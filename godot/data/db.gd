class_name DB
extends RefCounted
## Статический доступ ко всем дефам. Не автолоад: DB нужен в sim/, а автолоады
## там запрещены (docs/02 §1) — статический класс это единственный корректный
## вариант (research/14 §4).
##
## ensure_loaded() стоит в каждом геттере, а не в _ready: к DB обращается
## headless-тест, где никакого _ready не было.

static var _items: Dictionary[String, ItemDef] = {}
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

## Сбрасывает кэш. Нужен только тестам, которые проверяют сам загрузчик.
static func reload() -> void:
	_items.clear()
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
