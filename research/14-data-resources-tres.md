# 14 — Данные: Resource-дефы, генерация .tres скриптом, загрузчик DB

**Для этапов:** 04 (13 предметов), 07 (17 построек), 08 (рецепты), 10 (6 карт), 11 (12 разблокировок), 05 (20 черт), 02 (CliffDef).
**Дата ресерча:** 2026-08-21. **Движок:** Godot 4.7.x stable.

**Главный вывод документа:** ~70 `.tres`-файлов, которые требуют промпты, **нельзя делать руками в инспекторе** — это часы кликов и гарантированные опечатки в id. Их надо генерировать `EditorScript`-ом из одной таблицы в коде (§3). Это самый крупный выигрыш по времени во всём ресерче.

---

## 1. Деф-ресурс: канонический шаблон

```gdscript
class_name ItemDef
extends Resource

@export var id: String = ""
@export var display_key: String = ""
@export var stack_size: int = 1
@export var spoil_cycles: int = 0                       # 0 = не портится
@export var flood_rule: SimTypes.FloodRule = SimTypes.FloodRule.OK
@export var ship_points: int = 0
@export var icon: Texture2D = null
```

**Что здесь важно технически:**

1. **`class_name` обязателен.** Без него `.tres` сохранится со ссылкой на путь скрипта, а в инспекторе типизированные массивы/словари этого типа отображаются как generic `Resource` (баг [#109574](https://github.com/godotengine/godot/issues/109574)).
2. **У каждого `@export` — значение по умолчанию.** Без него поле может оказаться `null` в рантайме после загрузки старого `.tres` ([типовая проблема](https://bugnet.io/blog/fix-godot-export-variable-dictionary-null-at-runtime)). `Dictionary`/`Array` без дефолта особенно опасны.
3. **Enum экспортируется как enum-тип напрямую** (`@export var flood_rule: SimTypes.FloodRule`) — инспектор покажет выпадающий список. `@export_enum("OK", "WET", ...)` даёт то же визуально, но хранит **int/String без связи с enum** — не использовать, разъедется при добавлении значения.
4. **`Texture2D = null` — нормально.** Промпт 04 явно разрешает пустую иконку. Код, который её читает (этап 12/13), обязан иметь фолбэк.

### 1.1 Типизированные словари в `@export` — ограничения

Промпты 05/07/08/10 требуют `@export var cost: Dictionary[String, int]`, `modifiers: Dictionary[String, float]`, `effects: Dictionary[String, float]`.

**Факты:**
- Типизированные словари появились в **4.4**; синтаксис `Dictionary[KeyType, ValueType]`, оба типа обязательны (можно `Variant`).
- Официальная страница «GDScript exports» **не документирует экспорт типизированных словарей вообще** — то есть это работающая, но недодокументированная территория.
- Известный баг [#104581](https://github.com/godotengine/godot/issues/104581): **ключ записи в экспортированном словаре нельзя изменить через инспектор после добавления** — только удалить и создать заново.

**Что из этого следует для нас:** экспортированные словари **редактировать в инспекторе неудобно и багованно** → тем более надо генерировать `.tres` скриптом (§3), а инспектор использовать только для чтения/проверки. Само хранение и загрузка типизированных словарей работают корректно.

⚠️ **Фикс-ключи словарей — держать в `const`-массиве, а не в комментарии.** Промпт 05 перечисляет 21 ключ модификаторов, промпт 10 — 10 ключей эффектов. Опечатка в ключе даёт молчаливый ноль-эффект.
```gdscript
class_name TraitKeys
const ALL: Array[String] = ["speed_mult", "ladder_speed_mult", "bag_slots_add",
	"drown_seconds", "min_mark", "forge_mult", "saltery_mult", "hunger_rate_mult",
	"warmth_rate_mult", "mood_aura", "relic_chance_mult", "drop_chance",
	"panic_range", "work_mult", "carry_mult", "rest_need_mult", "rest_gain_mult",
	"no_panic", "no_rest_cycles", "idle_mood_penalty"]
```
и валидатор в тесте: любой ключ любого `TraitDef`, которого нет в `ALL`, — провал теста. **Ловит опечатки в момент коммита, а не через три этапа.**

---

## 2. Иммутабельность: почему это не формальность

docs/02 §5 и §10: дефы иммутабельны, `load()` возвращает **закэшированный инстанс**.

Практическое следствие: `DB.item("catch").spoil_cycles = 99` изменит деф **для всех и на весь запуск процесса**, включая следующий забег в той же сессии и все headless-тесты, идущие после. Это создаёт «плавающие» падения тестов, зависящие от порядка.

**Защита, которую стоит поставить сразу (дёшево):**
```gdscript
# tests/test_data.gd — прогонять в run_all.gd первым
static func test_defs_untouched(t: TestCtx) -> void:
	var before: Dictionary = _snapshot_all_defs()
	_run_full_headless_run(seed_value = 42)
	t.check(_snapshot_all_defs() == before, "рантайм мутировал деф-ресурс")
```
где `_snapshot_all_defs` собирает `JSON.stringify` всех полей всех дефов.

⚠️ **`duplicate(true)` на Resource в 4.5+ переписан** (`duplicate_deep`, есть регрессии) — docs/02 §10 запрещает глубокое копирование ресурсов. Это правило соблюдается автоматически, если дефы никогда не мутируются.

**`resource_local_to_scene` — не использовать.** Он делает копию ресурса на каждый инстанс сцены; для дефов это порча кэша и лишняя память.

---

## 3. Генератор `.tres` — главный ускоритель этапов 04/05/07/08/10/11

Схема одна и та же для всех шести этапов. Пишется один раз на этапе 04, дальше копируется с заменой таблицы.

```gdscript
@tool
extends EditorScript
## tools/gen_items.gd — File → Run. Идемпотентен: повторный прогон перезаписывает.
## Источник правды — таблица docs/00 §7. Правишь таблицу здесь, жмёшь Run.

const OUT_DIR: String = "res://data/items/"

# id, display_key, stack, spoil_cycles, flood_rule, ship_points
const TABLE: Array[Array] = [
	["scrap",      "ITEM_SCRAP",      20, 0,  SimTypes.FloodRule.OK,        1],
	["catch",      "ITEM_CATCH",      10, 3,  SimTypes.FloodRule.LOSE_HALF, 2],
	["driftwood",  "ITEM_DRIFTWOOD",  20, 0,  SimTypes.FloodRule.WET,       1],
	["kelp",       "ITEM_KELP",       20, 0,  SimTypes.FloodRule.OK,        1],
	["freshwater", "ITEM_FRESHWATER", 10, 0,  SimTypes.FloodRule.OK,        2],
	["salt",       "ITEM_SALT",       20, 0,  SimTypes.FloodRule.DESTROY,   2],
	["ingot",      "ITEM_INGOT",      10, 0,  SimTypes.FloodRule.OK,        4],
	["fiber",      "ITEM_FIBER",      20, 0,  SimTypes.FloodRule.WET,       1],
	["rations",    "ITEM_RATIONS",    10, 12, SimTypes.FloodRule.LOSE_HALF, 5],
	["part",       "ITEM_PART",       10, 0,  SimTypes.FloodRule.OK,        6],
	["rope",       "ITEM_ROPE",       10, 0,  SimTypes.FloodRule.OK,        3],
	["gear",       "ITEM_GEAR",        5, 0,  SimTypes.FloodRule.OK,        8],
	["relic",      "ITEM_RELIC",       5, 0,  SimTypes.FloodRule.OK,       20],
]

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var written: int = 0
	for row: Array in TABLE:
		var d := ItemDef.new()
		d.id = row[0]
		d.display_key = row[1]
		d.stack_size = row[2]
		d.spoil_cycles = row[3]
		d.flood_rule = row[4]
		d.ship_points = row[5]
		# Имя файла == id: это контракт, на него опирается валидатор в тестах.
		var path: String = OUT_DIR + d.id + ".tres"
		var err: Error = ResourceSaver.save(d, path)
		if err != OK:
			push_error("не сохранён %s: %d" % [path, err])
		else:
			written += 1
	print("items: записано %d/%d" % [written, TABLE.size()])
```

**Технические детали, без которых не заработает:**

- **`ResourceSaver.save(resource, path, flags)` — порядок аргументов именно такой** (в Godot 3 было `save(path, resource)`). Частая галлюцинация.
- **Расширение решает формат.** `.tres` — текстовый (в git читается и диффится), `.res` — бинарный. Для дефов только `.tres`.
- **Флаг `ResourceSaver.FLAG_BUNDLE_RESOURCES` не нужен** — вложенных ресурсов у нас нет.
- **`@tool` обязателен** на EditorScript, иначе `_run()` не вызовется.
- **После генерации нужен реимпорт.** В редакторе он произойдёт сам; в headless — `godot --headless --import --quit`.
- ⚠️ **`.uid`-файлы (с 4.4).** Godot создаёт рядом с каждым `.tres` файл `.tres.uid` со стабильным идентификатором. **Их надо коммитить в git.** Если удалить — ссылки в других ресурсах не сломаются (движок пересоздаст uid), но перегенерируются, и git покажет шум в каждом файле, который на них ссылается.

**Тот же скрипт для остальных этапов** меняется только в `TABLE` и типе дефа. Для `BuildingDef` (этап 07) таблица шире (17 строк × 10 полей) — стоит вынести её в отдельный `const` в том же файле, а не в CSV: `const` в GDScript типизируется и проверяется парсером, CSV — нет.

⚠️ **Исключение — `CliffDef` (этап 02).** Там 48×45 карта с площадками и слотами депозитов. Её тоже надо генерировать скриптом, но таблицей описывать не строки, а диапазоны:
```gdscript
# площадки: mark, x0, x1
const PLATFORMS: Array[Array] = [[6, 2, 12], [5, 2, 14], ..., [-8, 30, 46]]
# слоты депозитов: kind, mark, x
const DEPOSITS: Array[Array] = [["ruins_near", -1, 20], ..., ["kelp", -6, 40]]
```

---

## 4. `DB`: загрузчик, который не падает и проверяет себя

```gdscript
class_name DB
extends RefCounted
## Статический доступ ко всем дефам. Загружается один раз при первом обращении.

static var _items: Dictionary[String, ItemDef] = {}
static var _buildings: Dictionary[String, BuildingDef] = {}
static var _recipes: Dictionary[String, RecipeDef] = {}
static var _traits: Dictionary[String, TraitDef] = {}
static var _cards: Dictionary[String, CardDef] = {}
static var _unlocks: Dictionary[String, UnlockDef] = {}
static var _loaded: bool = false

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load_dir("res://data/items/", _items)
	_load_dir("res://data/buildings/", _buildings)
	_load_dir("res://data/recipes/", _recipes)
	_load_dir("res://data/traits/", _traits)
	_load_dir("res://data/cards/", _cards)
	_load_dir("res://data/unlocks/", _unlocks)

static func _load_dir(dir_path: String, into: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("DB: нет папки %s" % dir_path)
		return
	var names: PackedStringArray = dir.get_files()
	names.sort()                       # порядок загрузки детерминирован
	for f: String in names:
		# В экспортированной сборке .tres превращается в .remap!
		var name: String = f.trim_suffix(".remap")
		if not name.ends_with(".tres"):
			continue
		var res: Resource = load(dir_path + name)
		if res == null:
			push_error("DB: не загружен %s" % name)
			continue
		var id: String = res.get("id")
		if id.is_empty() or id != name.trim_suffix(".tres"):
			push_error("DB: id '%s' не совпадает с именем файла '%s'" % [id, name])
			continue
		into[id] = res

static func item(id: String) -> ItemDef:
	ensure_loaded()
	var d: ItemDef = _items.get(id, null)
	if d == null:
		push_error("DB: нет предмета '%s'" % id)
	return d

static func item_ids() -> Array[String]:
	ensure_loaded()
	var ids: Array[String] = []
	ids.assign(_items.keys())
	ids.sort()                          # детерминированный обход
	return ids
```

**Пять технических моментов:**

1. ⚠️ **`.remap` в экспортированной сборке — классическая ловушка.** При экспорте Godot конвертирует ресурсы и оставляет `file.tres.remap`. Код, фильтрующий по `ends_with(".tres")`, в редакторе работает, а в собранной игре находит **ноль файлов** — и игра запускается с пустой БД. Проявляется только на этапе 16/19, когда впервые собирают билд. `trim_suffix(".remap")` решает.
2. **`names.sort()`** — `DirAccess.get_files()` не гарантирует порядок. Для детерминизма он не критичен (доступ по id), но критичен, если где-то появится «первый доступный деф».
3. **`load()`, а не `preload()`** — путь вычисляется в рантайме, `preload` тут просто не скомпилируется.
4. **Статические переменные требуют 4.4+** — у нас 4.7, всё ок. Альтернатива без статики — автолоад, но `DB` нужен в `sim/`, а автолоады там запрещены → **статический класс это единственный корректный вариант**. Это важно: `DB` **не автолоад**, вопреки соблазну.
5. **`ensure_loaded()` в каждом геттере, а не в `_ready`** — потому что `sim/` может обратиться к `DB` из headless-теста, где никакого `_ready` не было.

### 4.1 Валидатор ссылок — один тест, который экономит день

Промпты 07/08/10/11 связывают дефы по id-строкам: `cost: {"scrap": 4}`, `station_special: "forge"`, `unlock_id: "u_gear"`, `grants: {"building": "steel_ladder"}`. Опечатка = молчаливо неработающий рецепт.

```gdscript
# tests/test_data.gd
static func test_cross_references(t: TestCtx) -> void:
	DB.ensure_loaded()
	for bid: String in DB.building_ids():
		var b: BuildingDef = DB.building(bid)
		for item_id: String in b.cost:
			t.check(DB.has_item(item_id), "постройка %s: неизвестный ресурс %s" % [bid, item_id])
		if not b.unlock_id.is_empty():
			t.check(DB.has_unlock(b.unlock_id), "постройка %s: нет разблокировки %s" % [bid, b.unlock_id])
	for rid: String in DB.recipe_ids():
		var r: RecipeDef = DB.recipe(rid)
		for k: String in r.inputs:  t.check(DB.has_item(k), "рецепт %s: вход %s" % [rid, k])
		for k: String in r.outputs: t.check(DB.has_item(k), "рецепт %s: выход %s" % [rid, k])
		t.check(DB.has_building_with_special(r.station_special),
			"рецепт %s: нет постройки со special=%s" % [rid, r.station_special])
	for uid: String in DB.unlock_ids():
		var u: UnlockDef = DB.unlock(uid)
		if u.grants.has("building"): t.check(DB.has_building(u.grants["building"]), ...)
		if u.grants.has("card"):     t.check(DB.has_card(u.grants["card"]), ...)
```

**И второй, столь же дешёвый: все `display_key`/`desc_key` существуют в `strings.csv`.** Ловит «сырые ключи на экране» из приёмки этапа 19 п.6 за пять этапов до неё:
```gdscript
static func test_i18n_keys(t: TestCtx) -> void:
	var known: Dictionary[String, bool] = _read_csv_keys("res://assets/i18n/strings.csv")
	for id: String in DB.item_ids():
		t.check(known.has(DB.item(id).display_key), "нет ключа %s" % DB.item(id).display_key)
```

---

## 5. Стаки как словари: почему не Resource и не класс

Промпт 04 задаёт стак как `{item_id: String, count: int, wet: bool, spoil_left: int}`.

**Это правильное решение, и вот почему технически:**
- Стак сериализуется напрямую в JSON без `to_dict` (docs/02 §6: «никаких Object/Resource в сейве»).
- Словарь копируется через `.duplicate()` — дёшево и без риска общего инстанса.
- ⚠️ **Но словарь передаётся по ссылке** (док Dictionary: *«Dictionaries are always passed by reference»*). `storage.store(id, stack)` не должен класть переданный словарь в хранилище как есть — иначе вызывающий код продолжит держать ссылку и сможет изменить стак «изнутри склада».
  ```gdscript
  func store(storage_id: int, stack: Dictionary) -> int:
      var s: Dictionary = stack.duplicate()   # владение переходит складу
      ...
  ```
- Типизировать как `Dictionary[String, Variant]` бессмысленно (значения разных типов). **Оставить нетипизированным с комментарием `# РЕШЕНИЕ:`** — иначе следующий агент попробует «починить» и упрётся.

**Хелперы стека — статические функции в одном месте** (`sim/stack_util.gd`), а не копипаста по системам:
```gdscript
class_name StackUtil
static func make(item_id: String, count: int, wet: bool = false) -> Dictionary:
	var def: ItemDef = DB.item(item_id)
	return {"item_id": item_id, "count": count, "wet": wet,
		"spoil_left": def.spoil_cycles}
static func can_merge(a: Dictionary, b: Dictionary) -> bool:
	return a["item_id"] == b["item_id"] and a["wet"] == b["wet"] \
		and a["spoil_left"] == b["spoil_left"]
```
⚠️ **`can_merge` обязан сравнивать `spoil_left`.** Слияние стаков с разным сроком порчи — тихий эксплойт: свежая рыба «продлевает» старую. Приёмка этапа 04 («catch исчезает через 3 цикла») это не поймает, а игрок поймает.

---

## 6. Чек-лист приёмки «данных» (общий для 04/05/07/08/10/11)

- [ ] Число `.tres` в папке == числу строк в таблице генератора.
- [ ] Имя каждого файла == его `id` (проверяется `DB._load_dir`).
- [ ] Кросс-ссылочный тест (§4.1) зелёный.
- [ ] Тест ключей i18n зелёный.
- [ ] Тест «дефы не мутировали за забег» (§2) зелёный.
- [ ] Все ключи словарей-модификаторов есть в `TraitKeys.ALL` / `CardKeys.ALL`.
- [ ] `godot --headless --import --quit` без ошибок (битый `.tres` вылезет здесь).

---

## Источники

- [GDScript exports](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_exports.html) — типизированные массивы, ограничения; про типизированные словари страница молчит
- [GDScript reference](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html) — типизированные словари с 4.4, статические переменные
- [Dictionary](https://docs.godotengine.org/en/stable/classes/class_dictionary.html) — передача по ссылке, duplicate, insertion order
- [ResourceSaver](https://docs.godotengine.org/en/stable/classes/class_resourcesaver.html) — save(resource, path, flags)
- [godot#104581](https://github.com/godotengine/godot/issues/104581) — ключ экспортированного словаря нельзя изменить в инспекторе
- [godot#109574](https://github.com/godotengine/godot/issues/109574) — типизированные коллекции кастомных типов без `class_name` в инспекторе
- [Fix Godot @export Dictionary null at runtime](https://bugnet.io/blog/fix-godot-export-variable-dictionary-null-at-runtime) — почему у каждого @export нужен дефолт
