extends RefCounted
## Приёмка этапа 07: размещение, полный цикл стройки, затопление, шторм,
## ремонт, снос, стартовые постройки.

const CLIFF: String = "res://data/cliffs/cliff_01.tres"

static func _cliff() -> CliffDef:
	return load(CLIFF) as CliffDef

static func _world(seed_value: int) -> SimWorld:
	var w: SimWorld = SimWorld.new()
	w.new_run(seed_value, _cliff())
	w.events_out.clear()
	return w

## Клетка ВЕРХНЕГО левого угла постройки, стоящей на полу отметки mark.
## Нижний ряд постройки лежит НАД полом, а сам пол — её опора.
static func _cell_on(mark: int, x: int, height: int) -> Vector2i:
	return Vector2i(x, Balance.mark_to_floor_cell_y(mark) - height)

# --- Размещение -----------------------------------------------------------

static func test_place_error_reasons(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	# Горн только на жилых ярусах (≥+1).
	t.check_eq(w.buildings.place_error("forge", _cell_on(-2, 20, 2), w), "ERR_MARK",
		"горн на дне не ставится")
	t.check_eq(w.buildings.place_error("forge", _cell_on(3, 4, 2), w), "",
		"а на +3 ставится")
	# 🔒-постройка без разблокировки.
	t.check_eq(w.buildings.place_error("ladder_steel", Vector2i(25,
		Balance.mark_to_floor_cell_y(-2)), w), "ERR_LOCKED",
		"стальная лестница заперта до разблокировки")
	w.unlocked.append("u_steel_ladder")
	t.check_eq(w.buildings.place_error("ladder_steel", Vector2i(25,
		Balance.mark_to_floor_cell_y(-2)), w), "",
		"после разблокировки ставится")
	# В воздухе, без опоры.
	t.check_eq(w.buildings.place_error("hearth", _cell_on(3, 4, 1) - Vector2i(0, 1), w),
		"ERR_NO_SUPPORT", "постройка не висит в воздухе")
	# Правее площадки — тоже без опоры.
	t.check_eq(w.buildings.place_error("hearth", _cell_on(3, 40, 1), w),
		"ERR_NO_SUPPORT", "за краем площадки опоры нет")

static func test_occupied_cells(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var cell: Vector2i = _cell_on(3, 4, 1)
	t.check(w.buildings.place("hearth", cell, w, true) > 0, "первый очаг встал")
	t.check_eq(w.buildings.place_error("hearth", cell, w), "ERR_OCCUPIED",
		"на занятое место второй не влезет")
	# Очаг 2×1: соседняя клетка тоже занята.
	t.check_eq(w.buildings.place_error("hearth", cell + Vector2i(1, 0), w),
		"ERR_OCCUPIED", "перекрытие по ширине тоже видно")
	t.check_eq(w.buildings.place_error("hearth", cell + Vector2i(2, 0), w), "",
		"а рядом — свободно")

# --- Полный цикл стройки --------------------------------------------------

## Главная приёмка: разместили → агенты принесли материалы → построили.
static func test_full_build_cycle(t: TestCtx) -> void:
	var w: SimWorld = _world(4242)
	w.storage.store(0, StackUtil.make("scrap", 6, false))
	var cell: Vector2i = _cell_on(3, 4, 2)
	var id: int = w.buildings.place("forge", cell, w)
	t.check(id > 0, "горн размещён")
	t.check_eq(int(w.buildings.buildings[id]["state"]),
		int(SimTypes.BuildState.PLANNED), "сначала это план")

	var ticks: int = 0
	while ticks < 20000 \
			and int(w.buildings.buildings[id]["state"]) != int(SimTypes.BuildState.ACTIVE):
		t.run_ticks(w, 1)
		ticks += 1
	t.check_eq(int(w.buildings.buildings[id]["state"]), int(SimTypes.BuildState.ACTIVE),
		"горн достроен за %d тиков" % ticks)
	t.check(w.buildings.is_working(w.buildings.buildings[id]), "и работает")

## Дублирование HAUL-задач — главная ошибка этого этапа: без учёта уже
## заказанного шестеро агентов несут шесть комплектов на одну постройку.
static func test_no_duplicate_haul_jobs(t: TestCtx) -> void:
	var w: SimWorld = _world(7)
	w.storage.store(0, StackUtil.make("scrap", 20, false))
	var id: int = w.buildings.place("forge", _cell_on(3, 4, 2), w)
	var max_seen: int = 0
	for i: int in 100:
		t.run_ticks(w, 1)
		var n: int = 0
		for jid: int in w.jobs.order:
			var j: Dictionary = w.jobs.jobs[jid]
			if str(j["kind"]) == "haul_request" and int(j["to_id"]) == id:
				n += 1
		max_seen = maxi(max_seen, n)
	# Горн стоит 6 утиля; стак 10 → одна задача покрывает всё.
	t.check(max_seen <= 2,
		"на постройку заказано не больше пары доставок, а не сотня (было %d)" % max_seen)

## Лестница, достроенная агентами, появляется в графе — и путь вниз открывается.
static func test_built_ladder_opens_path(t: TestCtx) -> void:
	var w: SimWorld = _world(9)
	var top: int = w.terrain.platform_of_mark(6)
	var deep: int = w.terrain.platform_of_mark(-3)
	t.check_eq(w.terrain.find_path(top, deep).size(), 0, "до −3 пути нет")
	var id: int = w.buildings.place("ladder_wood",
		Vector2i(25, Balance.mark_to_floor_cell_y(-2)), w, true)
	t.check(id > 0, "лестница поставлена")
	t.check(w.terrain.find_path(top, deep).size() > 0, "путь до −3 открылся")

# --- Затопление -----------------------------------------------------------

static func test_flooding_rules(t: TestCtx) -> void:
	var w: SimWorld = _world(11)
	# Сначала отлив: постройки должны родиться сухими, иначе испаритель
	# потеряет соль ещё до того, как мы её туда положим.
	w.tide.level_override = -8.0
	t.run_ticks(w, 2)
	var forge: int = w.buildings.place("forge", _cell_on(1, 4, 2), w, true)
	var ladder: int = w.buildings.place("ladder_wood",
		Vector2i(25, Balance.mark_to_floor_cell_y(-2)), w, true)
	var evap: int = w.buildings.place("evaporator", _cell_on(-1, 14, 1), w, true)
	t.check(evap > 0, "испаритель встал на −1")
	(w.buildings.buildings[evap]["buffer"] as Dictionary)["salt"] = 3
	t.check(not bool(w.buildings.buildings[evap]["flooded"]), "на отливе испаритель сух")

	w.tide.level_override = 2.0                     # накрыло всё до +2
	t.run_ticks(w, 2)
	t.check(bool(w.buildings.buildings[forge]["flooded"]), "горн затоплен")
	t.check(not w.buildings.is_working(w.buildings.buildings[forge]),
		"затопленный горн не работает")
	t.check(w.buildings.is_working(w.buildings.buildings[ladder]),
		"лестница под водой работает")
	t.check_eq(int((w.buildings.buildings[evap]["buffer"] as Dictionary)["salt"]), 0,
		"испаритель потерял накопленную соль")

# --- Шторм ----------------------------------------------------------------

static func test_storm(t: TestCtx) -> void:
	var w: SimWorld = _world(13)
	w.unlocked.append("u_steel_ladder")
	var wood: int = w.buildings.place("ladder_wood",
		Vector2i(25, Balance.mark_to_floor_cell_y(-2)), w, true)
	# Стальная — на ярус ниже, иначе она дублирует ребро −2/−3 и проверка
	# «ребро исчезло из графа» ничего не докажет.
	var steel: int = w.buildings.place("ladder_steel",
		Vector2i(28, Balance.mark_to_floor_cell_y(-3)), w, true)
	var dryer: int = w.buildings.place("dryer", _cell_on(5, 4, 2), w, true)
	var high_storage: int = w.buildings.place("storage", _cell_on(5, 7, 2), w, true)
	t.check(dryer > 0 and high_storage > 0, "сушила и склад на +5 стоят")

	var deep: int = w.terrain.platform_of_mark(-3)
	var top: int = w.terrain.platform_of_mark(6)
	t.check(w.terrain.find_path(top, deep).size() > 0, "путь вниз есть до шторма")

	w.buildings.on_storm(w)
	t.check(bool(w.buildings.buildings[wood]["damaged"]), "деревянная лестница сломана")
	t.check(not bool(w.buildings.buildings[steel]["damaged"]), "стальная цела")
	t.check(not w.buildings.buildings.has(dryer), "сушила сорвало в ноль на +5")
	# Склад на +5 выше STORM_SAFE_MARK — шторм его не трогает вовсе.
	t.check(w.buildings.buildings.has(high_storage), "склад на +5 цел")
	t.check_eq(w.terrain.find_path(top, deep).size(), 0,
		"ребро сломанной лестницы исчезло из графа")

## Агент, шедший по сломанному ребру, не должен зависнуть.
static func test_agent_survives_broken_ladder(t: TestCtx) -> void:
	var w: SimWorld = _world(17)
	var wood: int = w.buildings.place("ladder_wood",
		Vector2i(25, Balance.mark_to_floor_cell_y(-2)), w, true)
	var a: SimAgent = w.agents.agents[0]
	a.goto_platform = w.terrain.platform_of_mark(-3)
	a.goto_x = 25.0
	a.intent = SimTypes.AgentState.IDLE
	a.state = SimTypes.AgentState.GOTO
	a.path_graph_version = -1
	t.run_ticks(w, 200)
	w.buildings.on_storm(w)
	t.run_ticks(w, 200)
	t.check(a.is_alive(), "агент жив")
	t.check_eq(a.path_graph_version, w.terrain.graph_version,
		"и пересчитал путь после исчезновения ребра")

## Склад переживает два шторма — не спецкейсом, а потому что у него hp = 2.
static func test_storage_hp_two(t: TestCtx) -> void:
	var w: SimWorld = _world(19)
	var id: int = w.buildings.place("storage", _cell_on(-1, 14, 2), w, true)
	t.check(id > 0, "склад на −1 стоит")
	w.buildings.on_storm(w)
	t.check(not bool(w.buildings.buildings[id]["damaged"]), "первый шторм пережил")
	t.check_eq(int(w.buildings.buildings[id]["hp"]), 1, "но потерял единицу прочности")
	w.buildings.on_storm(w)
	t.check(bool(w.buildings.buildings[id]["damaged"]), "второй шторм сломал")

# --- Ремонт и снос --------------------------------------------------------

static func test_repair_restores(t: TestCtx) -> void:
	var w: SimWorld = _world(23)
	var id: int = w.buildings.place("ladder_wood",
		Vector2i(25, Balance.mark_to_floor_cell_y(-2)), w, true)
	w.buildings.on_storm(w)
	t.check(bool(w.buildings.buildings[id]["damaged"]), "сломана")
	var d: BuildingDef = DB.building("ladder_wood")
	var done: bool = false
	for i: int in 5000:
		if w.buildings.advance_construction(id, 1, w):
			done = true
			break
	t.check(done, "ремонт завершился")
	t.check(not bool(w.buildings.buildings[id]["damaged"]), "постройка снова цела")
	t.check_eq(int(w.buildings.buildings[id]["hp"]), d.hp, "прочность восстановлена")
	t.check(w.terrain.find_path(w.terrain.platform_of_mark(6),
		w.terrain.platform_of_mark(-3)).size() > 0, "ребро вернулось в граф")

## Ремонт стоит половину, округление вниз.
static func test_repair_cost_is_half(t: TestCtx) -> void:
	var cost: Dictionary[String, int] = BuildingSystem.repair_cost(DB.building("forge"))
	t.check_eq(int(cost.get("scrap", 0)), 3, "ремонт горна — 3 утиля из 6")
	var cost2: Dictionary[String, int] = BuildingSystem.repair_cost(DB.building("ladder_wood"))
	t.check_eq(int(cost2.get("driftwood", 0)), 1, "ремонт лестницы — 1 плавник из 3")

static func test_demolish_refunds_half(t: TestCtx) -> void:
	var w: SimWorld = _world(29)
	var cell: Vector2i = _cell_on(3, 4, 2)
	var id: int = w.buildings.place("forge", cell, w, true)
	var before: int = _ground_count(w, "scrap")
	t.check(w.buildings.demolish(id, w), "снос прошёл")
	t.check(not w.buildings.buildings.has(id), "постройки больше нет")
	t.check_eq(_ground_count(w, "scrap") - before, 3, "вернулось 3 утиля из 6")
	t.check_eq(w.buildings.building_at(cell), -1, "клетка освободилась")

## TEST-01 · снос недостроенного не создаёт ресурсы (SIM-02). Стоимость
## списывается только при ЗАВЕРШЕНИИ стройки, поэтому возврат «половины
## стоимости» из PLANNED/UNDER_CONSTRUCTION был бесконечным дублированием:
## поставить Горн за 6 утиля → сразу снести → 3 утиля из воздуха.
static func test_demolish_unbuilt_creates_nothing(t: TestCtx) -> void:
	# PLANNED, буфер пуст: на земле не должно появиться ничего.
	var w: SimWorld = _world(41)
	var id: int = w.buildings.place("forge", _cell_on(3, 4, 2), w)
	t.check_eq(int(w.buildings.buildings[id]["state"]),
		int(SimTypes.BuildState.PLANNED), "постройка запланирована, не достроена")
	var before: int = _world_total(w, "scrap")
	t.check(w.buildings.demolish(id, w), "снос прошёл")
	t.check_eq(_world_total(w, "scrap"), before,
		"снос PLANNED не изменил суммарный утиль в мире")

	# UNDER_CONSTRUCTION с полным буфером: возвращается РОВНО буфер.
	var w2: SimWorld = _world(43)
	var id2: int = w2.buildings.place("forge", _cell_on(3, 4, 2), w2)
	var cost: int = int(DB.building("forge").cost["scrap"])
	w2.buildings.deliver(id2, StackUtil.make("scrap", cost, false), w2)
	w2.buildings.tick(w2)
	t.check_eq(int(w2.buildings.buildings[id2]["state"]),
		int(SimTypes.BuildState.UNDER_CONSTRUCTION), "стройка началась")
	var before2: int = _world_total(w2, "scrap")
	w2.buildings.demolish(id2, w2)
	t.check_eq(_world_total(w2, "scrap"), before2,
		"снос недостроенной вернул ровно буфер, ни единицей больше")

	# ACTIVE: стоимость потрачена, половина возвращается — это верно.
	var w3: SimWorld = _world(47)
	var id3: int = w3.buildings.place("forge", _cell_on(3, 4, 2), w3, true)
	var before3: int = _world_total(w3, "scrap")
	w3.buildings.demolish(id3, w3)
	t.check_eq(_world_total(w3, "scrap") - before3,
		cost / Balance.DEMOLISH_REFUND_FRACTION,
		"снос достроенной вернул половину стоимости")

## Весь предмет в мире: склады + буферы построек + земля. Проверять только
## землю мало — при сносе буфер тоже уезжает на землю, и «выросло на 4»
## неотличимо от «выросло на 4 из воздуха».
static func _world_total(w: SimWorld, item_id: String) -> int:
	var n: int = int(w.storage.totals().get(item_id, 0))
	n += _ground_count(w, item_id)
	for id: int in w.buildings.order:
		var buf: Dictionary = w.buildings.buildings[id]["buffer"] as Dictionary
		for k: Variant in buf:
			if StackUtil.key_item(str(k)) == item_id:
				n += int(buf[k])
	return n

static func _ground_count(w: SimWorld, item_id: String) -> int:
	var n: int = 0
	for g: Dictionary in w.storage.ground:
		var s: Dictionary = g["stack"] as Dictionary
		if str(s["item_id"]) == item_id:
			n += int(s["count"])
	return n

## Уже принесённые материалы при сносе тоже не пропадают.
static func test_demolish_returns_buffer(t: TestCtx) -> void:
	var w: SimWorld = _world(31)
	var id: int = w.buildings.place("forge", _cell_on(3, 4, 2), w)
	(w.buildings.buildings[id]["buffer"] as Dictionary)["scrap"] = 4
	var before: int = _ground_count(w, "scrap")
	w.buildings.demolish(id, w)
	t.check(_ground_count(w, "scrap") - before >= 4, "вложенные материалы вернулись")

# --- Стартовые постройки --------------------------------------------------

static func test_start_buildings(t: TestCtx) -> void:
	var w: SimWorld = _world(37)
	var kinds: Dictionary[String, int] = {}
	for id: int in w.buildings.order:
		var b: Dictionary = w.buildings.buildings[id]
		kinds[str(b["def_id"])] = int(kinds.get(str(b["def_id"]), 0)) + 1
		t.check_eq(int(b["state"]), int(SimTypes.BuildState.ACTIVE),
			"стартовая постройка %s сразу активна" % str(b["def_id"]))
	t.check_eq(int(kinds.get("hearth", 0)), 1, "очаг на старте есть")
	t.check_eq(int(kinds.get("raincatcher", 0)), 1, "дождесборник тоже")
	t.check_eq(int(kinds.get("storage", 0)), 1, "и склад")
	t.check_eq(w.storage.storages.size(), 1, "склад зарегистрирован ровно один раз")

## Заглушка heat_sources этапа 05 закрыта: тепло даёт настоящий очаг.
static func test_hearth_is_the_heat_source(t: TestCtx) -> void:
	var w: SimWorld = _world(41)
	t.check_eq(w.heat_sources().size(), 1, "источник тепла один — очаг")
	var hearth: Dictionary = w.buildings.with_special("hearth")[0]
	t.check_eq(w.heat_sources()[0], hearth["cell"] as Vector2i, "и это его клетка")
	# Без топлива очаг гаснет и перестаёт быть источником.
	hearth["lit"] = false
	w.refresh_heat_sources()
	t.check_eq(w.heat_sources().size(), 0, "погасший очаг не греет")

static func test_hearth_burns_fuel(t: TestCtx) -> void:
	var w: SimWorld = _world(43)
	var before: int = w.storage.totals().get("driftwood", 0)
	t.run_ticks(w, Balance.TICKS_PER_CYCLE)
	t.check_eq(int(w.storage.totals().get("driftwood", 0)), before - 1,
		"за цикл очаг сжёг одно полено")
	var hearth: Dictionary = w.buildings.with_special("hearth")[0]
	t.check(bool(hearth["lit"]), "и продолжает гореть")

# --- Сериализация и детерминизм -------------------------------------------

static func test_buildings_survive_save(t: TestCtx) -> void:
	var w: SimWorld = _world(2024)
	w.storage.store(0, StackUtil.make("scrap", 10, false))
	w.buildings.place("forge", _cell_on(3, 4, 2), w)
	t.run_ticks(w, 2500)
	var text: String = JSON.stringify(w.to_dict(), "", true, true)
	var restored: SimWorld = SimWorld.new()
	restored.from_dict(JSON.parse_string(text) as Dictionary, _cliff())
	t.check_eq(JSON.stringify(restored.to_dict(), "", true, true), text,
		"постройки переживают JSON")
	t.check_eq(restored.buildings.building_at(_cell_on(3, 4, 2)),
		w.buildings.building_at(_cell_on(3, 4, 2)), "сетка занятости восстановлена")
	for i: int in 2000:
		t.run_ticks(w, 1)
		t.run_ticks(restored, 1)
	t.check_eq(TestCtx.state_hash(w), TestCtx.state_hash(restored),
		"после загрузки мир с постройками продолжается идентично")

static func test_determinism_with_buildings(t: TestCtx) -> void:
	var a: SimWorld = _world(31337)
	var b: SimWorld = _world(31337)
	for i: int in 10000:
		t.run_ticks(a, 1)
		t.run_ticks(b, 1)
		if i % 2000 == 0 and TestCtx.state_hash(a) != TestCtx.state_hash(b):
			t.check(false, "миры с постройками разошлись на тике %d" % i)
			return
	t.check_eq(TestCtx.state_hash(a), TestCtx.state_hash(b),
		"10 000 тиков с постройками: состояния совпадают")
