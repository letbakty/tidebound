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
	for bid: String in DB.building_ids():
		var bd: BuildingDef = DB.building(bid)
		t.check(known.has(bd.display_key),
			"нет ключа '%s' (постройка %s)" % [bd.display_key, bid])
	for rid: String in DB.recipe_ids():
		t.check(known.has(DB.recipe(rid).display_key),
			"нет ключа '%s' (рецепт %s)" % [DB.recipe(rid).display_key, rid])
	for cid: String in DB.card_ids():
		var cd: CardDef = DB.card(cid)
		t.check(known.has(cd.display_key), "нет ключа '%s' (карта %s)" % [cd.display_key, cid])
		t.check(known.has(cd.desc_key), "нет ключа описания карты %s" % cid)
	for uid: String in DB.unlock_ids():
		var ud: UnlockDef = DB.unlock(uid)
		t.check(known.has(ud.display_key),
			"нет ключа '%s' (разблокировка %s)" % [ud.display_key, uid])
		t.check(known.has(ud.desc_key), "нет ключа описания разблокировки %s" % uid)
	for err: String in ["ERR_LOCKED", "ERR_MARK", "ERR_OCCUPIED", "ERR_NO_SUPPORT",
			"ERR_NO_LADDER_SPOT", "ERR_NOT_BUILDABLE", "ERR_NO_BASKET_SPOT"]:
		t.check(known.has(err), "нет ключа причины отказа '%s'" % err)

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

static func test_all_buildings_present(t: TestCtx) -> void:
	t.check_eq(DB.building_ids().size(), 18, "все 18 построек docs/00 §8 загружены")
	for id: String in ["ladder_wood", "ladder_steel", "platform", "storage",
			"hearth", "bunk", "raincatcher", "forge", "workbench", "evaporator",
			"saltery", "dryer", "ropery", "sluice", "lantern", "condenser", "winch",
			"weir"]:
		t.check(DB.has_building(id), "есть постройка '%s'" % id)

## Опечатка в id ресурса делает рецепт или постройку молча непостроимой.
static func test_building_costs_reference_real_items(t: TestCtx) -> void:
	for id: String in DB.building_ids():
		var b: BuildingDef = DB.building(id)
		for item_id: String in b.cost:
			t.check(DB.has_item(item_id),
				"постройка %s: неизвестный ресурс '%s'" % [id, item_id])
		t.check(b.size.x > 0 and b.size.y > 0, "у %s ненулевой размер" % id)
		t.check(b.min_mark <= b.max_mark, "у %s диапазон отметок не вывернут" % id)
		t.check(b.hp >= 1, "у %s прочность хотя бы 1" % id)

static func test_building_spec_details(t: TestCtx) -> void:
	t.check_eq(DB.building("storage").hp, 2, "склад переживает два шторма")
	t.check(DB.building("dryer").storm_always, "сушила срывает на любой отметке")
	t.check(not DB.building("ladder_steel").storm_breaks, "стальная лестница штормоустойчива")
	t.check(DB.building("ladder_wood").storm_breaks, "деревянная — нет")
	t.check_eq(DB.building("hearth").min_mark, 1, "очаг только на жилых ярусах")
	t.check_eq(DB.building("evaporator").max_mark, 0, "испаритель не выше нуля")
	t.check_eq(DB.building("ladder_steel").unlock_id, "u_steel_ladder", "🔒 у стальной")
	t.check_eq(DB.building("condenser").unlock_id, "u_condenser", "🔒 у конденсатора")
	t.check_eq(DB.building("winch").unlock_id, "u_winch", "🔒 у лебёдки")
	t.check(DB.building("forge").flood_rule == SimTypes.FloodRule.DISABLED,
		"горн под водой не работает")
	t.check(DB.building("sluice").flood_rule == SimTypes.FloodRule.OK,
		"шлюз под водой работает — в этом его смысл")
	# Верша: затопление ей ПОЛЕЗНО, поэтому «не работает под водой» отменило бы
	# постройку целиком, а диапазон отметок держит её внизу — там, где её
	# накрывает каждой высокой водой (CONTENT-wave-1 §2).
	t.check(DB.building("weir").flood_rule == SimTypes.FloodRule.OK,
		"верша под водой работает — в этом её смысл")
	t.check_eq(DB.building("weir").max_mark, -1, "верша не поднимается выше −1")
	t.check_eq(DB.building("weir").min_mark, -3, "верша не опускается ниже −3")
	t.check_eq(DB.building("weir").special, "weir", "у верши свой маркер логики")

static func test_all_cards_present(t: TestCtx) -> void:
	t.check_eq(DB.card_ids().size(), 12, "все 12 карт docs/00 §10")
	for id: String in ["deep_dive", "fast_haul", "careful", "great_ebb",
			"calm_water", "the_find", "full_moon", "sea_loan", "travel_light",
			"long_breath", "the_dash", "muffled_bell"]:
		t.check(DB.has_card(id), "есть карта '%s'" % id)
		var c: CardDef = DB.card(id)
		t.check(c.rarity == "base" or c.rarity == "rare", "редкость карты %s задана" % id)
		t.check(c.rarity == "base" or not c.unlock_id.is_empty(),
			"у редкой карты %s есть разблокировка" % id)

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
	for bid: String in DB.building_ids():
		var bd: BuildingDef = DB.building(bid)
		all.append([bd.id, bd.display_key, str(bd.size), bd.cost, bd.min_mark,
			bd.max_mark, int(bd.flood_rule), bd.storm_breaks, bd.hp, bd.special])
	for cid2: String in DB.card_ids():
		var cd2: CardDef = DB.card(cid2)
		all.append([cd2.id, cd2.display_key, cd2.rarity, cd2.unlock_id, cd2.effects])
	for uid2: String in DB.unlock_ids():
		var ud2: UnlockDef = DB.unlock(uid2)
		all.append([ud2.id, ud2.display_key, ud2.cost, ud2.grants])
	for rid2: String in DB.recipe_ids():
		var rd: RecipeDef = DB.recipe(rid2)
		all.append([rd.id, rd.station_special, rd.inputs, rd.outputs,
			rd.work_seconds, rd.passive_per, rd.needs_agent])
	return JSON.stringify(all)

## Загрузчик обязан пережить перезагрузку кэша: ensure_loaded() зовётся из
## каждого геттера, в том числе из headless-теста без всякого _ready.
static func test_db_reload(t: TestCtx) -> void:
	var before: Array[String] = DB.item_ids()
	var before_traits: Array[String] = DB.trait_ids()
	DB.reload()
	t.check_eq(DB.item_ids(), before, "после reload состав БД тот же")
	t.check_eq(DB.trait_ids(), before_traits, "черты тоже")

## C2.7: ключ модификатора, который никто не читает, — такие же мёртвые данные,
## как опечатка. Так три черты (Неуклюжий, Бодряк, Запасливый) простояли
## пустышками: валидатор проверял ТОЛЬКО что ключ известен TraitKeys.
static func test_trait_keys_are_read_by_sim(t: TestCtx) -> void:
	var src: String = ""
	var d: DirAccess = DirAccess.open("res://sim/")
	t.check(d != null, "каталог res://sim/ читается")
	if d == null:
		return
	var files: Array[String] = []
	files.assign(d.get_files())
	files.sort()
	for f: String in files:
		# Сам список ключей не считается «чтением»: иначе объявление ключа
		# в trait_keys.gd проходило бы проверку за использование.
		if f.ends_with(".gd") and f != "trait_keys.gd":
			src += FileAccess.get_file_as_string("res://sim/" + f)
	for key: String in TraitKeys.all():
		t.check(src.contains('"%s"' % key),
			"ключ черт '%s' объявлен, но нигде в sim/ не читается" % key)

## A1.4 · SPEC-03, решение ОКОНЧАТЕЛЬНОЕ (docs/00 §10, подтверждено аудитом
## 22.08): плато ниже −8 даёт ВРЕМЯ, а не клетки, и утёс №1 не расширяется.
## Тест держит решение с обеих сторон — чтобы следующий проход не «починил»
## его в случайную сторону.
static func test_bottom_mark_is_final(t: TestCtx) -> void:
	t.check_eq(Balance.BOTTOM_MARK, -8, "дно карты — −8")
	var cliff: CliffDef = load("res://data/cliffs/cliff_01.tres") as CliffDef
	var lowest: int = Balance.TOP_MARK
	var marks: Dictionary[int, bool] = {}
	for p: Dictionary in cliff.platforms:
		var m: int = int(p["mark"])
		marks[m] = true
		lowest = mini(lowest, m)
	t.check_eq(lowest, Balance.BOTTOM_MARK, "площадок ниже дна в карте нет")
	for m2: int in range(Balance.BOTTOM_MARK, Balance.TOP_MARK + 1):
		t.check(marks.has(m2), "ярус %d в карте есть — дыр в лестнице отметок нет" % m2)
	# Карты вылазки опускают ПЛАТО воды, а не пол карты: «до −12» в описании
	# означает «дно открыто дольше», а не «появились ярусы −9…−12».
	for cid: String in DB.card_ids():
		var add: float = float(DB.card(cid).effects.get("low_plateau_add", 0.0))
		if is_zero_approx(add):
			continue
		t.check(add < 0.0, "карта %s опускает плато, а не поднимает" % cid)
		t.check(not marks.has(Balance.BOTTOM_MARK - 1),
			"и ниже дна клеток от неё не появляется")
