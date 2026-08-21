extends RefCounted
## Приёмка этапа 08: цепочки соли и металла, мокрый плавник, пассивные
## рецепты, лебёдка, скорость Кузнеца.

const CLIFF: String = "res://data/cliffs/cliff_01.tres"

static func _cliff() -> CliffDef:
	return load(CLIFF) as CliffDef

static func _world(seed_value: int) -> SimWorld:
	var w: SimWorld = SimWorld.new()
	w.new_run(seed_value, _cliff())
	w.events_out.clear()
	return w

static func _cell_on(mark: int, x: int, height: int) -> Vector2i:
	return Vector2i(x, Balance.mark_to_floor_cell_y(mark) - height)

## Ставит станцию сразу активной.
static func _station(w: SimWorld, def_id: String, mark: int, x: int) -> int:
	var d: BuildingDef = DB.building(def_id)
	return w.buildings.place(def_id, _cell_on(mark, x, d.size.y), w, true)

# --- Данные ---------------------------------------------------------------

static func test_recipes_match_spec(t: TestCtx) -> void:
	t.check_eq(DB.recipe_ids().size(), 9, "все рецепты docs/00 §9.1 (плюс вода) на месте")
	var forge: RecipeDef = DB.recipe("forge_ingot")
	t.check_eq(int(forge.inputs["scrap"]), 2, "горн: 2 утиля")
	t.check_eq(int(forge.inputs["driftwood"]), 1, "и 1 плавник")
	t.check_eq(int(forge.outputs["ingot"]), 1, "→ 1 слиток")
	t.check_approx(forge.work_seconds, 20.0, 0.01, "за 20 секунд")
	var salt: RecipeDef = DB.recipe("saltery_rations")
	t.check_eq(int(salt.outputs["rations"]), 2, "солильня даёт 2 провизии")
	t.check_eq(DB.recipe("evaporator_salt").passive_per, "low_phase",
		"испаритель работает за фазу отлива")
	t.check_eq(DB.recipe("ropery_gear").unlock_id, "u_gear", "снаряжение под 🔒")

## Опечатка в id входа делает рецепт молча неработающим.
static func test_recipe_references(t: TestCtx) -> void:
	var specials: Dictionary[String, bool] = {}
	for bid: String in DB.building_ids():
		specials[DB.building(bid).special] = true
	for rid: String in DB.recipe_ids():
		var r: RecipeDef = DB.recipe(rid)
		t.check(specials.has(r.station_special),
			"рецепт %s: нет постройки со special=%s" % [rid, r.station_special])
		for k: String in r.inputs:
			t.check(DB.has_item(k), "рецепт %s: вход '%s'" % [rid, k])
		for k2: String in r.outputs:
			t.check(DB.has_item(k2), "рецепт %s: выход '%s'" % [rid, k2])

# --- Цепочка металла ------------------------------------------------------

static func test_metal_chain(t: TestCtx) -> void:
	var w: SimWorld = _world(4242)
	_station(w, "forge", 3, 4)
	_station(w, "workbench", 3, 8)
	w.storage.store(0, StackUtil.make("scrap", 10, false))
	w.storage.store(0, StackUtil.make("driftwood", 10, false))
	# Заготовка на максимум: подвоз входов — тоже работа класса HAUL.
	w.policies.set_value(SimTypes.Policy.SUPPLY, 3)
	w.jobs.mark_dirty()

	var ticks: int = 0
	while ticks < 40000 and int(w.storage.totals().get("part", 0)) < 1:
		t.run_ticks(w, 1)
		ticks += 1
	t.check(int(w.storage.totals().get("ingot", 0)) > 0
		or int(w.storage.totals().get("part", 0)) > 0,
		"горн выплавил слитки")
	t.check(int(w.storage.totals().get("part", 0)) >= 1,
		"верстак сделал деталь за %d тиков" % ticks)

## Мокрый плавник горн не принимает — правило выводится из данных
## (flood_rule == WET), а не из хардкода id.
static func test_forge_refuses_wet_driftwood(t: TestCtx) -> void:
	var w: SimWorld = _world(11)
	var forge: int = _station(w, "forge", 3, 4)
	var b: Dictionary = w.buildings.buildings[forge]
	var r: RecipeDef = DB.recipe("forge_ingot")
	w.buildings.deliver(forge, StackUtil.make("scrap", 2, false), w)
	w.buildings.deliver(forge, StackUtil.make("driftwood", 3, true), w)
	t.check(not ProductionSystem.has_inputs(b, r), "мокрый плавник не считается")
	w.buildings.deliver(forge, StackUtil.make("driftwood", 1, false), w)
	t.check(ProductionSystem.has_inputs(b, r), "с сухим — рецепт готов")

## А Сушила, наоборот, мокрый плавник ждут.
static func test_dryer_dries_driftwood(t: TestCtx) -> void:
	var w: SimWorld = _world(13)
	_station(w, "dryer", 3, 4)
	w.storage.store(0, StackUtil.make("driftwood", 4, true))
	var wet_before: int = _wet_count(w, "driftwood")
	t.check(wet_before >= 4, "мокрый плавник лежит на складе")
	t.run_ticks(w, Balance.TICKS_PER_CYCLE)
	var wet_after: int = _wet_count(w, "driftwood")
	t.check_eq(wet_before - wet_after, Balance.DRYER_DRIFTWOOD_PER_CYCLE,
		"сушила высушили два полена за цикл")

static func _wet_count(w: SimWorld, item_id: String) -> int:
	var n: int = 0
	for s: Dictionary in w.storage.storages:
		for v: Variant in s["stacks"] as Array:
			var cur: Dictionary = v as Dictionary
			if str(cur["item_id"]) == item_id and bool(cur["wet"]):
				n += int(cur["count"])
	return n

static func test_dryer_makes_fiber(t: TestCtx) -> void:
	var w: SimWorld = _world(17)
	var dryer: int = _station(w, "dryer", 3, 4)
	w.buildings.deliver(dryer, StackUtil.make("kelp", 3, false), w)
	t.run_ticks(w, Balance.TICKS_PER_CYCLE)
	t.check(int(w.storage.totals().get("fiber", 0)) >= 1,
		"3 водоросли превратились в волокно")

# --- Цепочка соли ---------------------------------------------------------

## Полная цепочка: испаритель даёт соль, солильня превращает её в провизию.
static func test_salt_chain(t: TestCtx) -> void:
	var w: SimWorld = _world(4242)
	_station(w, "evaporator", -1, 14)
	_station(w, "saltery", 3, 4)
	w.storage.store(0, StackUtil.make("catch", 20, false))
	w.storage.store(0, StackUtil.make("freshwater", 20, false))
	w.policies.set_value(SimTypes.Policy.SUPPLY, 3)
	w.jobs.mark_dirty()
	t.run_ticks(w, Balance.TICKS_PER_CYCLE * 3)
	t.check(int(w.storage.totals().get("rations", 0)) >= 8 + 2,
		"к концу третьего цикла провизии стало больше стартовых восьми (%d)"
		% int(w.storage.totals().get("rations", 0)))

## Испаритель, накрытый водой в середине отлива, соли в этом цикле не даёт.
static func test_evaporator_needs_dry_low(t: TestCtx) -> void:
	var w: SimWorld = _world(19)
	var evap: int = _station(w, "evaporator", -1, 14)
	# Спокойный цикл: соль появляется.
	t.run_ticks(w, 450 + 1500 + 5)
	t.check_eq(int(w.storage.totals().get("salt", 0)), 1, "за сухой отлив — 1 соль")

	# Второй цикл: накрываем испаритель посреди отлива.
	t.run_ticks(w, 300 + 750 + 450 + 700)
	w.tide.level_override = 0.0
	t.run_ticks(w, 5)
	# Флаг проверяем сразу: на границе следующей фазы он сбрасывается.
	t.check(bool(w.buildings.buildings[evap]["flooded_in_phase"]),
		"флаг «был затоплен за фазу» выставлен")
	w.tide.level_override = NAN
	t.run_ticks(w, 800 + 5)
	t.check_eq(int(w.storage.totals().get("salt", 0)), 1,
		"после затопления посреди отлива соли не прибавилось")

static func test_evaporator_stops_in_storm(t: TestCtx) -> void:
	var w: SimWorld = _world(23)
	_station(w, "evaporator", -1, 14)
	w.is_storm = true
	t.run_ticks(w, 450 + 1500 + 5)
	t.check_eq(int(w.storage.totals().get("salt", 0)), 0, "в шторм соли нет")

# --- Пассивная вода -------------------------------------------------------

static func test_raincatcher_gives_water(t: TestCtx) -> void:
	var w: SimWorld = _world(29)
	var before: int = int(w.storage.totals().get("freshwater", 0))
	t.run_ticks(w, Balance.TICKS_PER_CYCLE)
	t.check_eq(int(w.storage.totals().get("freshwater", 0)) - before, 1,
		"стартовый дождесборник даёт 1 воду за цикл")

static func test_condenser_gives_two(t: TestCtx) -> void:
	var w: SimWorld = _world(31)
	w.unlocked.append("u_condenser")
	_station(w, "condenser", 5, 4)
	var before: int = int(w.storage.totals().get("freshwater", 0))
	t.run_ticks(w, Balance.TICKS_PER_CYCLE)
	t.check_eq(int(w.storage.totals().get("freshwater", 0)) - before, 3,
		"конденсатор +2 и дождесборник +1 за цикл")

# --- Скорость работы ------------------------------------------------------

## Замер в ТИКАХ, а не в секундах: секунды зависят от скорости игры.
static func test_smith_is_faster(t: TestCtx) -> void:
	var w: SimWorld = _world(37)
	var r: RecipeDef = DB.recipe("forge_ingot")
	var plain: SimAgent = SimAgent.new()
	plain.init_needs()
	plain.trait_ids = []
	plain.recompute_from_traits()
	var smith: SimAgent = SimAgent.new()
	smith.init_needs()
	smith.trait_ids = ["smith"]
	smith.recompute_from_traits()
	var t_plain: int = w.production.work_ticks_for(r, plain)
	var t_smith: int = w.production.work_ticks_for(r, smith)
	t.check_eq(t_plain, 200, "обычный агент кует слиток 20 секунд")
	t.check_eq(t_smith, 160, "Кузнец — на 25% быстрее (160 тиков)")
	# И только у своей станции: на верстаке черта не помогает.
	var bench: RecipeDef = DB.recipe("workbench_part")
	t.check_eq(w.production.work_ticks_for(bench, smith),
		w.production.work_ticks_for(bench, plain), "у верстака Кузнец обычный")

# --- Лебёдка --------------------------------------------------------------

static func test_winch_lifts_from_basket(t: TestCtx) -> void:
	var w: SimWorld = _world(41)
	w.unlocked.append("u_winch")
	var winch: int = _station(w, "winch", 0, 4)
	t.check(winch > 0, "лебёдка встала")
	var b: Dictionary = w.buildings.buildings[winch]
	var basket: Vector2i = ProductionSystem.basket_cell(b)
	w.storage.drop(basket, StackUtil.make("scrap", 3, false))
	var before: int = int(w.storage.totals().get("scrap", 0))
	# 6 секунд подъёма плюс запас на тик системы.
	t.run_ticks(w, int(Balance.WINCH_LIFT_SEC * Balance.TICKS_PER_SEC) + 5)
	t.check_eq(int(w.storage.totals().get("scrap", 0)) - before, 3,
		"стак из корзины оказался на складе")
	t.check(w.storage.ground_at(basket).is_empty(), "корзина опустела")

## Вода не вымывает груз из корзины — в этом смысл лебёдки.
static func test_basket_is_protected_from_water(t: TestCtx) -> void:
	var w: SimWorld = _world(43)
	w.unlocked.append("u_winch")
	var winch: int = _station(w, "winch", 0, 4)
	t.check(winch > 0, "лебёдка встала")
	var basket: Vector2i = ProductionSystem.basket_cell(w.buildings.buildings[winch])
	# Ломаем лебёдку, чтобы она не успела поднять груз до прилива.
	w.buildings.buildings[winch]["damaged"] = true
	w.tide.level_override = -8.0
	t.run_ticks(w, 2)
	w.storage.drop(basket, StackUtil.make("scrap", 2, false))
	w.tide.level_override = 0.0
	t.run_ticks(w, 5)
	t.check_eq(w.storage.ground_at(basket).size(), 1, "груз в корзине уцелел")

## Агенты с дна предпочитают корзину дальнему складу наверху.
static func test_haul_prefers_basket(t: TestCtx) -> void:
	var w: SimWorld = _world(47)
	w.unlocked.append("u_winch")
	var winch: int = _station(w, "winch", -1, 14)
	t.check(winch > 0, "лебёдка встала на −1")
	var basket: Vector2i = ProductionSystem.basket_cell(w.buildings.buildings[winch])
	w.tide.level_override = -8.0
	t.run_ticks(w, 2)
	var far: Vector2i = Vector2i(20, Balance.mark_to_floor_cell_y(-2))
	w.storage.drop(far, StackUtil.make("scrap", 1, false))
	w.jobs.mark_dirty()
	t.run_ticks(w, 2)
	var found: bool = false
	for id: int in w.jobs.order:
		var j: Dictionary = w.jobs.jobs[id]
		if str(j["kind"]) == "haul_ground" and (j["cell"] as Vector2i) == far:
			found = true
			t.check_eq(str(j["to_kind"]), "basket", "груз с дна несут в корзину")
			t.check_eq(j["to_cell"] as Vector2i, basket, "и именно в эту")
	t.check(found, "задача на переноску создана")

# --- Итог цикла и сериализация --------------------------------------------

static func test_cycle_report_has_produced(t: TestCtx) -> void:
	var w: SimWorld = _world(53)
	t.run_ticks(w, Balance.TICKS_PER_CYCLE - 1)
	w.tick()
	var report: Dictionary = {}
	for e: SimEvent in w.events_out:
		if e.type == "cycle_ended":
			report = e.data
	t.check(report.has("produced"), "в итоге цикла есть колонка «произведено»")
	t.check_eq(int((report["produced"] as Dictionary).get("freshwater", 0)), 1,
		"дождесборник попал в отчёт")

static func test_production_survives_save(t: TestCtx) -> void:
	var w: SimWorld = _world(2024)
	_station(w, "forge", 3, 4)
	w.unlocked.append("u_winch")
	var winch: int = _station(w, "winch", 0, 8)
	t.check(winch > 0, "лебёдка встала")
	w.storage.store(0, StackUtil.make("scrap", 10, false))
	w.storage.drop(ProductionSystem.basket_cell(w.buildings.buildings[winch]),
		StackUtil.make("kelp", 2, false))
	t.run_ticks(w, 2000)
	var text: String = JSON.stringify(w.to_dict(), "", true, true)
	var restored: SimWorld = SimWorld.new()
	restored.from_dict(JSON.parse_string(text) as Dictionary, _cliff())
	t.check_eq(JSON.stringify(restored.to_dict(), "", true, true), text,
		"производство переживает JSON")
	for i: int in 2000:
		t.run_ticks(w, 1)
		t.run_ticks(restored, 1)
	t.check_eq(TestCtx.state_hash(w), TestCtx.state_hash(restored),
		"после загрузки мир со станциями продолжается идентично")
