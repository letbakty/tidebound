class_name DB
extends RefCounted
## Статический доступ ко всем дефам. Не автолоад: DB нужен в sim/, а автолоады
## там запрещены (docs/02 §1) — статический класс это единственный корректный
## вариант (research/14 §4).
##
## ensure_loaded() стоит в каждом геттере, а не в _ready: к DB обращается
## headless-тест, где никакого _ready не было.

static var _items: Dictionary[String, ItemDef] = {}
static var _traits: Dictionary[String, TraitDef] = {}
static var _buildings: Dictionary[String, BuildingDef] = {}
static var _recipes: Dictionary[String, RecipeDef] = {}
static var _loaded: bool = false

# Задел под этапы 07/08/05/10/11 — папки уже существуют, загрузчик один и тот же.
const DIRS: Dictionary = {
	"items": "res://data/items/",
	"buildings": "res://data/buildings/",
	"recipes": "res://data/recipes/",
	"traits": "res://data/traits/",
	"cards": "res://data/cards/",
	"unlocks": "res://data/unlocks/",
}

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load_dir(str(DIRS["items"]), _items)
	_load_dir(str(DIRS["traits"]), _traits)
	_load_dir(str(DIRS["buildings"]), _buildings)
	_load_dir(str(DIRS["recipes"]), _recipes)

## Сбрасывает кэш. Нужен только тестам, которые проверяют сам загрузчик.
static func reload() -> void:
	_items.clear()
	_traits.clear()
	_buildings.clear()
	_recipes.clear()
	_loaded = false
	ensure_loaded()

static func _load_dir(dir_path: String, into: Dictionary) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		push_error("DB: нет папки %s" % dir_path)
		return
	var names: PackedStringArray = dir.get_files()
	names.sort()                      # get_files() порядка не гарантирует
	for f: String in names:
		# ⚠️ В экспортированной сборке .tres превращается в .tres.remap.
		# Фильтр только по ".tres" находит в собранной игре НОЛЬ файлов,
		# и игра стартует с пустой БД (research/14 §4).
		var fname: String = f.trim_suffix(".remap")
		if not fname.ends_with(".tres"):
			continue
		var res: Resource = load(dir_path + fname)
		if res == null:
			push_error("DB: не загружен %s" % fname)
			continue
		var id: String = str(res.get("id"))
		if id.is_empty() or id != fname.trim_suffix(".tres"):
			push_error("DB: id '%s' не совпадает с именем файла '%s'" % [id, fname])
			continue
		into[id] = res

static func item(id: String) -> ItemDef:
	ensure_loaded()
	var d: ItemDef = _items.get(id, null)
	if d == null:
		push_error("DB: нет предмета '%s'" % id)
	return d

static func has_item(id: String) -> bool:
	ensure_loaded()
	return _items.has(id)

static func item_ids() -> Array[String]:
	ensure_loaded()
	var ids: Array[String] = []
	ids.assign(_items.keys())
	ids.sort()                        # детерминированный обход
	return ids

## trait_def, а не trait: trait — зарезервированное слово в GDScript.
static func trait_def(id: String) -> TraitDef:
	ensure_loaded()
	var d: TraitDef = _traits.get(id, null)
	if d == null:
		push_error("DB: нет черты '%s'" % id)
	return d

static func has_trait(id: String) -> bool:
	ensure_loaded()
	return _traits.has(id)

static func building(id: String) -> BuildingDef:
	ensure_loaded()
	var d: BuildingDef = _buildings.get(id, null)
	if d == null:
		push_error("DB: нет постройки '%s'" % id)
	return d

static func has_building(id: String) -> bool:
	ensure_loaded()
	return _buildings.has(id)

static func building_ids() -> Array[String]:
	ensure_loaded()
	var ids: Array[String] = []
	ids.assign(_buildings.keys())
	ids.sort()
	return ids

static func recipe(id: String) -> RecipeDef:
	ensure_loaded()
	var r: RecipeDef = _recipes.get(id, null)
	if r == null:
		push_error("DB: нет рецепта '%s'" % id)
	return r

static func has_recipe(id: String) -> bool:
	ensure_loaded()
	return _recipes.has(id)

static func recipe_ids() -> Array[String]:
	ensure_loaded()
	var ids: Array[String] = []
	ids.assign(_recipes.keys())
	ids.sort()
	return ids

static func trait_ids() -> Array[String]:
	ensure_loaded()
	var ids: Array[String] = []
	ids.assign(_traits.keys())
	ids.sort()
	return ids
