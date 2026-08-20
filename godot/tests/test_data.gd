extends RefCounted
## Валидатор данных. Идёт в run_all.gd ПЕРВЫМ: битые .tres валят всё остальное,
## и лучше увидеть причину, чем десяток следствий.

const ITEMS_DIR: String = "res://data/items/"
const CSV_PATH: String = "res://assets/i18n/strings.csv"
const CLIFF: String = "res://data/cliffs/cliff_01.tres"

static func test_all_items_present(t: TestCtx) -> void:
	var ids: Array[String] = DB.item_ids()
	t.check_eq(ids.size(), 13, "все 13 предметов docs/00 §7 загружены")
	for id: String in ["scrap", "catch", "driftwood", "kelp", "freshwater", "salt",
			"ingot", "fiber", "rations", "part", "rope", "gear", "relic"]:
		t.check(DB.has_item(id), "есть предмет '%s'" % id)

## Имя файла == id: на этом контракте держится загрузчик DB.
static func test_file_names_match_ids(t: TestCtx) -> void:
	var dir: DirAccess = DirAccess.open(ITEMS_DIR)
	t.check(dir != null, "папка предметов открывается")
	if dir == null:
		return
	var n: int = 0
	for f: String in dir.get_files():
		var fname: String = f.trim_suffix(".remap")
		if not fname.ends_with(".tres"):
			continue
		n += 1
		var res: ItemDef = load(ITEMS_DIR + fname) as ItemDef
		t.check(res != null, "%s грузится как ItemDef" % fname)
		if res != null:
			t.check_eq(res.id, fname.trim_suffix(".tres"), "id совпадает с именем файла")
	t.check_eq(n, DB.item_ids().size(), "число файлов == числу загруженных дефов")

static func test_flood_rules_match_spec(t: TestCtx) -> void:
	var expect: Dictionary = {
		"driftwood": SimTypes.FloodRule.WET, "fiber": SimTypes.FloodRule.WET,
		"salt": SimTypes.FloodRule.DESTROY,
		"catch": SimTypes.FloodRule.LOSE_HALF, "rations": SimTypes.FloodRule.LOSE_HALF,
	}
	for id: String in DB.item_ids():
		var want: int = int(expect.get(id, SimTypes.FloodRule.OK))
		t.check_eq(int(DB.item(id).flood_rule), want, "правило затопления у '%s'" % id)

static func test_spoilage_matches_spec(t: TestCtx) -> void:
	t.check_eq(DB.item("catch").spoil_cycles, 3, "добыча портится за 3 цикла")
	t.check_eq(DB.item("rations").spoil_cycles, 12, "провизия — за 12")
	for id: String in DB.item_ids():
		if id == "catch" or id == "rations":
			continue
		t.check_eq(DB.item(id).spoil_cycles, 0, "'%s' не портится" % id)

## Ловит «сырые ключи на экране» за пятнадцать этапов до приёмки этапа 19.
static func test_i18n_keys_exist(t: TestCtx) -> void:
	var known: Dictionary[String, bool] = _csv_keys()
	t.check(known.has("APP_NAME"), "csv читается")
	for id: String in DB.item_ids():
		var key: String = DB.item(id).display_key
		t.check(known.has(key), "нет ключа локализации '%s' (предмет %s)" % [key, id])
	for tid: String in DB.trait_ids():
		var d: TraitDef = DB.trait_def(tid)
		t.check(known.has(d.display_key), "нет ключа '%s' (черта %s)" % [d.display_key, tid])
		t.check(known.has(d.desc_key), "нет ключа '%s' (описание черты %s)" % [d.desc_key, tid])
	for bio: String in AgentPools.BIO_KEYS:
		t.check(known.has(bio), "нет ключа биографии '%s'" % bio)

static func test_all_traits_present(t: TestCtx) -> void:
	t.check_eq(DB.trait_ids().size(), 20, "все 20 черт docs/00 §6.4 загружены")
	for tid: String in DB.trait_ids():
		var d: TraitDef = DB.trait_def(tid)
		t.check(not d.modifiers.is_empty(), "у черты '%s' есть хотя бы один эффект" % tid)

## Опечатка в ключе модификатора даёт молчаливый ноль-эффект, который всплыл бы
## этапов через пять (research/14 §1.1).
static func test_trait_keys_are_known(t: TestCtx) -> void:
	for tid: String in DB.trait_ids():
		for key: String in DB.trait_def(tid).modifiers:
			t.check(not TraitKeys.fold_of(key).is_empty(),
				"черта %s: ключ '%s' не из TraitKeys" % [tid, key])

static func test_agent_pools(t: TestCtx) -> void:
	t.check_eq(AgentPools.NAMES.size(), 40, "пул имён — 40 штук")
	t.check_eq(AgentPools.BIO_KEYS.size(), 30, "пул биографий — 30 штук")
	var seen: Dictionary[String, bool] = {}
	for n: String in AgentPools.NAMES:
		t.check(not seen.has(n), "имя '%s' не повторяется" % n)
		seen[n] = true

static func _csv_keys() -> Dictionary[String, bool]:
	var out: Dictionary[String, bool] = {}
	var f: FileAccess = FileAccess.open(CSV_PATH, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line: PackedStringArray = f.get_csv_line()
		if line.size() > 0 and not line[0].is_empty():
			out[line[0]] = true
	return out

## Дефы — общие инстансы из кэша ResourceLoader. Мутация в рантайме изменила бы
## предмет для всех и до конца процесса, включая следующие тесты: это даёт
## «плавающие» падения, зависящие от порядка (research/14 §2).
static func test_defs_not_mutated_by_a_run(t: TestCtx) -> void:
	var before: String = _snapshot()
	var w: SimWorld = SimWorld.new()
	w.new_run(42, load(CLIFF) as CliffDef)
	t.run_ticks(w, Balance.TICKS_PER_CYCLE * 2)
	t.check_eq(_snapshot(), before, "забег не изменил ни одного деф-ресурса")

static func _snapshot() -> String:
	var all: Array = []
	for id: String in DB.item_ids():
		var d: ItemDef = DB.item(id)
		all.append([d.id, d.display_key, d.stack_size, d.spoil_cycles,
			int(d.flood_rule), d.ship_points])
	for tid: String in DB.trait_ids():
		var td: TraitDef = DB.trait_def(tid)
		all.append([td.id, td.display_key, td.desc_key, td.modifiers])
	return JSON.stringify(all)

## Загрузчик обязан пережить перезагрузку кэша: ensure_loaded() зовётся из
## каждого геттера, в том числе из headless-теста без всякого _ready.
static func test_db_reload(t: TestCtx) -> void:
	var before: Array[String] = DB.item_ids()
	var before_traits: Array[String] = DB.trait_ids()
	DB.reload()
	t.check_eq(DB.item_ids(), before, "после reload состав БД тот же")
	t.check_eq(DB.trait_ids(), before_traits, "черты тоже")
