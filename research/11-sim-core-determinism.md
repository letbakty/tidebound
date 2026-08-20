# 11 — Ядро симуляции: детерминизм, тик, типы данных, производительность GDScript

**Для этапов:** 01 (весь), 19 (п.2 санитария детерминизма), фон для 05–11.
**Дата ресерча:** 2026-08-21. **Движок:** Godot 4.7.x stable.

Это самый дорогой к ошибке документ: рассинхрон, найденный на этапе 11 или 19, стоит переписывания половины `sim/`. Всё ниже — про то, чтобы этого не случилось.

---

## 1. Шесть источников недетерминизма в GDScript (и как каждый закрыть)

| # | Источник | Почему ломает | Правило проекта |
|---|---|---|---|
| 1 | `randi()/randf()/randomize()` | глобальный RNG движка, сидируется системным временем | только `SimRNG`; grep-аудит на этапе 19 |
| 2 | `Array.sort_custom()` | **сортировка НЕ стабильна** (док Array: «values considered equal may have their order changed») | компаратор обязан быть *тотальным*: последним ключом всегда `id` |
| 3 | Порядок обхода словаря | insertion order сохраняется, но зависит от порядка вставки, который может отличаться после `from_dict` | сериализовать словари как отсортированные массивы пар **или** восстанавливать вставку в порядке `id` |
| 4 | Накопление float | сложение в разном порядке даёт разный результат | все счётчики — `int` (тики); `float` только там, где есть допуск (позиция, потребности) |
| 5 | `Time.*`, `delta`, `OS.*` | зависят от железа | в `sim/` запрещены; вход в тик — только номер тика |
| 6 | Итерация по «живым объектам» в порядке словаря/удаления | удаление элемента в середине цикла меняет порядок | итерация только по отсортированному `Array[int]` id, удаление — отложенно, в конце тика |

### 1.1 Про `sort_custom` — самая коварная

Документация Array прямо говорит: *«The sorting algorithm used is not stable.»* Значит две задачи с одинаковым `score` могут поменяться местами между прогонами — и агенты пойдут в разные места.

**Лечение — тотальный компаратор.** Никогда не сравнивать только по одному полю:

```gdscript
# ПЛОХО: при равных score порядок не определён
jobs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
	return a["score"] > b["score"])

# ХОРОШО: ничья разрешается стабильным ключом
jobs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
	if not is_equal_approx(a["score"], b["score"]):
		return a["score"] > b["score"]
	return a["id"] < b["id"])          # id уникален => порядок однозначен
```

⚠️ `is_equal_approx` внутри компаратора — само по себе риск (нарушает транзитивность при цепочке близких значений). Надёжнее — **квантовать score до целого** перед сортировкой:

```gdscript
# score хранится как int «в сотых»: устраняет и float-дрожь, и проблему компаратора
var q: int = int(round(score * 100.0))
```

Это же квантование делает `to_dict()` устойчивым к float-мусору. **Рекомендация: скоринг работ (этап 06) считать во float, но кэшировать в задаче как `score_q: int`.**

### 1.2 Про float

GDScript `float` = 64-битный `double` (док GDScript: *«stored as a 64-bit value, equivalent to `double` in C++»`*). Это хорошая новость — точности навалом.

Плохая новость: **`Vector2` / `Vector2i`-компоненты — не `double`.** В стандартной (single-precision) сборке движка `Vector2.x` это 32-битный float. Значит:

```gdscript
# ПЛОХО: позиция агента в Vector2 => 32-битное накопление, дрожь на длинных прогонах
agent.pos += dir * speed * dt

# ХОРОШО: позиция по площадке — обычный float (double) + целочисленный platform_id
var platform_id: int = 3
var x: float = 12.34          # 64-bit
```

Промпт 05 уже задаёт `позиция (platform_id + x: float)` — это архитектурно верно, и вот техническая причина. **Vector2 в `sim/` использовать только как «мёртвые» координаты клетки (`Vector2i`), никогда — как накопитель.**

### 1.3 Про «за цикл → за тик»

Промпт 05 требует пересчёта: `X за цикл = X/3000 за тик`. Деление даёт бесконечную дробь (например 10/3000). Складывать её 3000 раз — накопить ошибку.

**Лучше: хранить потребность в целых «милли-единицах» и вычитать целое.**
```gdscript
# satiety_milli: int, 0..100000 (100.0 * 1000)
# расход 10 единиц за цикл = 10000 милли / 3000 тиков = 3.333 -> дробь
# Решение: накапливать остаток целочисленно
var per_cycle_milli: int = 10000
agent.satiety_milli -= per_cycle_milli / Balance.TICKS_PER_CYCLE          # 3
agent._satiety_rem += per_cycle_milli % Balance.TICKS_PER_CYCLE           # 1000
if agent._satiety_rem >= Balance.TICKS_PER_CYCLE:
	agent._satiety_rem -= Balance.TICKS_PER_CYCLE
	agent.satiety_milli -= 1
```
Это **полностью целочисленно и абсолютно детерминировано**, а наружу отдаётся `satiety() -> float { return satiety_milli / 1000.0 }`.

⚠️ Это усложнение. Оно оправдано, если приёмка требует побитового совпадения `to_dict` после 20 000 тиков (а промпты 05/06/11 требуют). **Компромисс, если хочется проще:** оставить float, но в `to_dict()` округлять до 3 знаков (`snappedf(v, 0.001)`) и сравнивать хеш от округлённого. Тогда `from_dict` вернёт округлённое значение и продолжение симуляции **разойдётся** с непрерывным прогоном — а приёмка этапа 11 требует именно совпадения хешей после save→load. Значит: **либо целочисленные потребности, либо `full_precision` в сейве (см. doc 18 §2).**

---

## 2. Хеш состояния: как правильно

Приёмка этапов 01/05/06/11 требует «одинаковый `JSON.stringify(to_dict())`».

**Факты по `JSON.stringify` (4.7):**
```gdscript
static String stringify(data: Variant, indent: String = "", sort_keys: bool = true, full_precision: bool = false)
```
- `sort_keys = true` **по умолчанию** — то есть порядок ключей в строке нормализован. Отлично: разный insertion order словарей уже не ломает сравнение строк.
- `full_precision = false` **по умолчанию** — float печатается с усечением. Для *сравнения* это даже плюс (гасит шум), для *сейва* — катастрофа (см. doc 18).
- «Non-finite numbers are not supported in JSON» — `NAN`/`INF` сериализуются как `null`. ⚠️ **Прямо касается `tide.level_override: float = NAN` из промпта 03!** В `to_dict` его надо конвертировать: `is_nan(v) ? null : v`, а на чтении обратно.

**Рекомендуемый хелпер (в `tests/`, не в `sim/`):**
```gdscript
static func state_hash(world: SimWorld) -> String:
	# sort_keys=true по умолчанию => порядок ключей стабилен
	# full_precision=false => гасит float-шум ниже значимого
	return JSON.stringify(world.to_dict()).sha256_text()
```
`String.sha256_text()` есть в 4.x и возвращает hex-строку — удобнее сравнивать и печатать в CSV soak-теста (этап 19).

⚠️ **Не использовать `Dictionary.hash()`** для этой цели: док Dictionary — *«Dictionaries with the same entries but in a different order will not have the same hash»*. То есть штатный хеш словаря **чувствителен к порядку вставки** и даст ложные расхождения после `from_dict`.

---

## 3. Цикл тика: аккумулятор, «спираль смерти», пауза

Схема из docs/02 §4 верна, но у неё два известных дефекта, которые надо закрыть на этапе 01.

```gdscript
extends Node
## autoload/game.gd

const TICKS_PER_SEC: int = 10
const STEP: float = 1.0 / TICKS_PER_SEC
const MAX_TICKS_PER_FRAME: int = 12   # защита от спирали смерти

var speed: int = 0
var world: SimWorld = null
var _accum: float = 0.0
var _tick_budget_ms: float = 0.0      # для графика в дебаг-панели (этап 18 п.10)

func _physics_process(delta: float) -> void:
	if speed == 0 or world == null:
		return
	_accum += delta * float(speed)
	var steps: int = 0
	var t0: int = Time.get_ticks_usec()
	while _accum >= STEP and steps < MAX_TICKS_PER_FRAME:
		_accum -= STEP
		steps += 1
		world.tick()
		_flush_events()
	if steps >= MAX_TICKS_PER_FRAME:
		# Не догоняем: сбрасываем долг, иначе кадр за кадром будет всё хуже.
		_accum = 0.0
	_tick_budget_ms = float(Time.get_ticks_usec() - t0) / 1000.0

## Дробное сим-время для шейдеров (research/05-shader-time-and-pause.md).
func sim_seconds() -> float:
	if world == null:
		return 0.0
	return float(world.clock.total_ticks()) * STEP + _accum
```

**Дефект 1 — спираль смерти.** Если один тик стал тяжёлым (12 циклов, 6 агентов, стройка), `_accum` растёт быстрее, чем выгребается, и игра «залипает». `MAX_TICKS_PER_FRAME` + сброс долга решают это ценой замедления симуляции — что правильно: лучше играть медленнее, чем зависнуть.

**Дефект 2 — `_flush_events()` внутри цикла.** При speed=3 за кадр может пройти 3 тика и 3 пачки сигналов; UI получит три `water_level_changed` подряд в одном кадре. Это не ошибка, но лишняя работа. **Дешёвая оптимизация: копить `events_out` за все тики кадра и flush один раз в конце** — с оговоркой, что порядок событий сохраняется. ⚠️ Не делать на этапе 01, если это усложнит: сначала корректность.

**Пауза.** `get_tree().paused` мы **не используем** (docs/01 §6): `speed = 0` просто не тикает мир. Следствия:
- Tween'ы, частицы и `TIME` в шейдерах продолжат идти → см. research/05 про `sim_time`.
- UI остаётся полностью живым на паузе (это фича: «тактическая пауза»).
- `Engine.time_scale` не трогаем никогда: он ломает и Tween'ы, и звук.

**`_physics_process`, а не `_process`** — потому что `delta` там фиксированная (1/60), а значит `_accum` набегает предсказуемо. Это не даёт детерминизма (число тиков за кадр всё равно зависит от лагов), но детерминизм нам нужен **внутри `world.tick()`**, а не в том, сколько раз его вызвали.

---

## 4. Классы `sim/`: что можно, чего нельзя

**Базовый класс — `RefCounted`** (по умолчанию, если написать просто `class_name X`). Не `Object` (утечёт), не `Resource` (потянет ResourceLoader и кэш), не `Node`.

```gdscript
class_name SimClock
extends RefCounted   # писать явно: читаемее и защищает от случайного extends Node
```

**Что доступно в `sim/` и не нарушает правил:**
- `RandomNumberGenerator` — внутри `SimRNG`. Это `RefCounted`, детерминирован при заданном `seed`, состояние читается/пишется через `rng.state: int`.
- **`AStar2D` / `AStarGrid2D` — тоже `RefCounted`, их можно использовать в `sim/`.** См. doc 16 §2: для нашего графа площадок это готовый C++-ускоренный поиск пути вместо ручного BFS. Док явно отмечает детерминизм тай-брейка в `get_closest_point`: *«If several points are the closest… the one with the smallest ID will be returned, ensuring a deterministic result.»*
- `JSON`, `Marshalls`, `String`, `Vector2i`, `PackedInt32Array` — чистые типы, можно.
- **`@abstract`** (с 4.5) — годится для базового класса системы: `@abstract class_name SimSystem`. Даёт ошибку при попытке инстанцировать.
- **Статические переменные и функции** (с 4.4) — годятся для `Balance` и утилит. ⚠️ Статическая переменная — глобальное изменяемое состояние, **в `sim/` держать только `const`**, иначе два `SimWorld` в тесте детерминизма будут делить состояние и тест станет ложно-зелёным.

**Чего в `sim/` нет и не должно быть:** `Node`, `get_tree()`, `await`, `Timer`, `Time.*`, `print`, `signal` (наружу — только `events_out`), `preload` сцен, `Callable` на методы нод.

⚠️ **`signal` в `sim/` — отдельный соблазн.** RefCounted умеет сигналы, и хочется сделать `signal agent_died`. Не делать: сигнал вызывается синхронно посреди тика, слушатель может изменить состояние → порядок систем поедет. `events_out` — очередь, разбираемая после тика, это и есть защита.

---

## 5. `SimEvent`: структура и цена

```gdscript
class_name SimEvent
extends RefCounted

var type: String
var data: Dictionary

static func make(p_type: String, p_data: Dictionary = {}) -> SimEvent:
	var e := SimEvent.new()
	e.type = p_type
	e.data = p_data
	return e
```

⚠️ **Аллокация на каждое событие.** При 10 тиках/с × 6 агентов это десятки объектов в секунду — терпимо. Но `water_level_changed` каждый тик × 12 циклов × 3000 тиков = 36 000 объектов за забег. Промпт 01 уже требует троттлинг «не чаще раза в 3 тика и при |Δ|>0.01» — **это не косметика, а требование производительности, соблюсти обязательно.**

**Дешёвая альтернатива, если профайлер покажет проблему:** пул `SimEvent`, переиспользуемый после flush. ⚠️ Не делать превентивно — усложнение без замера.

**`data: Dictionary` не типизирован специально:** типизированный `Dictionary[String, Variant]` не даёт ни скорости, ни защиты, а мешает класть `Vector2i`. Это допустимое исключение из правила «типизация везде» — **записать комментарием `# РЕШЕНИЕ:`**, иначе следующий агент «починит».

---

## 6. Мапперы `type -> сигнал`: как не потерять событие молча

Ключевой риск из docs/02 §10: *«несовместимая сигнатура обработчика не вызывается, warning только в debug-сборке»*.

**Не писать длинный `match` по строкам** — он молча пропустит неизвестный тип. Писать таблицу + явную проверку:

```gdscript
## autoload/game.gd
const EVENT_MAP: Dictionary[String, String] = {
	"sim_ticked": "sim_ticked",
	"phase_changed": "phase_changed",
	"water_level_changed": "water_level_changed",
	"cycle_started": "cycle_started",
	"cycle_ended": "cycle_ended",
}

func _flush_events() -> void:
	for e: SimEvent in world.events_out:
		var sig: String = EVENT_MAP.get(e.type, "")
		if sig.is_empty():
			push_error("SimEvent без маппинга: %s" % e.type)   # в тестах = провал
			continue
		Events.emit_signal(sig, *_args_for(e))
	world.events_out.clear()
```

⚠️ GDScript **не поддерживает распаковку `*args`**. Реальный код:
```gdscript
		match e.type:
			"phase_changed":        Events.phase_changed.emit(e.data["phase"], e.data["cycle"])
			"water_level_changed":  Events.water_level_changed.emit(e.data["level"])
			...
			_:                      push_error("SimEvent без маппинга: %s" % e.type)
```
То есть `match` всё-таки, но **с обязательной веткой `_:` и `push_error`**. Тест этапа 19 (п.3 «санитария сигналов») тогда сводится к прогону забега с проверкой, что `push_error` не вызывался — для этого в дебаг-сборке достаточно счётчика в `Game`.

**Смоук-тест подписок (дёшево, ловит 90% проблем):**
```gdscript
# tests/test_signals.gd
for sig: Dictionary in Events.get_signal_list():
	var name: String = sig["name"]
	var conns: Array = Events.get_signal_connection_list(name)
	if conns.is_empty():
		warnings.append("сигнал %s никто не слушает" % name)
```

---

## 7. Производительность GDScript: что реально важно в нашем масштабе

Масштаб проекта: 6 агентов, ~50 задач, ~40 построек, граф из ~30 узлов, 10 тиков/с. **Это крошечно.** Бюджет из docs/00 §16 — 2 мс на тик — достижим почти любым кодом. Поэтому:

**Не оптимизировать превентивно.** Особенно не делать: пулы объектов, битовые маски, ручную упаковку в PackedArray. Это съест время этапов и усложнит отладку детерминизма.

**Но три вещи стоит сделать сразу, потому что потом дорого:**

1. **Не пересчитывать граф путей каждый тик.** `Terrain.find_path` вызывать только при смене цели агента, результат кэшировать в агенте (`path: Array[int]`, `path_idx: int`). Инвалидация — по событию `add_ladder/remove_ladder` (глобальный счётчик `graph_version: int`, агент хранит версию своего пути).
2. **Не строить список задач с нуля каждый тик.** `JobSystem` перестраивает пул задач по событиям (депозит изменился, предмет упал, постройка размещена), а каждый тик только *выбирает* из готового пула. Иначе O(агенты × задачи) каждый тик превращается в O(агенты × мир).
3. **Типизировать циклы.** `for id: int in ids:` быстрее, чем `for id in ids:` — статический тип убирает проверку варианта. Это бесплатно и требуется CONVENTIONS.

**Факты о структурах данных (док Array):** *«Packed arrays are generally faster to iterate on and modify compared to a typed array of the same type… Also, packed arrays consume less memory.»* Для наших списков id (`Array[int]` из ~30 элементов) разница нерелевантна — **берём `Array[int]` ради читаемости и типизированных сигналов.** `PackedInt32Array` — только если что-то вырастет до тысяч (не вырастет).

**Про `Dictionary` vs `Array` для сущностей:** агентов/построек/задач хранить в `Dictionary[int, X]` (доступ по id) **плюс** отсортированный `Array[int]` порядка обхода. Одного словаря мало: insertion order после `from_dict` может отличаться (см. §1).

---

## 8. `to_dict` / `from_dict`: шаблон, который не развалится

```gdscript
## Правила для ВСЕХ sim-классов:
## 1. to_dict возвращает только примитивы, Array и Dictionary. Никаких Object/Resource.
## 2. Vector2i -> [x, y]. Enum -> int. NAN -> null.
## 3. from_dict полностью восстанавливает состояние, не полагаясь на конструктор.
## 4. Порядок вставки ключей не важен (JSON.stringify сортирует), но
##    порядок элементов в МАССИВАХ важен: он и есть порядок обхода.

func to_dict() -> Dictionary:
	return {
		"tick_in_phase": tick_in_phase,
		"phase": int(phase),
		"cycle": cycle,
	}

func from_dict(d: Dictionary) -> void:
	tick_in_phase = int(d.get("tick_in_phase", 0))
	phase = int(d.get("phase", SimTypes.Phase.EBB)) as SimTypes.Phase
	cycle = int(d.get("cycle", 1))
```

⚠️ **`JSON.parse` возвращает все числа как `float`.** Целые после round-trip станут `12.0`. Поэтому `from_dict` **обязан** приводить: `int(d["cycle"])`. Забыть — значит получить `cycle` типа float, `typeof` != TYPE_INT, и следующий `to_dict` даст `12.0` вместо `12` → хеш не совпадёт → «плавающий» провал теста этапа 11. **Это ошибка №1 при написании сейвов в Godot.** Подробнее — doc 18 §1.

Хелпер, который стоит завести сразу в `sim/sim_types.gd`:
```gdscript
static func v2i_to_arr(v: Vector2i) -> Array: return [v.x, v.y]
static func arr_to_v2i(a: Array) -> Vector2i: return Vector2i(int(a[0]), int(a[1]))
static func f_or_null(v: float) -> Variant: return null if is_nan(v) else v
static func null_or_f(v: Variant) -> float: return NAN if v == null else float(v)
```

---

## 9. Тест детерминизма: как писать, чтобы он ловил, а не мешал

```gdscript
# tests/test_clock.gd (фрагмент)
static func test_determinism(t: TestCtx) -> void:
	var a := SimWorld.new(); a.new_run(12345)
	var b := SimWorld.new(); b.new_run(12345)
	for i: int in 10000:
		a.tick(); a.events_out.clear()
		b.tick(); b.events_out.clear()
		# Ранняя диагностика: расхождение на тике N ищется бинарно, а не в конце
		if i % 500 == 0:
			t.check(hash_of(a) == hash_of(b), "разошлись на тике %d" % i)
	t.check(hash_of(a) == hash_of(b), "финальные состояния различаются")
```

**Промежуточные сверки каждые 500 тиков — не паранойя, а экономия часов.** Расхождение «после 20 000 тиков» ничего не говорит; расхождение «между тиками 3000 и 3500, сразу после cycle_ended» указывает на систему.

**Второй тест, который надо написать один раз и он окупится на этапе 11:**
```gdscript
# save -> load -> продолжение == непрерывный прогон
var live := SimWorld.new(); live.new_run(777)
for i: int in 5000: live.tick(); live.events_out.clear()
var snapshot: Dictionary = live.to_dict()

var restored := SimWorld.new()
restored.from_dict(snapshot)
for i: int in 2000:
	live.tick(); live.events_out.clear()
	restored.tick(); restored.events_out.clear()
t.check(hash_of(live) == hash_of(restored), "save/load ломает детерминизм")
```
Он падает ровно в двух случаях: (а) `from_dict` что-то не восстановил (обычно — состояние RNG или кэш), (б) `to_dict` теряет точность float. Оба — фатальны и лучше узнать о них на этапе 01, а не на 11.

**RNG в сейве:** `RandomNumberGenerator.state` — это `int`, полное внутреннее состояние. `seed` его сбрасывает. Восстанавливать надо **`state`, а не `seed`**, иначе после загрузки генератор начнёт последовательность заново.

---

## 10. Grep-аудит для этапа 19 (готовый скрипт)

```bash
#!/usr/bin/env bash
# tools/audit_sim.sh — запускать перед коммитом любого sim-этапа
set -u
FAIL=0
cd "$(dirname "$0")/../godot" || exit 1

check() {  # check <regex> <человеческое описание>
	local hits
	hits=$(grep -rnE "$1" sim/ --include='*.gd' | grep -v '^\s*#' || true)
	if [ -n "$hits" ]; then echo "❌ $2"; echo "$hits"; FAIL=1; fi
}

check '\brandi\(|\brandf\(|\brandomize\(|\brand_range' 'глобальный RNG в sim/'
check '\bTime\.'                                       'Time.* в sim/'
check '\bawait\b'                                      'await в sim/'
check '\bget_tree\(|\bget_node\(|\$'                   'доступ к дереву нод в sim/'
check '^\s*print\('                                    'print в sim/ (только push_warning/push_error)'
check 'extends Node'                                   'Node-наследник в sim/'
check '\bsignal\b'                                     'signal в sim/ (события — только events_out)'
check 'sort_custom\(' 'sort_custom — проверь, что компаратор тотальный (см. research/11 §1.1)'

[ $FAIL -eq 0 ] && echo "✅ sim/ чист" || exit 1
```

Последняя проверка намеренно «мягкая» (напоминание, а не запрет) — `sort_custom` разрешён, но требует ревью компаратора.

---

## 11. Что стоит заложить на этапе 01, чтобы не переделывать позже

Дёшево сейчас — дорого потом. Ничего из списка не нарушает раздел «Не делать» промпта 01.

1. **`Game.sim_seconds() -> float`** — уже отмечено в research/README (нужен этапу 18 для шейдеров). Три строки.
2. **`SimClock.total_ticks() -> int`** — сквозной счётчик тиков забега (не `tick_in_phase`). Нужен и хешам, и логам, и `sim_seconds()`, и графику времени тика.
3. **`SimWorld.graph_version: int`** — инкремент при любом изменении графа. Нужен кэшу путей (этап 05/06) и оверлею дебага (этап 03).
4. **`SimWorld.cycle_modifiers: Dictionary`** — промпт 10 требует его явно; если завести пустым уже на 01, этапы 05/06/08 сразу будут читать его, а не хардкод.
5. **`SimClock.phase_scale: Dictionary[int, float]`** — промпт 09 требует API масштабирования длительности фазы (шторм укорачивает LOW на 30%). Заложить как единичный словарь сразу — иначе на этапе 09 придётся трогать формулу фаз, а это самое опасное место для детерминизма.
6. **Счётчик `_error_count` в `Game`**, инкремент в ветке `_:` маппинга событий. Даёт этапу 19 бесплатную «санитарию сигналов».

---

## Источники

- [Array (Godot 4.7)](https://docs.godotengine.org/en/stable/classes/class_array.html) — нестабильность `sort()`/`sort_custom()`, packed vs typed
- [Dictionary (Godot 4.7)](https://docs.godotengine.org/en/stable/classes/class_dictionary.html) — insertion order, `hash()` чувствителен к порядку, передача по ссылке
- [JSON (Godot 4.7)](https://docs.godotengine.org/en/stable/classes/class_json.html) — `stringify(data, indent="", sort_keys=true, full_precision=false)`, non-finite numbers
- [GDScript reference](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html) — int/float 64-bit, `@abstract`, static vars, assert в release
- [AStar2D](https://docs.godotengine.org/en/stable/classes/class_astar2d.html) — RefCounted, детерминированный тай-брейк
- [CPU optimization](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html) — профилировать до оптимизации
- [Fix Your Timestep! — Gaffer On Games](https://gafferongames.com/post/fix_your_timestep/) — аккумулятор, спираль смерти
- [Deterministic Lockstep — Gaffer On Games](https://gafferongames.com/post/deterministic_lockstep/) — почему стабильный порядок обхода и стабильные id важнее всего
