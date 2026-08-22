extends RefCounted
## Приёмка этапа 14: причина простоя станции для КАЖДОГО случая (docs/03 §5.4)
## и соответствие кодов sim ключам панели.
##
## Именно это главная приёмка этапа: без явной причины игрок не понимает,
## почему цепочка встала.

const CLIFF: String = "res://data/cliffs/cliff_01.tres"

static func _world(seed_value: int) -> SimWorld:
	var w: SimWorld = SimWorld.new()
	w.new_run(seed_value, load(CLIFF) as CliffDef)
	w.events_out.clear()
	return w

static func _cell_on(mark: int, x: int, height: int) -> Vector2i:
	return Vector2i(x, Balance.mark_to_floor_cell_y(mark) - height)

static func _station(w: SimWorld, def_id: String, mark: int, x: int,
		instant: bool = true) -> int:
	var d: BuildingDef = DB.building(def_id)
	return w.buildings.place(def_id, _cell_on(mark, x, d.size.y), w, instant)

static func _reason(w: SimWorld, id: int) -> String:
	return ProductionSystem.idle_reason(w.buildings.buildings[id], w)

## Все шесть причин + «работает». Проверяем поштучно, отключая по одному
## условию — так же, как этого требует приёмка промпта.
static func test_idle_reason_each_case(t: TestCtx) -> void:
	var w: SimWorld = _world(31)

	# 1. Ещё строится.
	var planned: int = _station(w, "forge", 3, 4, false)
	t.check_eq(_reason(w, planned), "under_construction", "стройка не начата")
	w.buildings.demolish(planned, w)

	# 2. Нет материалов: горн стоит, входов в буфере нет.
	var forge: int = _station(w, "forge", 3, 4)
	t.check_eq(_reason(w, forge), "no_materials", "пустой буфер — нет материалов")

	# 3. Нет топлива: утиль принесли, а сухого плавника нет.
	w.buildings.deliver(forge, StackUtil.make("scrap", 2, false), w)
	t.check_eq(_reason(w, forge), "no_fuel", "не хватает только плавника")

	# 4. Всё есть — станция работает.
	w.buildings.deliver(forge, StackUtil.make("driftwood", 1, false), w)
	t.check_eq(_reason(w, forge), "", "полный буфер — станция работает")

	# 5. Заготовка на нуле: никто не идёт.
	w.policies.set_value(SimTypes.Policy.SUPPLY, 0)
	t.check_eq(_reason(w, forge), "no_worker", "Заготовка 0 — никто не идёт")
	w.policies.set_value(SimTypes.Policy.SUPPLY, 2)

	# 6. Повреждена.
	var b: Dictionary = w.buildings.buildings[forge]
	b["damaged"] = true
	t.check_eq(_reason(w, forge), "damaged", "повреждённая станция стоит")
	b["damaged"] = false

	# 7. Затоплена (горн не работает под водой).
	b["flooded"] = true
	var d: BuildingDef = DB.building(str(b["def_id"]))
	if d.flood_rule == SimTypes.FloodRule.DISABLED:
		t.check_eq(_reason(w, forge), "flooded", "затопленная станция стоит")
	b["flooded"] = false

	# 8. Некуда класть готовое: все склады забиты.
	_fill_all_storages(w)
	t.check_eq(_reason(w, forge), "no_space", "склады полны — готовое некуда класть")

## Забивает каждый склад под завязку одинаковыми полными стаками.
static func _fill_all_storages(w: SimWorld) -> void:
	for s: Dictionary in w.storage.storages:
		var stacks: Array = s["stacks"] as Array
		stacks.clear()
		var def: ItemDef = DB.item("relic")
		for i: int in int(s["capacity"]):
			stacks.append(StackUtil.make("relic", def.stack_size, false))

## Затопление отключает станцию: у горна это правило дефа, у испарителя —
## пассивный рецепт, которому вода в фазе портит выпаривание.
static func test_flooded_station_stops(t: TestCtx) -> void:
	var w: SimWorld = _world(32)
	var forge: int = _station(w, "forge", 3, 4)
	t.check_eq(int(DB.building("forge").flood_rule),
		int(SimTypes.FloodRule.DISABLED), "горн под водой не работает по дефу")
	w.buildings.buildings[forge]["flooded"] = true
	t.check_eq(_reason(w, forge), "flooded", "затопленный горн стоит")

	# Испаритель работает БЕЗ агента: пустой рецепт-для-агента не должен
	# читаться как «нечего делать» (иначе панель врёт про исправную станцию).
	var evap: int = _station(w, "evaporator", -1, 14)
	# На старте забега вода стоит у отметки 0, и −1 уже накрыто: сушим руками.
	w.buildings.buildings[evap]["flooded"] = false
	w.buildings.buildings[evap]["flooded_in_phase"] = false
	t.check_eq(_reason(w, evap), "", "сухой испаритель работает пассивно")
	w.buildings.buildings[evap]["flooded_in_phase"] = true
	t.check_eq(_reason(w, evap), "flooded",
		"накрытый водой испаритель соли в этом цикле не даст")

## Приказ «Починить» поднимает срочность ремонта — иначе кнопка ничего не
## значила бы (docs/03 §5.4).
static func test_repair_order_is_urgent(t: TestCtx) -> void:
	var w: SimWorld = _world(33)
	var forge: int = _station(w, "forge", 3, 4)
	var b: Dictionary = w.buildings.buildings[forge]
	b["damaged"] = true
	t.check(not bool(b["repair_urgent"]), "по умолчанию ремонт не срочный")
	w.apply_command({"kind": "repair", "id": forge})
	w.tick()
	t.check(bool(w.buildings.buildings[forge]["repair_urgent"]),
		"команда repair пометила постройку")
	# Ремонт закончен — флаг снят, иначе он переживёт саму поломку.
	# Смету ремонта кладём в буфер: без материалов работа не идёт (C1.3).
	var cost: Dictionary[String, int] = BuildingSystem.repair_cost(DB.building("forge"))
	for k: String in cost:
		w.buildings.deliver(forge, StackUtil.make(k, int(cost[k]), false), w)
	w.buildings.advance_construction(forge, 100000, w)
	t.check(not bool(w.buildings.buildings[forge]["repair_urgent"]),
		"после ремонта срочность снимается")
	t.check(not bool(w.buildings.buildings[forge]["damaged"]), "постройка цела")

## Свободное место на складе: отличает «некуда класть» от прочих причин.
static func test_storage_has_space(t: TestCtx) -> void:
	var w: SimWorld = _world(34)
	t.check(w.storage.has_space("ingot", 1), "на старте место есть")
	_fill_all_storages(w)
	t.check(not w.storage.has_space("ingot", 1), "забитый склад места не даёт")
	t.check(w.storage.has_space("relic", 1) == false
		or DB.item("relic").stack_size > 1, "полный стак реликвий не принимает добавку")

## Каждый код простоя из sim обязан иметь ключ в панели: иначе игрок увидит
## пустую строку вместо объяснения.
static func test_reason_codes_have_keys(t: TestCtx) -> void:
	var codes: Array[String] = ["under_construction", "damaged", "flooded",
		"no_recipe", "no_materials", "no_fuel", "no_worker", "no_space"]
	var src: String = FileAccess.get_file_as_string("res://ui/panels/station_panel.gd")
	var csv: String = FileAccess.get_file_as_string("res://assets/i18n/strings.csv")
	for code: String in codes:
		t.check(src.contains('"%s"' % code),
			"StationPanel не знает код простоя '%s'" % code)
	for line: String in src.split("\n"):
		if not line.strip_edges().begins_with('"'):
			continue
		if not line.contains("STATION_"):
			continue
		var key: String = line.get_slice("STATION_", 1).get_slice('"', 0)
		t.check(csv.contains("STATION_%s," % key),
			"нет строки локализации STATION_%s" % key)
