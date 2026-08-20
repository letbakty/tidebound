# 15 — Агенты: FSM без нод, потребности, View-синхронизация, хит-тест

**Для этапов:** 05 (весь), 06 (WORK/HAUL/GATHER поверх этой FSM), 09 (паника от существ), 13/14 (AgentChip, AgentCard).
**Дата ресерча:** 2026-08-21. **Движок:** Godot 4.7.x stable.

---

## 1. FSM в `sim/`: три варианта и почему выбран первый

| Вариант | Как | Сериализация | Вердикт |
|---|---|---|---|
| **A. enum + `match`** | `state: SimTypes.AgentState`, диспетчер `match state:` | `int` — тривиально | **берём** |
| B. Объекты-состояния | `var state: AgentStateBase`, полиморфизм | объект → нужен `state_id` рядом, дублирование | лишний слой |
| C. Node-based FSM / аддон (LimboAI, Beehave) | ноды-состояния, деревья поведения | ноды в `sim/` запрещены | **нельзя** |

Вариант C заслуживает отдельного слова, потому что это стандартный совет из интернета. [LimboAI](https://github.com/limbonaut/limboai) и [Beehave](https://github.com/bitbrain/beehave) — хорошие аддоны, но оба построены на нодах и `_process`, то есть **несовместимы с архитектурой docs/02 §1** (sim без нод, фиксированный тик, сериализуемость). Заимствовать у них стоит только идею **дерева приоритетов** — она реализована у нас в скоринге работ (doc 16), а не в FSM.

**Ключевой аргумент за A:** состояние агента обязано попадать в `to_dict()` (этап 11) и восстанавливаться побитово. `int` из enum — единственный вариант, где это бесплатно.

---

## 2. Каркас FSM: приоритетные прерывания + обычные переходы

Ошибка, которую легко сделать: свалить всё в один `match` и получить агента, который тонет, но продолжает идти на работу.

**Правильная структура — два уровня:**

```gdscript
class_name AgentSystem
extends RefCounted

func _tick_agent(a: SimAgent, w: SimWorld) -> void:
	# --- Уровень 1: безусловные прерывания. Порядок = приоритет. ---
	if a.state == SimTypes.AgentState.DEAD:
		return
	if _check_drowning(a, w):        return   # вода важнее всего
	if _check_panic(a, w):           return   # существо/mood<30
	if _check_recall(a, w):          return   # отзыв игрока
	# --- Уровень 2: обычная работа состояния ---
	match a.state:
		SimTypes.AgentState.IDLE:   _do_idle(a, w)
		SimTypes.AgentState.GOTO:   _do_goto(a, w)
		SimTypes.AgentState.RETURN: _do_return(a, w)
		SimTypes.AgentState.REST:   _do_rest(a, w)
		SimTypes.AgentState.EAT:    _do_eat(a, w)
		SimTypes.AgentState.GATHER: _do_gather(a, w)     # этап 06
		SimTypes.AgentState.HAUL:   _do_haul(a, w)       # этап 06
		SimTypes.AgentState.WORK:   _do_work(a, w)       # этап 08
		_: pass
```

**Почему `_check_*` возвращают `bool` и делают `return`:** прерывание должно съесть тик целиком. Иначе агент за один тик успеет и запаниковать, и пройти два шага — а это уже недетерминированный порядок эффектов.

### 2.1 `set_state` — единственная точка смены

```gdscript
func _set_state(a: SimAgent, s: SimTypes.AgentState, w: SimWorld) -> void:
	if a.state == s:
		return
	_on_exit(a, a.state, w)
	a.state = s
	a.state_ticks = 0
	_on_enter(a, s, w)
	# Событие наружу — но НЕ чаще раза в секунду на агента (промпт 05).
	_queue_agent_updated(a, w)
```
`state_ticks` (сколько тиков в текущем состоянии) нужен почти каждому состоянию (работа за 2 с, еда, отдых) и **обязан сериализоваться**. Забыть его — значит после загрузки получить агента, который начинает добычу заново.

⚠️ **`_on_enter` не должен вызывать `_set_state` рекурсивно.** Если у `EAT` нет еды, соблазн сразу перейти в `IDLE` из `_on_enter` — так получается цепочка вложенных переходов и неочевидный порядок событий. **Правильно: `_on_enter` только настраивает данные; решение «состояние невозможно» принимается на следующем тике в `_do_*`.** Стоит одного лишнего тика (0.1 с) и снимает целый класс багов.

### 2.2 Троттлинг `agent_updated`
```gdscript
func _queue_agent_updated(a: SimAgent, w: SimWorld) -> void:
	# 10 тиков = 1 секунда. Гарантия из промпта 05: "не чаще 1/с на агента".
	if w.clock.total_ticks() - a.last_update_tick < Balance.TICKS_PER_SEC:
		a.update_pending = true
		return
	a.last_update_tick = w.clock.total_ticks()
	a.update_pending = false
	w.events_out.append(SimEvent.make("agent_updated", {"id": a.id}))
```
⚠️ **Флаг `update_pending` обязателен**, иначе последнее изменение перед «тишиной» потеряется и UI застынет на устаревшем состоянии. Сбрасывать отложенные апдейты — в конце тика системы, одним проходом.

---

## 3. Движение по графу: тики, а не дельты

```gdscript
# Скорость 2.0 тайла/сек при 10 тиках/сек = 0.2 тайла за тик.
# Считаем в тайлах (float, 64-bit), НЕ в пикселях и НЕ в Vector2 (research/11 §1.2).
func _advance(a: SimAgent, w: SimWorld) -> void:
	var on_ladder: bool = _is_ladder_edge(a)
	var base: float = Balance.LADDER_SPEED if on_ladder else Balance.WALK_SPEED
	var mult: float = a.modifier("ladder_speed_mult" if on_ladder else "speed_mult")
	mult *= w.cycle_modifiers.get("haul_speed_mult", 1.0)      # карты, этап 10
	var step: float = base * mult / float(Balance.TICKS_PER_SEC)
	a.x += step * signf(a.target_x - a.x)
	if absf(a.target_x - a.x) <= step:
		a.x = a.target_x
		_arrive_at_node(a, w)
```

**Три технических правила:**
1. **`a.x` — координата вдоль площадки в тайлах**, а не мировой пиксель. Пиксели — забота View (`WorldGeo.cell_to_world`). Это защищает sim от изменений размера тайла на этапе 18.
2. **Проверка прибытия через `absf(delta) <= step`, а не `a.x == target`.** Равенство float'ов не наступит.
3. **Модификаторы перемножаются, а не складываются**, и порядок перемножения фиксирован (черты → карты цикла → маяк). Разный порядок даёт разный float — см. research/11 §1.

**Кэш пути.** Промпт 05 требует движения по `Array[platform_id]`. Путь пересчитывать **только** при: смене цели, изменении `graph_version` (сломалась/построилась лестница), недостижимости. Хранить в агенте:
```gdscript
var path: Array[int] = []
var path_idx: int = 0
var path_graph_version: int = -1
```
Проверка `if a.path_graph_version != w.terrain.graph_version: _repath(a)` — одна строка, но она закрывает «агент идёт по лестнице, которую сломал шторм» (этап 09).

---

## 4. Потребности: целочисленно и с гистерезисом

Пересчёт «за цикл → за тик» — см. research/11 §1.3 (целочисленный остаток). Здесь — про поведение.

**Гистерезис обязателен.** Промпт задаёт порог «<30 — эффекты». Если агент идёт есть при satiety<30 и перестаёт при >=30, он у порога будет дёргаться туда-сюда каждый тик:
```gdscript
const HUNGRY_ENTER: int = 30_000     # милли-единицы
const HUNGRY_EXIT: int  = 55_000     # выше порога входа => нет дребезга
```
Это же правило для warmth (уход от очага) и mood (выход из паники). **Без гистерезиса приёмка «голодный агент идёт есть; satiety +60» пройдёт, а в игре агенты будут стоять у склада и вибрировать.**

**События Духа (mood):** смерть соседа −25, сырая еда −5, реликвия +10 всем (этап 06), существо рядом −10 раз за цикл на агента. Последнее требует **флага «уже испугался в этом цикле»** в агенте и его сброса на `cycle_started` — иначе −10 будет каждые 10 тиков.

---

## 5. Утопление: счётчик, а не мгновенная смерть

```gdscript
func _check_drowning(a: SimAgent, w: SimWorld) -> bool:
	var cell: Vector2i = _cell_of(a)
	if not w.terrain.is_flooded(cell, w.tide.level):
		a.submerged_ticks = 0            # вышел — сброс (промпт 05)
		return false
	a.wet = true
	a.submerged_ticks += 1
	var limit_sec: float = a.modifier("drown_seconds",
		Balance.DROWN_GEAR_SEC if a.has_gear else Balance.DROWN_SEC)
	var limit: int = int(limit_sec * Balance.TICKS_PER_SEC)
	# Предупреждение за 2 с до смерти — ровно один раз.
	if a.submerged_ticks == limit - 2 * Balance.TICKS_PER_SEC:
		w.events_out.append(SimEvent.make("agent_drowning", {"id": a.id}))
	if a.submerged_ticks >= limit:
		_kill(a, "drown", w)
	_set_state(a, SimTypes.AgentState.DROWNING, w)
	return true
```

⚠️ **`modifier("drown_seconds", default)` — сигнатура с дефолтом обязательна.** У черты `drown_seconds` семантика «заменить», а не «умножить» — в отличие от `*_mult`. **Это единственное исключение среди 21 ключа, и его надо описать комментарием**, иначе следующий агент свернёт всё в один множитель и Ныряльщик сломается.

⚠️ **`== limit - 20`, а не `>=`** — иначе событие полетит каждый тик последние две секунды.

⚠️ **Порядок систем важен.** `is_flooded` читает `w.tide.level` **этого** тика, а `tide` обновляется до `agents` (docs/02 §4: `clock → tide → crisis → production → jobs → agents → storage → run_state`). Это правильно и менять нельзя.

---

## 6. View-слой: создание, удаление, интерполяция

### 6.1 Дерево и Y-sort
```
World (Node2D)
└── Agents (Node2D, y_sort_enabled = true)
    ├── AgentView#1 (Node2D)
    └── ...
```
`y_sort_enabled` на **контейнере**: тогда дети сортируются по своему `position.y`. У самих `AgentView` его включать не надо (сортировка внутри одного агента бессмысленна и стоит производительности).

⚠️ Y-sort и `Parallax2D` не дружат (баг #113092, уже в research/00) — параллакс только в фоновых слоях, вне `Agents`.

### 6.2 Синхронизация: словарь id → нода
```gdscript
var _views: Dictionary[int, AgentView] = {}

func _on_agent_spawned(id: int) -> void:
	var v: AgentView = AGENT_SCENE.instantiate()
	v.setup(id)
	add_child(v)
	_views[id] = v

func _on_agent_died(id: int, cause: String) -> void:
	var v: AgentView = _views.get(id, null)
	if v == null: return
	_views.erase(id)
	v.play_death_and_free(cause)      # сама себя queue_free после анимации
```
⚠️ **`erase` из словаря ДО анимации смерти.** Иначе `rebroadcast_state` после загрузки (этап 11) создаст второй view для того же id, а первый ещё доигрывает — и в мире будет два трупа.

⚠️ **Утечки View — пункт приёмки этапа 19 (п.4).** Здесь единственное место, где они рождаются. Правило: **`_views` очищается полностью на `run_ended` и на `run_started`**, а не по одному.

### 6.3 Интерполяция без физической интерполяции движка
Sim двигает агента 10 раз в секунду, экран рисует 60. Без сглаживания движение будет ступенчатым.

```gdscript
# agent_view.gd
var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _t: float = 0.0

func set_target(world_pos: Vector2) -> void:
	_from = position
	_to = world_pos
	_t = 0.0

func _process(delta: float) -> void:
	if Game.speed == 0:
		return                                  # на паузе не доезжаем: пауза видна
	_t = minf(_t + delta * float(Balance.TICKS_PER_SEC) * float(Game.speed), 1.0)
	position = _from.lerp(_to, _t)
```
**Почему не `Camera2D`/`physics_interpolation`:** встроенная интерполяция движка работает по физическим кадрам и не знает про наш `speed` (×2/×3). Своя `lerp` — 6 строк и полностью управляема.

⚠️ **`if Game.speed == 0: return` — не мелочь.** Иначе на тактической паузе агенты продолжат «доезжать» ещё 0.1 с, и пауза будет читаться как «подтормаживание», а не как остановка. Это та же логика, что и запрет `TIME` в шейдерах (research/05).

**Позиция для View приходит из события или запрашивается?** Промпт 05 требует событий (`agent_updated` не чаще 1/с) — но 1 Гц слишком редко для плавного движения. **Решение: `AgentView` тянет позицию раз в кадр через `Game.query_agent_pos(id) -> Vector2`** — синхронное чтение из sim, тот же разрешённый «pull», что промпт 14 вводит для `AgentCard`. `agent_updated` остаётся для смены **состояния**, а не позиции. Записать как `# РЕШЕНИЕ:` — промпт этого явно не оговаривает, а без этого агенты будут телепортироваться раз в секунду.

### 6.4 Флип спрайта: не через `scale.x = -1`
```gdscript
sprite.flip_h = (dir < 0)          # ХОРОШО
# node.scale.x = -1                # ПЛОХО
```
Отрицательный `scale` на родителе ломает Y-sort, инвертирует детей (иконку состояния над головой) и на пиксель-арте даёт сдвиг на 1 px при нечётной ширине спрайта. `flip_h` у `Sprite2D` разворачивает только текстуру.

⚠️ У `Sprite2D` с нечётной шириной `flip_h` смещает изображение на 1 px, если `centered = true` и позиция дробная. Держать спрайты **чётной ширины** (16, 32) и позиции целочисленными.

### 6.5 Двухкадровая «анимация» без AnimatedSprite2D
Промпт 05 разрешает заглушку. Дешевле всего — покачивание без второго кадра:
```gdscript
func _process(_d: float) -> void:
	if _moving:
		# Шаг привязан к сим-времени, а не к TIME: на паузе замирает.
		var phase: float = Game.sim_seconds() * 6.0
		sprite.position.y = -1.0 if fmod(phase, 2.0) < 1.0 else 0.0
```
Целочисленное смещение (0/−1 px), а не синус: дробное смещение в пиксель-арте даёт мыло.

### 6.6 Бюджет нод
6 агентов + ~40 построек + существа + депозиты + тайлмапы ≈ **сотня нод в мире.** Док CPU optimization говорит о тысячах-десятках тысяч как о пределе — у нас запас в 100×. **Пул объектов не нужен, `queue_free`/`instantiate` по событию — нормально.** Единственное исключение — брызги на этапе 18 (там пул уже заложен в research/04).

---

## 7. Клик по агенту без физики

docs/02 §1 запрещает физику. Значит `Area2D` + `input_event` — мимо. Хит-тест руками:

```gdscript
# world.gd — подписан на InputService.world_tapped(screen_pos)
func _on_world_tapped(screen_pos: Vector2) -> void:
	var world_pos: Vector2 = _screen_to_world(screen_pos)
	var hit_id: int = -1
	var best_y: float = -INF
	for id: int in _agent_views:
		var v: AgentView = _agent_views[id]
		var r := Rect2(v.position - Vector2(8, 24), Vector2(16, 24))
		# Верхний по Y-sort выигрывает — тот же порядок, что видит игрок
		if r.has_point(world_pos) and v.position.y > best_y:
			best_y = v.position.y
			hit_id = id
	if hit_id >= 0:
		Events.ui_panel_opened.emit("agent_stub")
```

**Порядок проверки — по убыванию Y**, чтобы клик попадал в того, кто нарисован сверху. Иначе игрок будет попадать «сквозь» ближнего агента в дальнего.

**Приоритет целей при хит-тесте (важно для этапов 07/14):** агент → постройка → склад → пустая клетка. Один список, один проход, ранний выход. **Написать это как единственную функцию `World.pick_at(world_pos) -> Dictionary` на этапе 05** — этапы 07 (призрак), 09 (существа), 14 (панели складов/агентов) её просто переиспользуют вместо трёх разных хит-тестов.

```gdscript
func pick_at(world_pos: Vector2) -> Dictionary:
	# {"kind": "agent"|"building"|"storage"|"creature"|"cell", "id": int, "cell": Vector2i}
	...
```

---

## 8. Чек-лист приёмки этапа 05

- [ ] Агент проходит −8 → +6 за расчётное время ±10% (тест меряет тики, не секунды).
- [ ] Утопление: 5 с без gear, 20 с с gear, счётчик сбрасывается при выходе из воды.
- [ ] `agent_drowning` эмитится **ровно один раз** на утопление.
- [ ] Голод/тепло не дребезжат у порога (прогнать 3000 тиков, посчитать смены состояния — должно быть единицы, не сотни).
- [ ] `recall(hard)` бросает стаки; после отзыва с −4 никто не остаётся ниже 0 к началу HIGH.
- [ ] `agent_updated` не чаще 1/с на агента (тест считает события за 100 тиков: ≤ 6×10).
- [ ] Детерминизм: 20 000 тиков, два прогона, одинаковый хеш.
- [ ] Нет утечек View: после `run_ended` `print_orphan_nodes()` пуст (заготовка к этапу 19).

---

## Источники и аналоги

- [GDScript reference](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html) — enum, match, лямбды
- [CPU optimization](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html) — бюджет числа нод
- [LimboAI](https://github.com/limbonaut/limboai) / [Beehave](https://github.com/bitbrain/beehave) — эталонные FSM/BT-аддоны для Godot; **нам не подходят** (ноды + `_process`), но их структура приоритетов — прообраз нашего скоринга (doc 16)
- [The Genius AI Behind The Sims — GMTK](https://gmtk.substack.com/p/the-genius-ai-behind-the-sims) — «объекты рекламируют себя», прототип нашей модели «депозит порождает задачу», а не «агент ищет депозит»
- [godot#113092](https://github.com/godotengine/godot/issues/113092) — Y-sort и клоны Parallax2D
