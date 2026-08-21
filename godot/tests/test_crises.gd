extends RefCounted
## Приёмка этапа 09: календарь, сизигия, шторм, Приход, шлюзы и фонари.

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

## Прокручивает мир до нужного цикла и фазы. Считать тики нельзя: карты
## вылазки и шторм меняют длительность отлива, и фиксированное смещение
## после них разъезжается.
static func _until(t: TestCtx, w: SimWorld, cycle: int, phase: SimTypes.Phase,
		into_phase: int = 5) -> void:
	var guard: int = 0
	while guard < Balance.TICKS_PER_CYCLE * 20:
		if w.clock.cycle == cycle and w.clock.phase == phase:
			break
		t.run_ticks(w, 1)
		guard += 1
	t.run_ticks(w, into_phase)

## Достраивает спуск: без лестниц существам некуда плыть, а игроку — нечего
## терять на дне.
static func _ladders_down_to(w: SimWorld, bottom: int) -> void:
	for mark: int in range(-2, bottom - 1, -1):
		var span: Array[int] = w.terrain.platform_x_range(mark)
		var below: Array[int] = w.terrain.platform_x_range(mark - 1)
		if span.is_empty() or below.is_empty():
			continue
		w.terrain.add_ladder(Vector2i(maxi(span[0], below[0]),
			Balance.mark_to_floor_cell_y(mark)))

# --- Календарь ------------------------------------------------------------

## Кризис по расписанию, а не по кубику: игрок обязан видеть его заранее.
static func test_calendar_matches_spec(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var started: Dictionary[int, Array] = {}
	var announced: Dictionary[int, Array] = {}
	# Непрерывный прогон, а не по 3000 тиков: штормовой цикл короче на 30%,
	# и выравнивание по фиксированной длине после него разъезжается.
	for i: int in Balance.TICKS_PER_CYCLE * 13:
		w.tick()
		for e: SimEvent in w.events_out:
			if e.type == "crisis_started":
				_push(started, w.clock.cycle, int(e.data["type"]))
			elif e.type == "crisis_announced":
				_push(announced, int(e.data["cycle"]), int(e.data["type"]))
		w.events_out.clear()
		if w.clock.cycle > 12:
			break
	t.check((started.get(4, []) as Array).has(SimTypes.CrisisType.VISIT),
		"цикл 4 — первый Приход")
	t.check((started.get(6, []) as Array).has(SimTypes.CrisisType.SPRING_TIDE),
		"цикл 6 — сизигия")
	t.check((started.get(7, []) as Array).has(SimTypes.CrisisType.VISIT),
		"цикл 7 — Приход")
	t.check((started.get(10, []) as Array).has(SimTypes.CrisisType.STORM),
		"цикл 10 — шторм")
	t.check((started.get(10, []) as Array).has(SimTypes.CrisisType.VISIT),
		"и он совпадает с Приходом — пик сложности")
	t.check((started.get(12, []) as Array).has(SimTypes.CrisisType.SPRING_TIDE),
		"цикл 12 — сизигия под судно")
	t.check((announced.get(6, []) as Array).has(SimTypes.CrisisType.SPRING_TIDE),
		"сизигия объявлена ровно за цикл")
	t.check((announced.get(10, []) as Array).has(SimTypes.CrisisType.STORM),
		"шторм объявлен ровно за цикл")
	for cyc: int in [2, 3, 5, 8, 9, 11]:
		t.check(not started.has(cyc), "цикл %d спокойный" % cyc)

static func _push(into: Dictionary[int, Array], key: int, value: int) -> void:
	if not into.has(key):
		into[key] = []
	(into[key] as Array).append(value)

# --- Сизигия --------------------------------------------------------------

static func test_spring_tide_floods_plus_one(t: TestCtx) -> void:
	var w: SimWorld = _world(3)
	var b: int = w.buildings.place("bunk", _cell_on(1, 4, 1), w, true)
	t.check(b > 0, "койка на +1 стоит")
	# Обычный цикл: +1 сухо даже в разгар прилива.
	_until(t, w, 1, SimTypes.Phase.HIGH, 500)
	t.check(not bool(w.buildings.buildings[b]["flooded"]),
		"в обычный прилив койка на +1 суха")
	_until(t, w, 6, SimTypes.Phase.EBB, 5)
	t.check_eq(w.clock.cycle, 6, "мы в цикле сизигии")
	t.check_approx(w.tide.high_plateau, Balance.HIGH_LEVEL + Balance.SPRING_BONUS,
		0.01, "плато высокой воды поднято до +2")
	_until(t, w, 6, SimTypes.Phase.HIGH, 500)
	t.check(bool(w.buildings.buildings[b]["flooded"]), "сизигия накрыла койку на +1")
	# И плато возвращается на следующем цикле.
	_until(t, w, 7, SimTypes.Phase.EBB, 5)
	t.check_approx(w.tide.high_plateau, Balance.HIGH_LEVEL, 0.01,
		"после сизигии плато вернулось")

static func test_tide_records_cycle_high(t: TestCtx) -> void:
	var w: SimWorld = _world(5)
	t.run_ticks(w, 450 + 100)
	t.check_approx(w.tide.last_high_level, 0.0, 0.05,
		"максимум за цикл помнит высокую воду")
	t.run_ticks(w, 1500)
	t.check_approx(w.tide.last_high_level, 0.0, 0.05, "и не падает вместе с водой")

# --- Шторм ----------------------------------------------------------------

static func test_storm_shortens_low_and_breaks(t: TestCtx) -> void:
	var w: SimWorld = _world(7)
	var dryer: int = w.buildings.place("dryer", _cell_on(5, 4, 2), w, true)
	# Доходим до штормового цикла 10.
	_until(t, w, 10, SimTypes.Phase.EBB, 5)
	t.check_eq(w.clock.cycle, 10, "цикл шторма")
	t.check(w.is_storm, "is_storm поднят")
	# Карта цикла тоже влияет на длину отлива, поэтому сравниваем с базой ×0.7.
	var card_mult: float = float(w.cycle_modifiers.get("low_time_mult", 1.0))
	t.check_eq(w.clock.phase_len(SimTypes.Phase.LOW),
		int(round(1500.0 * card_mult * Balance.STORM_LOW_SCALE)),
		"отлив короче на 30%")
	# До пика (начало Высокой воды) сушила ещё целы.
	t.check(w.buildings.buildings.has(dryer), "сушила пока стоят")
	_until(t, w, 10, SimTypes.Phase.HIGH, 5)
	t.check(not w.buildings.buildings.has(dryer), "сушила сорвало на +5")
	# И после цикла всё возвращается.
	_until(t, w, 11, SimTypes.Phase.EBB, 5)
	t.check(not w.is_storm, "шторм кончился")
	t.check_eq(w.clock.phase_len(SimTypes.Phase.LOW),
		int(round(1500.0 * float(w.cycle_modifiers.get("low_time_mult", 1.0)))),
		"множитель шторма снят")

## Пик шторма: ниже +1 гибель, на +1..+2 — мокрый и −15 духа.
static func test_storm_peak_hits_agents(t: TestCtx) -> void:
	var w: SimWorld = _world(11)
	_ladders_down_to(w, -4)
	var low: SimAgent = w.agents.agents[0]
	var mid: SimAgent = w.agents.agents[1]
	var safe: SimAgent = w.agents.agents[2]
	# Политики в ноль: работа и авто-возврат увели бы агентов с их отметок.
	for pol: int in SimTypes.POLICY_ORDER:
		w.policies.set_value(pol, 0)
	w.jobs.mark_dirty()
	_until(t, w, 10, SimTypes.Phase.SIGNAL, 200)
	t.check(w.is_storm, "мы в штормовом цикле")
	_put(w, low, -2, 20)
	_put(w, mid, 2, 6)
	_put(w, safe, 5, 4)
	var mid_mood: float = mid.mood()
	_until(t, w, 10, SimTypes.Phase.HIGH, 5)
	t.check_eq(int(w.clock.phase), int(SimTypes.Phase.HIGH), "дошли до пика")
	t.check(not low.is_alive(), "агент на −2 погиб в шторм")
	t.check(mid.is_alive(), "агент на +2 выжил")
	t.check(mid.wet, "но промок")
	t.check(safe.is_alive() and not safe.wet, "агент на +5 не пострадал")
	t.check(mid.mood() < mid_mood, "и потерял дух")

## Ставит агента на отметку и оставляет там. recalled НЕ выставляем: он бы
## увёл агента наверх ровно от того, что мы проверяем.
static func _put(w: SimWorld, a: SimAgent, mark: int, x: int) -> void:
	a.platform_id = w.terrain.platform_of_mark(mark)
	a.x = float(x)
	a.target_x = a.x
	a.climb_to = -1
	a.climb_t = 0.0
	a.recalled = false
	a.state = SimTypes.AgentState.IDLE
	a.goto_platform = a.platform_id
	a.goto_x = a.x

static func test_is_storm_only_in_storm_cycle(t: TestCtx) -> void:
	var w: SimWorld = _world(13)
	var storm_cycles: Array[int] = []
	for i: int in Balance.TICKS_PER_CYCLE * 12:
		t.run_ticks(w, 1)
		if w.is_storm and not storm_cycles.has(w.clock.cycle):
			storm_cycles.append(w.clock.cycle)
		if w.clock.cycle > 11:
			break
	t.check_eq(storm_cycles, [10] as Array[int], "шторм ровно в цикле 10")

# --- Существа -------------------------------------------------------------

## Существа приходят с водой, в начале Высокой воды цикла Прихода.
static func test_creatures_arrive_and_leave(t: TestCtx) -> void:
	var w: SimWorld = _world(17)
	_until(t, w, 4, SimTypes.Phase.HIGH, 5)
	t.check_eq(w.clock.cycle, 4, "цикл 4")
	t.check_eq(w.crisis.creatures.size(), 1, "пришло одно существо")
	t.run_ticks(w, 750)
	t.check_eq(w.crisis.creatures.size(), 0, "с концом Высокой воды все ушли")

static func test_creature_counts_match_calendar(t: TestCtx) -> void:
	t.check_eq(_creatures_in_cycle(t, 4), 1, "цикл 4 — одно существо")
	t.check_eq(_creatures_in_cycle(t, 7), 2, "цикл 7 — два")
	t.check_eq(_creatures_in_cycle(t, 10), 3, "цикл 10 — три")

static func _creatures_in_cycle(t: TestCtx, cycle: int) -> int:
	var w: SimWorld = _world(19)
	_until(t, w, cycle, SimTypes.Phase.HIGH, 5)
	return w.crisis.creatures.size()

## Склад — украсть стак и уйти; станцию — грызть до поломки (docs/00 §9.3).
static func test_creature_steals_from_storage(t: TestCtx) -> void:
	var w: SimWorld = _world(23)
	_ladders_down_to(w, -8)
	var st: int = w.buildings.place("storage", _cell_on(-2, 20, 2), w, true)
	t.check(st > 0, "склад на −2 стоит")
	var sid: int = w.storage.storage_at(BuildingSystem.storage_cell(
		w.buildings.buildings[st]))
	w.storage.store(sid, StackUtil.make("scrap", 5, false))
	_until(t, w, 4, SimTypes.Phase.HIGH, 5)
	t.check_eq(w.crisis.creatures.size(), 1, "существо пришло")
	# Считаем ВЕСЬ склад: существо уносит случайный стак, и это может быть
	# не утиль (docs/00 §9.3 — «1 случайный стак»).
	var before: int = _storage_total(w, sid)
	# До конца Высокой воды: существо успевает доплыть и украсть.
	_until(t, w, 5, SimTypes.Phase.EBB, 0)
	t.check(_storage_total(w, sid) < before,
		"стак со склада украден (%d → %d)" % [before, _storage_total(w, sid)])

static func _storage_total(w: SimWorld, sid: int) -> int:
	var i: int = w.storage.storage_index(sid)
	if i < 0:
		return 0
	var n: int = 0
	for v: Variant in w.storage.storages[i]["stacks"] as Array:
		n += int((v as Dictionary)["count"])
	return n

static func test_creature_gnaws_station(t: TestCtx) -> void:
	var w: SimWorld = _world(29)
	_ladders_down_to(w, -8)
	var evap: int = w.buildings.place("evaporator", _cell_on(-1, 14, 1), w, true)
	t.check(evap > 0, "испаритель на −1 стоит")
	_until(t, w, 4, SimTypes.Phase.HIGH, 5)
	t.run_ticks(w, 740)
	t.check(bool(w.buildings.buildings[evap]["damaged"]),
		"существо сгрызло испаритель")

## Шлюз перекрывает РЕБРО графа: существо через него не проходит.
static func test_sluice_blocks_edge(t: TestCtx) -> void:
	var w: SimWorld = _world(31)
	_ladders_down_to(w, -4)
	var deep: int = w.terrain.platform_of_mark(-4)
	var up: int = w.terrain.platform_of_mark(-1)
	w.tide.level_override = 2.0
	t.run_ticks(w, 2)
	w.crisis._refresh_wet_graph(w)
	t.check(w.terrain.find_wet_path(deep, up).size() > 0, "путь наверх есть")

	# Шлюз в колонке лестницы −1/−2.
	var lx: int = _ladder_x(w, -1)
	t.check(lx >= 0, "лестница −1/−2 найдена")
	var gate: int = w.buildings.place("sluice", _cell_on(-1, lx, 2), w, true)
	t.check(gate > 0, "шлюз встал в колонке лестницы")
	w.crisis._refresh_wet_graph(w)
	t.check_eq(w.terrain.find_wet_path(deep, up).size(), 0,
		"через закрытый шлюз пути нет")

## TEST-09 · вторая лестница между теми же ярусами — обход шлюза.
##
## Граф связывает ОТМЕТКИ, а не лестницы, поэтому вторая лестница оставляет
## ребро живым: существо честно обходит шлюз, и это правило (запереть ярус —
## значит закрыть все его лестницы). Дефектом было другое: колонку для спуска
## выбирала первая попавшаяся лестница с нужной отметкой, и существо лезло
## СКВОЗЬ закрытый шлюз (SIM-05).
static func test_sluice_and_second_ladder(t: TestCtx) -> void:
	var w: SimWorld = _world(41)
	_ladders_down_to(w, -4)
	var deep: int = w.terrain.platform_of_mark(-4)
	var up: int = w.terrain.platform_of_mark(-1)
	w.tide.level_override = 2.0
	t.run_ticks(w, 2)
	var lx: int = _ladder_x(w, -1)
	t.check(lx >= 0, "первая лестница −1/−2 найдена")
	# Вторая лестница между теми же ярусами, в соседней колонке.
	var second_x: int = lx + 2
	var second: int = w.terrain.add_ladder(
		Vector2i(second_x, Balance.mark_to_floor_cell_y(-1)))
	t.check(second >= 0, "вторая лестница −1/−2 поставлена")

	var gate: int = w.buildings.place("sluice", _cell_on(-1, lx, 2), w, true)
	t.check(gate > 0, "шлюз встал на первую лестницу")
	w.crisis._refresh_wet_graph(w)
	t.check(w.terrain.find_wet_path(deep, up).size() > 0,
		"обход по второй лестнице остался — шлюз закрывает лестницу, а не ярус")
	t.check_eq(w.crisis._open_ladder_x(-1, float(lx), w), second_x,
		"на подъём выбрана ОТКРЫТАЯ лестница, а не та, где стоит шлюз")

	# Закрыли обе — яруса не достичь.
	var gate2: int = w.buildings.place("sluice", _cell_on(-1, second_x, 2), w, true)
	t.check(gate2 > 0, "второй шлюз встал")
	w.crisis._refresh_wet_graph(w)
	t.check_eq(w.terrain.find_wet_path(deep, up).size(), 0,
		"обе лестницы закрыты — пути наверх нет")
	t.check_eq(w.crisis._open_ladder_x(-1, float(lx), w), -1,
		"и открытой колонки не осталось")

## Шлюз мимо колонки лестницы — это отказ размещения, а не тихо мёртвая
## постройка: раньше игрок ставил его в соседней клетке и не понимал,
## почему существа проходят насквозь.
static func test_sluice_needs_a_ladder(t: TestCtx) -> void:
	var w: SimWorld = _world(43)
	_ladders_down_to(w, -4)
	var lx: int = _ladder_x(w, -1)
	t.check_eq(w.buildings.place_error("sluice", _cell_on(-1, lx, 2), w), "",
		"в колонке лестницы шлюз ставится")
	t.check_eq(w.buildings.place_error("sluice", _cell_on(-1, lx + 1, 2), w),
		"ERR_NO_LADDER", "на клетку мимо — отказ с причиной")

static func _ladder_x(w: SimWorld, mark_top: int) -> int:
	for l: Dictionary in w.terrain.ladders:
		if int(l["mark_top"]) == mark_top:
			return int(l["x"])
	return -1

## Фонарь запрещает УЗЕЛ: существо в его радиус не заходит.
static func test_lantern_blocks_node(t: TestCtx) -> void:
	var w: SimWorld = _world(37)
	_ladders_down_to(w, -4)
	w.tide.level_override = 2.0
	t.run_ticks(w, 2)
	var target: int = w.terrain.platform_of_mark(-1)
	w.crisis._refresh_wet_graph(w)
	t.check(w.terrain.is_wet_node(target), "узел −1 доступен существам")
	var lamp: int = w.buildings.place("lantern",
		Vector2i(18, Balance.mark_to_floor_cell_y(-1) - 1), w, true)
	t.check(lamp > 0, "фонарь встал на −1")
	# Только что поставленный фонарь ещё не заправлен: топливо приходит
	# на границе цикла.
	w.buildings.on_cycle_started(w)
	w.crisis._refresh_wet_graph(w)
	t.check(not w.terrain.is_wet_node(target), "освещённый узел для существ закрыт")

## При полном перекрытии существо бродит у спавна, а не зависает.
static func test_creature_idles_when_cut_off(t: TestCtx) -> void:
	var w: SimWorld = _world(41)
	# Лестниц вниз нет вовсе — колония недосягаема с моря.
	_until(t, w, 4, SimTypes.Phase.HIGH, 5)
	t.check_eq(w.crisis.creatures.size(), 1, "существо пришло")
	t.run_ticks(w, 400)
	t.check_eq(w.crisis.creatures.size(), 1, "и никуда не делось")
	t.check_eq(int(w.crisis.creatures[0]["target_id"]), -1, "цели у него нет")
	# Главное — прогон не упал и мир детерминирован.
	t.check(w.agents.alive_count() > 0, "колония цела")

## Существо рядом бьёт по духу ровно один раз за цикл на агента.
static func test_creature_scare_once_per_cycle(t: TestCtx) -> void:
	var w: SimWorld = _world(43)
	_ladders_down_to(w, -8)
	_until(t, w, 4, SimTypes.Phase.HIGH, 5)
	t.check_eq(w.crisis.creatures.size(), 1, "существо пришло")
	var a: SimAgent = w.agents.agents[0]
	var c: Dictionary = w.crisis.creatures[0]
	_put(w, a, int(w.terrain.platforms[int(c["platform"])]["mark"]), int(float(c["x"])))
	var before: float = a.mood()
	t.run_ticks(w, 100)
	t.check(a.scared_this_cycle, "агент испугался")
	var after: float = a.mood()
	t.check_approx(before - after, 10.0, 1.0, "и потерял ровно 10 духа")
	t.run_ticks(w, 200)
	t.check_approx(a.mood(), after, 1.0, "повторно за тот же цикл — не пугается")

# --- Отчёт и сериализация -------------------------------------------------

static func test_cycle_report_has_crises(t: TestCtx) -> void:
	var w: SimWorld = _world(47)
	_until(t, w, 4, SimTypes.Phase.HIGH, 0)
	# Тикаем вручную до границы цикла: run_ticks чистит события, а отчёт
	# приходит ровно на ней.
	var report: Dictionary = {}
	for i: int in Balance.TICKS_PER_CYCLE * 2:
		w.tick()
		for e: SimEvent in w.events_out:
			if e.type == "cycle_ended":
				report = e.data
		if not report.is_empty():
			break
		w.events_out.clear()
	t.check(report.has("crises"), "в итоге цикла есть список кризисов")
	t.check(report.has("damage") and report.has("stolen"),
		"и колонки урона и краж")
	t.check((report["crises"] as Array).has(SimTypes.CrisisType.VISIT),
		"цикл 4 отмечен Приходом")

static func test_crises_survive_save(t: TestCtx) -> void:
	var w: SimWorld = _world(2024)
	_ladders_down_to(w, -4)
	_until(t, w, 4, SimTypes.Phase.HIGH, 50)
	t.check_eq(w.crisis.creatures.size(), 1, "существо в мире")
	var text: String = JSON.stringify(w.to_dict(), "", true, true)
	var restored: SimWorld = SimWorld.new()
	restored.from_dict(JSON.parse_string(text) as Dictionary, _cliff())
	t.check_eq(JSON.stringify(restored.to_dict(), "", true, true), text,
		"кризисы и существа переживают JSON")
	for i: int in 600:
		t.run_ticks(w, 1)
		t.run_ticks(restored, 1)
	t.check_eq(TestCtx.state_hash(w), TestCtx.state_hash(restored),
		"после загрузки мир с существами продолжается идентично")

static func test_determinism_with_crises(t: TestCtx) -> void:
	var a: SimWorld = _world(31337)
	var b: SimWorld = _world(31337)
	_ladders_down_to(a, -4)
	_ladders_down_to(b, -4)
	for i: int in 15000:
		t.run_ticks(a, 1)
		t.run_ticks(b, 1)
		if i % 3000 == 0 and TestCtx.state_hash(a) != TestCtx.state_hash(b):
			t.check(false, "миры с кризисами разошлись на тике %d" % i)
			return
	t.check_eq(TestCtx.state_hash(a), TestCtx.state_hash(b),
		"15 000 тиков с кризисами: состояния совпадают")
