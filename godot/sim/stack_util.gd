class_name StackUtil
extends RefCounted
## Хелперы стака в одном месте, чтобы правила слияния не расползлись копипастой
## по системам (research/14 §5).
##
## РЕШЕНИЕ: стак — нетипизированный Dictionary
## {item_id: String, count: int, wet: bool, spoil_left: int, dry_left: int}.
## Значения разных типов, Dictionary[String, Variant] не даёт ничего, кроме
## помех; зато словарь сериализуется в JSON без to_dict. Не «чинить».
##
## dry_left сверх схемы промпта 04: сушка мокрого стака занимает 2 полных цикла,
## и этот счётчик — единственное её состояние.

## ⚠️ Словари передаются ПО ССЫЛКЕ. Любой, кто принимает стак во владение,
## обязан взять duplicate() — иначе вызывающий код продолжит держать ссылку
## и сможет менять стак «изнутри склада».
static func make(item_id: String, count: int, wet: bool = false) -> Dictionary:
	var def: ItemDef = DB.item(item_id)
	var spoil: int = def.spoil_cycles if def != null else 0
	return {
		"item_id": item_id, "count": count, "wet": wet,
		"spoil_left": spoil, "dry_left": Balance.DRY_CYCLES if wet else 0,
	}

## ⚠️ spoil_left сравнивается обязательно: слияние стаков с разным сроком порчи
## — тихий эксплойт, свежая добыча «продлевала» бы старую.
static func can_merge(a: Dictionary, b: Dictionary) -> bool:
	return str(a["item_id"]) == str(b["item_id"]) \
		and bool(a["wet"]) == bool(b["wet"]) \
		and int(a["spoil_left"]) == int(b["spoil_left"]) \
		and int(a["dry_left"]) == int(b["dry_left"])

static func set_wet(stack: Dictionary, wet: bool) -> void:
	stack["wet"] = wet
	stack["dry_left"] = Balance.DRY_CYCLES if wet else 0

## Ключ буфера постройки. Мокрое хранится отдельно: горн сухой плавник
## принимает, а мокрый — нет, и словарь {item: count} без этого различия
## теряет разницу (research/17 §7.3).
const WET_SUFFIX: String = "#wet"

static func buffer_key(item_id: String, wet: bool) -> String:
	return item_id + WET_SUFFIX if wet else item_id

static func key_item(key: String) -> String:
	return key.trim_suffix(WET_SUFFIX)

static func key_is_wet(key: String) -> bool:
	return key.ends_with(WET_SUFFIX)

## Нормализует стак, пришедший из JSON: все числа там float.
static func from_json(d: Dictionary) -> Dictionary:
	return {
		"item_id": str(d.get("item_id", "")),
		"count": int(d.get("count", 0)),
		"wet": bool(d.get("wet", false)),
		"spoil_left": int(d.get("spoil_left", 0)),
		"dry_left": int(d.get("dry_left", 0)),
	}
