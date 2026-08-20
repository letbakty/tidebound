# 17 — Постройки и производство: состояния, размещение, призрак, станции

**Для этапов:** 07 (весь), 08 (весь), 09 (`on_storm`, шлюзы/фонари как блокираторы), 14 (радиал стройки).
**Дата ресерча:** 2026-08-21. **Движок:** Godot 4.7.x stable.

---

## 1. Состояния постройки: три состояния + два ортогональных флага

Промпт 07 задаёт `PLANNED → UNDER_CONSTRUCTION → ACTIVE` и «отдельно флаги `flooded`, `damaged`». **Это принципиально: не пять состояний, а три + два флага.**

Почему так, а не enum из пяти значений: постройка может быть одновременно `ACTIVE + flooded + damaged`, и правила для каждого случая разные (затопленный горн не работает, но чинить его можно; сломанная лестница убирает ребро независимо от воды). Пять состояний дали бы комбинаторный взрыв.

```gdscript
# sim/building_system.gd
# building = {
#   id: int, def_id: String, cell: Vector2i, mark: int,
#   state: SimTypes.BuildState,        # PLANNED / UNDER_CONSTRUCTION / ACTIVE
#   flooded: bool, damaged: bool,
#   hp: int, progress_ticks: int,
#   buffer: Dictionary[String,int],    # принесённые материалы / входы станции
#   pending_jobs: Array[int],          # см. §6 — против дублей HAUL
# }

func is_working(b: Dictionary) -> bool:
	if b["state"] != SimTypes.BuildState.ACTIVE: return false
	if b["damaged"]: return false
	if b["flooded"] and DB.building(b["def_id"]).flood_rule == SimTypes.FloodRule.DISABLED:
		return false
	return true
```
**`is_working()` — единственная функция, которую спрашивают все остальные системы** (production, crisis, jobs, view). Если каждая система выведет «работает ли» сама, они разойдутся. `SimTypes.BuildState` придётся добавить в enum'ы — **это допустимое расширение контракта docs/02 §3.1, отметить в ответе этапа 07**.

---

## 2. Проверка размещения: сетка занятости вместо перебора

Наивный `can_place` перебирает все постройки и проверяет пересечение AABB. При 40 постройках × призрак, обновляемый каждый кадр (60 Гц), — 2400 проверок в секунду впустую.

**Правильно — словарь занятости:**
```gdscript
var _occupied: Dictionary[Vector2i, int] = {}     # cell -> building_id

func can_place(def_id: String, cell: Vector2i, w: SimWorld) -> bool:
	var d: BuildingDef = DB.building(def_id)
	if d == null: return false
	# 1) разблокировка
	if not d.unlock_id.is_empty() and not w.run_state.has_unlock(d.unlock_id):
		return false
	# 2) отметка
	var mark: int = WorldGeo.cell_to_mark(cell)
	if mark < d.min_mark or mark > d.max_mark: return false
	# 3) занятость и опора — один проход по клеткам постройки
	for dx: int in d.size.x:
		for dy: int in d.size.y:
			var c := cell + Vector2i(dx, dy)
			if _occupied.has(c): return false
			if not w.terrain.is_solid_ground(c + Vector2i(0, d.size.y)):
				return false                     # опора под всей шириной
	return true
```
`_occupied` обновляется в `place`/`remove` — двумя строками, а стоит O(1) при каждой проверке. **Призрак размещения (60 Гц) станет бесплатным.**

⚠️ **`for dx: int in d.size.x` работает** — итерация по int даёт 0..n-1. Это идиоматично для Godot 4 и короче `range()`.

⚠️ **Опора проверяется под нижним рядом**, поэтому `+ Vector2i(0, d.size.y)`. Классическая ошибка — проверить под `cell` (верхним углом) и разрешить постройку, висящую в воздухе.

**Порядок проверок — от дешёвых к дорогим и от «частых причин отказа» к редким.** Это же порядок, в котором надо возвращать причину для тултипа UI (этап 14). Стоит сразу возвращать не `bool`, а причину:
```gdscript
func place_error(def_id: String, cell: Vector2i, w: SimWorld) -> String:
	# "" = можно. Иначе i18n-ключ: "ERR_LOCKED"/"ERR_MARK"/"ERR_OCCUPIED"/"ERR_NO_SUPPORT"
```
`can_place()` тогда — обёртка `place_error(...).is_empty()`. Этап 14 получит подсказку «почему красный» бесплатно, вместо переписывания на 14-м.

---

## 3. Призрак размещения: снап, конверсия, обновление

```gdscript
# game/build_ghost.gd
extends Node2D

var _def_id: String = ""
var _valid: bool = false
var _last_cell: Vector2i = Vector2i(-9999, -9999)

func _process(_d: float) -> void:
	if _def_id.is_empty(): return
	var world_pos: Vector2 = get_global_mouse_position()
	var cell: Vector2i = WorldGeo.world_to_cell(world_pos)
	if cell == _last_cell:
		return                              # ничего не изменилось — не дёргаем sim
	_last_cell = cell
	_valid = Game.query_can_place(_def_id, cell)
	position = WorldGeo.cell_to_world(cell)  # снап к сетке
	modulate = Color(0.5, 1, 0.5, 0.6) if _valid else Color(1, 0.4, 0.4, 0.6)
	queue_redraw()
```

**Три технических момента:**
1. **Гейт `cell == _last_cell`** — призрак дёргает sim только при смене клетки, а не 60 раз в секунду. Обязательно.
2. **`get_global_mouse_position()` внутри SubViewport** возвращает координаты **этого вьюпорта**, а не окна — то, что нужно. Но только если нода — потомок `SubViewport`. Из UI-слоя пришлось бы переводить руками.
3. **`Game.query_can_place` — синхронное чтение sim.** Это тот же разрешённый «pull», что промпт 14 вводит для `AgentCard`. Записать в `Game` рядом с `query_agent`.

**Тач (этап 14/16):** позиция берётся не от мыши, а от последнего касания — `InputService.world_long_pressed(pos)`. Чтобы не писать две ветки, `build_ghost` должен иметь метод `set_cursor_world(pos: Vector2)`, а `_process` использовать мышь только если активен мышиный ввод (doc 20 §5).

**Линии до складов с материалами** (промпт 14, приём из Against the Storm): `Line2D` в мире, пересоздаются только при смене клетки — та же оптимизация, что и §3.1.

---

## 4. Лестницы и граф: единственная точка правды

Лестница — постройка, которая **регистрирует ребро в `Terrain`**. Три события меняют граф: `ACTIVE`, `damaged`, снос.

```gdscript
func _on_became_active(b: Dictionary, w: SimWorld) -> void:
	if DB.building(b["def_id"]).special == "ladder":
		b["edge_id"] = w.terrain.add_ladder(b["cell"])   # add_ladder бампает graph_version

func _on_became_broken(b: Dictionary, w: SimWorld) -> void:
	if b.has("edge_id"):
		w.terrain.remove_ladder(b["edge_id"])
		b.erase("edge_id")
```

⚠️ **`graph_version` обязан инкрементироваться в `add_ladder`/`remove_ladder`**, иначе агенты с закэшированным путём (research/15 §3) продолжат «идти по несуществующей лестнице» — и это не упадёт, а тихо телепортирует их. Приёмка этапа 07 требует «ребро лестницы исчезло из графа»; **дописать к ней проверку, что агент, шедший по этому ребру, перешёл в IDLE/RETURN**.

⚠️ **Помост расширяет площадку** — это не ребро, а изменение диапазона `x0..x1` существующей площадки. Значит `Terrain` должен уметь `extend_platform(platform_id, x0, x1)` и тоже бампать версию. Заложить сигнатуру на этапе 02 (или отметить как расширение на 07).

---

## 5. Затопление: пересечение, а не состояние

Полностью по паттерну doc 12 §5 (событие пересечения по двум уровням, эпсилон). Специфика построек:

```gdscript
func _on_flooded(b: Dictionary, w: SimWorld) -> void:
	b["flooded"] = true
	match DB.building(b["def_id"]).special:
		"evaporator": b["buffer"]["salt"] = 0                 # теряет накопленное
		"hearth":     b["lit"] = false                        # гаснет
		# "lantern", "sluice", "ladder" — работают под водой, ничего не делаем
	w.events_out.append(SimEvent.make("building_state_changed", {"id": b["id"]}))
```
⚠️ **Событие `building_state_changed` — только при реальной смене**, не каждый тик. Иначе HUD (этап 13, точки построек на шкале) будет перерисовываться 10 раз в секунду.

---

## 6. Дублирование HAUL-задач — главная ошибка этапа 07

Постройка в `PLANNED` каждый тик видит «не хватает 4 утиля» и просит доставку. За 10 тиков — 10 задач, 6 агентов растащат материалы по кругу.

**Лечение — учёт уже заказанного:**
```gdscript
func _request_materials(b: Dictionary, w: SimWorld) -> void:
	var need: Dictionary[String, int] = DB.building(b["def_id"]).cost.duplicate()
	for k: String in b["buffer"]:
		need[k] = need.get(k, 0) - int(b["buffer"][k])
	# вычесть то, что УЖЕ едет
	for jid: int in b["pending_jobs"]:
		var j: Dictionary = w.jobs.get_job(jid)
		if j.is_empty(): continue
		need[j["item_id"]] = need.get(j["item_id"], 0) - int(j["n"])
	for k: String in need:
		if need[k] > 0:
			var jid: int = w.jobs.request_haul(_source_for(k, w),
				{"kind": "building", "id": b["id"], "cell": b["cell"]}, k, need[k])
			if jid != -1:
				b["pending_jobs"].append(jid)
```
**И симметрично: при завершении/отмене задачи она удаляется из `pending_jobs`.** Без этого массив растёт вечно и попадает в сейв.

⚠️ Тот же паттерн — для **топлива очага/фонаря** и для **входов станций**. Три места, одна ошибка. **Стоит вынести в общий хелпер `MaterialRequester`** на этапе 07 — этап 08 тогда не пишет ничего нового.

---

## 7. Производство: буфер станции и порядок систем

**Ключ к цепочкам без ручных заказов** — материалы должны лежать **на станции**, а не «где-то на складе», до начала работы (промпт 08). То есть у станции есть `buffer`, и цикл такой:

```
входы на складе → HAUL в buffer станции → есть все входы + станция работает
  → STATION-задача → агент приходит → work_seconds × модификаторы → выход на склад
```

**Порядок систем `production → jobs → agents` (docs/02 §4) — не случайность:**
`production` в этом тике решает «станция готова, нужна STATION-задача» → `jobs` в этом же тике её публикует → `agents` могут её взять. Обратный порядок дал бы задержку в тик на каждом звене цепочки — при 3-звенной цепочке соли это 0.3 с, незаметно, но детерминированный порядок важнее.

### 7.1 Пассивные рецепты: привязка к границам фаз
```gdscript
# evaporator: +1 salt в конце LOW, если НЕ был затоплен всю LOW и не шторм
func _on_phase_ended(phase: SimTypes.Phase, w: SimWorld) -> void:
	if phase != SimTypes.Phase.LOW: return
	for b: Dictionary in _stations_with_special("evaporator"):
		if b["flooded_during_phase"]: continue
		if w.crisis.is_active(SimTypes.CrisisType.STORM): continue
		if not is_working(b): continue
		_output(b, "salt", 1, w)
```
⚠️ **Флаг `flooded_during_phase` нужен именно как «был ли затоплен хоть раз за фазу»**, а не «затоплен сейчас». Приёмка: «испаритель, затопленный на середине LOW, соль в этом цикле не даёт». Сбрасывать на входе в LOW. **Один булев флаг в постройке, сериализуемый.**

⚠️ «Конец LOW» — это момент перехода `LOW → SIGNAL` в `SimClock`. `SimClock.tick()` должен возвращать событие `phase_changed` **с указанием прошлой фазы**, иначе `production` не сможет отличить «конец LOW» от «начало SIGNAL» без собственного отслеживания. **Заложить `{"phase": int, "prev": int, "cycle": int}` в данные события на этапе 01** — потом переделывать дороже.

### 7.2 Индекс рецептов
```gdscript
var _by_station: Dictionary[String, Array] = {}      # special -> Array[RecipeDef]

static func _build_index() -> void:
	for rid: String in DB.recipe_ids():
		var r: RecipeDef = DB.recipe(rid)
		if not _by_station.has(r.station_special):
			_by_station[r.station_special] = []
		_by_station[r.station_special].append(r)
	for k: String in _by_station:
		_by_station[k].sort_custom(func(a: RecipeDef, b: RecipeDef) -> bool:
			return a.id < b.id)                       # тотальный компаратор: id уникален
```
**Выбор рецепта при нескольких доступных — первый по отсортированному id**, у которого хватает входов. Не «лучший», не «случайный» — детерминированный. Если позже понадобится приоритет, добавить поле `priority: int` в `RecipeDef` и сортировать по `(priority, id)`.

### 7.3 Мокрый плавник
`inputs: {"driftwood": 1}` — но горн принимает только сухой. Значит проверка входов обязана смотреть на `wet` в стаке, а не только на `item_id`:
```gdscript
func _has_inputs(b: Dictionary, r: RecipeDef, w: SimWorld) -> bool:
	for k: String in r.inputs:
		var need: int = r.inputs[k]
		# У сушила отдельный рецепт: он-то как раз принимает мокрое.
		var dry_only: bool = (k == "driftwood" and r.station_special != "dryer")
		if _buffer_count(b, k, dry_only) < need:
			return false
	return true
```
⚠️ Обобщать «сухость» на все предметы не надо — это правило только про плавник и волокно (`FloodRule.WET`). **Правило: `dry_only = DB.item(k).flood_rule == WET and r.station_special != "dryer"`** — так оно выводится из данных, а не из хардкода id.

---

## 8. Шторм и hp

```gdscript
func on_storm(w: SimWorld) -> void:
	for id: int in _order:                       # отсортированный порядок — детерминизм
		var b: Dictionary = _buildings[id]
		var d: BuildingDef = DB.building(b["def_id"])
		if not d.storm_breaks: continue
		if b["mark"] >= 3: continue              # +3 и выше — цело
		if d.special == "dryer":
			_destroy(b, w, refund = 0)           # сушило — в ноль, без возврата
			continue
		b["hp"] -= 1
		if b["hp"] <= 0:
			b["damaged"] = true
			_on_became_broken(b, w)              # снимет ребро лестницы
		w.events_out.append(SimEvent.make("building_state_changed", {"id": id}))
```
⚠️ **`hp` у большинства построек = 1** (дефолт `BuildingDef.hp`), у склада = 2 («переживает 2 шторма»). То есть механика одна, различие — в данных. Не писать спецкейс для склада.

⚠️ **`on_storm` вызывается из `SimWorld` по событию `crisis_started(STORM)`**, а не подпиской (сигналов в sim нет). Промпт 07 просит именно метод — это правильно.

---

## 9. Снос и возврат материалов

```gdscript
func demolish(id: int, w: SimWorld) -> void:
	var b: Dictionary = _buildings[id]
	var cost: Dictionary = DB.building(b["def_id"]).cost
	for k: String in cost:
		var n: int = int(cost[k]) / 2                    # окр. вниз, целочисленно
		if n > 0:
			w.storage.drop(_free_cell_near(b["cell"], w), StackUtil.make(k, n))
	_unregister(b, w)
```
⚠️ **`int(x) / 2` в GDScript при обоих int даёт целочисленное деление** — это то, что нужно («окр. вниз»). Но `4 / 2.0` даст float. Явно приводить оба операнда к int.

⚠️ **`_free_cell_near` может не найти места** (всё занято/затоплено). Не терять материалы молча: если места нет — класть на клетку постройки и эмитить предупреждение-событие. То же правило в промпте 08 для выхода станции без складов.

---

## 10. Чек-лист приёмки этапов 07 и 08

**07:**
- [ ] `can_place`/`place_error` даёт правильный ключ ошибки на все 4 причины.
- [ ] Полный цикл place → HAUL → BUILD → ACTIVE проходит headless за разумное число тиков.
- [ ] **Дублей HAUL нет**: на PLANNED-постройку за 100 тиков создано ровно `need` задач, не 100×.
- [ ] Затопление: горн не работает, лестница работает, испаритель обнулил соль.
- [ ] `on_storm`: сушило разрушено в ноль, деревянная лестница ниже +3 сломана, стальная цела, ребро исчезло из графа, **агент на этом ребре не завис**.
- [ ] Снос вернул ровно 50% (округление вниз), материалы не потеряны.
- [ ] Детерминизм-прогон зелёный.

**08:**
- [ ] Цепочка соли даёт ≥2 rations к концу 3-го цикла.
- [ ] Цепочка металла: утиль+сухой плавник → слитки → детали.
- [ ] Мокрый плавник горн не принимает; после сушила — принимает (проверка через `_has_inputs`, а не через хардкод).
- [ ] Испаритель, затопленный в середине LOW, соли не даёт (флаг `flooded_during_phase`).
- [ ] Кузнец быстрее на 25% — замер в **тиках**, не в секундах.
- [ ] Выход станции без складов уходит на землю **и эмитит предупреждение**.

---

## Источники

- [AStar2D](https://docs.godotengine.org/en/stable/classes/class_astar2d.html) — рёбра лестниц: `connect_points`/`disconnect_points`
- [Dictionary](https://docs.godotengine.org/en/stable/classes/class_dictionary.html) — `duplicate()` перед мутацией `cost`
- [GDScript reference](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html) — целочисленное деление, `for i: int in n`
- [Oxygen Not Included — Errand](https://oxygennotincluded.fandom.com/wiki/Errand) — буфер станции и доставка входов как отдельная работа: та же модель
- research/16 — резервирование и `request_haul`, на которых стоит вся стройка
