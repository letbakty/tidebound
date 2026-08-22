extends RefCounted
## Приёмка этапа 11: конец забега, очки, разблокировки, сейв на диск.
##
## Файловые проверки идут через SaveIO напрямую: автолоады (Game, Meta,
## SaveService) в headless-раннере не создаются, а логика записи и чтения
## живёт именно в SaveIO.

const CLIFF: String = "res://data/cliffs/cliff_01.tres"
const TEST_PATH: String = "user://test_save.json"

static func _cliff() -> CliffDef:
	return load(CLIFF) as CliffDef

static func _world(seed_value: int, unlocks: Array[String] = []) -> SimWorld:
	var w: SimWorld = SimWorld.new()
	w.new_run(seed_value, _cliff(), unlocks)
	w.events_out.clear()
	return w

static func _until_cycle(t: TestCtx, w: SimWorld, cycle: int) -> void:
	var guard: int = 0
	while w.clock.cycle < cycle and not w.run_state.finished \
			and guard < Balance.TICKS_PER_CYCLE * 30:
		t.run_ticks(w, 1)
		guard += 1

# --- Полный забег ---------------------------------------------------------

## Главная приёмка: автопилотный забег доходит до судна и даёт очки.
static func test_full_run_reaches_ship(t: TestCtx) -> void:
	var w: SimWorld = _world(4242)
	var report: Dictionary = _run_to_end(t, w)
	t.check(not report.is_empty(), "забег завершился")
	t.check_eq(int(report["end"]), int(SimTypes.RunEnd.SHIP), "и завершился судном")
	t.check_eq(int(report["cycles"]), Balance.CYCLES_PER_RUN, "прожито 12 циклов")
	t.check(int(report["score"]) > 0, "очков больше нуля (%d)" % int(report["score"]))
	# Разбивка обязана сходиться с итогом — иначе экран итогов врёт игроку.
	var sum: int = 0
	for k: Variant in report["breakdown"] as Dictionary:
		sum += int((report["breakdown"] as Dictionary)[k])
	t.check_eq(sum, int(report["score"]), "разбивка сходится с суммой")

static func _run_to_end(t: TestCtx, w: SimWorld) -> Dictionary:
	var report: Dictionary = {}
	for i: int in Balance.TICKS_PER_CYCLE * 20:
		w.tick()
		for e: SimEvent in w.events_out:
			if e.type == "run_ended":
				report = e.data["report"] as Dictionary
		w.events_out.clear()
		if not report.is_empty():
			break
	return report

static func test_ship_arrives_before_run_ends(t: TestCtx) -> void:
	var w: SimWorld = _world(11)
	var arrived_cycle: int = -1
	for i: int in Balance.TICKS_PER_CYCLE * 20:
		w.tick()
		for e: SimEvent in w.events_out:
			if e.type == "ship_arrived":
				arrived_cycle = w.clock.cycle
		w.events_out.clear()
		if w.run_state.finished:
			break
	t.check_eq(arrived_cycle, Balance.CYCLES_PER_RUN, "судно приходит в 12-м цикле")
	t.check(not w.run_state.score_snapshot.is_empty(),
		"очки сняты в момент прибытия, а не в конце Высокой воды")

## Гибель всех — немедленный конец с 30% очков.
static func test_wipe_ends_run(t: TestCtx) -> void:
	var w: SimWorld = _world(13)
	t.run_ticks(w, 100)
	for a: SimAgent in w.agents.agents:
		w.agents.kill(a, "test", w)
	w.tick()
	var report: Dictionary = {}
	for e: SimEvent in w.events_out:
		if e.type == "run_ended":
			report = e.data["report"] as Dictionary
	t.check(not report.is_empty(), "забег кончился сразу")
	t.check_eq(int(report["end"]), int(SimTypes.RunEnd.WIPE), "исход — гибель всех")
	t.check(int(report["score"]) <= int(report["raw_score"]),
		"очки урезаны до 30%")
	t.check_eq((report["deaths"] as Array).size(), Balance.START_AGENTS,
		"все шестеро записаны в Журнал с причиной")

static func test_surrender(t: TestCtx) -> void:
	var w: SimWorld = _world(17)
	t.run_ticks(w, 100)
	w.apply_command({"kind": "surrender"})
	w.tick()
	t.check(w.run_state.finished, "сдача заканчивает забег немедленно")
	t.check_eq(int(w.run_state.end_kind), int(SimTypes.RunEnd.WIPE),
		"и засчитывается как гибель")

# --- Досрочный уход -------------------------------------------------------

static func test_leave_early_only_from_cycle_eight(t: TestCtx) -> void:
	var w: SimWorld = _world(19)
	_until_cycle(t, w, 7)
	t.check(not w.run_state.leave_early(w), "на 7-м цикле уйти нельзя")
	_until_cycle(t, w, 8)
	t.check(w.run_state.leave_early(w), "с 8-го — можно")
	t.check_eq(w.run_state.ship_cycle, 9, "судно приходит на следующий цикл")
	t.check(not w.run_state.leave_early(w), "повторно — нет")

static func test_leave_early_cuts_score(t: TestCtx) -> void:
	var w: SimWorld = _world(23)
	_until_cycle(t, w, 8)
	w.apply_command({"kind": "leave_early"})
	var report: Dictionary = _run_to_end(t, w)
	t.check(not report.is_empty(), "забег завершился досрочно")
	t.check(bool(report["early"]), "отмечен как досрочный уход")
	t.check(int(report["cycles"]) < Balance.CYCLES_PER_RUN, "и раньше 12-го цикла")
	var expected: int = int(float(int(report["raw_score"])) * Balance.SCORE_MULT_EARLY)
	t.check_eq(int(report["score"]), expected, "очки урезаны на четверть")

## TEST-02 · момент снимка очков (SIM-01). Раньше снимок делался в
## on_phase_started(HIGH), когда вода ещё стояла на уровне Сигнала (−6):
## затоплены были только −7 и −8, и «финальное испытание сизигии» из
## docs/00 §11.2 не срабатывало никогда. Проверяем сам МОМЕНТ, а не формулу.
static func test_score_snapshot_taken_at_high_peak(t: TestCtx) -> void:
	var w: SimWorld = _world(4242)
	# Склад на +1: в сизигию 12-го цикла он обязан оказаться под водой.
	var high_id: int = w.buildings.place("storage",
		Vector2i(10, Balance.mark_to_floor_cell_y(1) - 2), w, true)
	t.check(high_id > 0, "склад на +1 стоит")
	var sid: int = w.storage.storage_at(BuildingSystem.storage_cell(
		w.buildings.buildings[high_id]))
	w.storage.store(sid, StackUtil.make("relic", 1, false))

	var level_at_arrival: float = NAN
	var plateau_at_arrival: float = NAN
	var tick_at_arrival: int = -1
	var peak_at_arrival: int = -1
	var phase_at_arrival: int = -1
	var cycle_at_arrival: int = -1
	for i: int in Balance.TICKS_PER_CYCLE * 20:
		w.tick()
		for e: SimEvent in w.events_out:
			if e.type != "ship_arrived":
				continue
			level_at_arrival = w.tide.level
			plateau_at_arrival = w.tide.high_plateau
			tick_at_arrival = int(w.clock.tick_in_phase)
			peak_at_arrival = w.clock.high_peak_tick()
			phase_at_arrival = int(w.clock.phase)
			cycle_at_arrival = int(w.clock.cycle)
		w.events_out.clear()
		if w.run_state.finished:
			break
	t.check(not is_nan(level_at_arrival), "судно пришло")
	t.check_eq(cycle_at_arrival, Balance.CYCLES_PER_RUN, "в 12-м цикле")
	t.check_eq(phase_at_arrival, int(SimTypes.Phase.HIGH), "на Высокой воде")
	t.check_eq(tick_at_arrival, peak_at_arrival, "и ровно на её пике")
	t.check_approx(level_at_arrival, plateau_at_arrival, 0.01,
		"вода уже на плато, а не на уровне Сигнала")
	t.check_approx(level_at_arrival, Balance.HIGH_LEVEL + Balance.SPRING_BONUS, 0.01,
		"плато 12-го цикла — сизигийное +2")
	# Главное следствие момента (docs/00 §11.2): склад на +1 в этот тик
	# под водой и в очки не идёт, а поднятое на +3 спасено.
	t.check(Balance.is_mark_flooded(1, level_at_arrival),
		"склад на +1 в момент снимка под водой")
	t.check(not Balance.is_mark_flooded(3, level_at_arrival),
		"а поднятое на +3 спасено")

# --- Очки -----------------------------------------------------------------

## Затопленный в момент судна склад не даёт очков — это спроектированное
## финальное испытание 12-го цикла (сизигия), а не потеря данных.
static func test_flooded_storage_scores_nothing(t: TestCtx) -> void:
	var w: SimWorld = _world(29)
	var low: int = w.buildings.place("storage",
		Vector2i(20, Balance.mark_to_floor_cell_y(-2) - 2), w, true)
	t.check(low > 0, "склад на −2 стоит")
	var sid: int = w.storage.storage_at(BuildingSystem.storage_cell(
		w.buildings.buildings[low]))
	w.storage.store(sid, StackUtil.make("ingot", 5, false))

	w.tide.level_override = -8.0
	t.run_ticks(w, 2)
	var dry: Dictionary = w.run_state.compute_score(w)
	w.tide.level_override = 0.0
	t.run_ticks(w, 2)
	var wet: Dictionary = w.run_state.compute_score(w)
	t.check(int(dry["cargo"]) > int(wet["cargo"]),
		"под водой груз не считается (%d → %d)" % [int(dry["cargo"]), int(wet["cargo"])])

static func test_score_counts_survivors_and_relics(t: TestCtx) -> void:
	var w: SimWorld = _world(31)
	w.tide.level_override = -8.0
	t.run_ticks(w, 2)
	var base: Dictionary = w.run_state.compute_score(w)
	t.check_eq(int(base["survivors"]),
		w.agents.alive_count() * Balance.POINTS_PER_SURVIVOR,
		"по 5 очков за живого")
	w.storage.store(0, StackUtil.make("relic", 2, false))
	var with_relics: Dictionary = w.run_state.compute_score(w)
	t.check_eq(int(with_relics["relics"]), 2 * Balance.POINTS_PER_RELIC_BONUS,
		"реликвия даёт 10 сверх своих очков предмета")
	t.check_eq(int(with_relics["cargo"]) - int(base["cargo"]),
		2 * DB.item("relic").ship_points, "и свои 10 очков груза тоже")

# --- Разблокировки --------------------------------------------------------

static func test_unlocks_gate_content(t: TestCtx) -> void:
	var locked: SimWorld = _world(37)
	t.check_eq(locked.buildings.place_error("winch",
		Vector2i(13, Balance.mark_to_floor_cell_y(0) - 2), locked), "ERR_LOCKED",
		"лебёдка заперта без разблокировки")
	var open_w: SimWorld = _world(37, ["u_winch"])
	t.check_eq(open_w.buildings.place_error("winch",
		Vector2i(13, Balance.mark_to_floor_cell_y(0) - 2), open_w), "",
		"с разблокировкой ставится")

static func test_start_bonuses(t: TestCtx) -> void:
	var plain: SimWorld = _world(41)
	var stocked: SimWorld = _world(41, ["u_start_stock"])
	t.check_eq(int(stocked.storage.totals().get("driftwood", 0))
		- int(plain.storage.totals().get("driftwood", 0)),
		Balance.START_STOCK_BONUS, "«Старт: запас» добавляет 6 плавника")
	var smithy: SimWorld = _world(41, ["u_start_smith"])
	t.check_eq(smithy.agents.agents.size(), Balance.START_AGENTS + 1,
		"«Старт: кузнец» даёт седьмого агента")
	var has_smith: bool = false
	for a: SimAgent in smithy.agents.agents:
		if a.has_trait("smith"):
			has_smith = true
	t.check(has_smith, "и он действительно Кузнец")

static func test_hearth_radius_upgrade(t: TestCtx) -> void:
	var plain: SimWorld = _world(43)
	t.check_eq(plain.heat_radius(), Balance.HEAT_RADIUS, "обычный очаг греет на 4")
	var big: SimWorld = _world(43, [Balance.UNLOCK_HEARTH_BIG])
	t.check_eq(big.heat_radius(), Balance.HEAT_RADIUS_BIG, "с разблокировкой — на 6")

static func test_all_unlocks_present(t: TestCtx) -> void:
	t.check_eq(DB.unlock_ids().size(), 12, "все 12 разблокировок docs/00 §11.3")
	var total: int = 0
	for id: String in DB.unlock_ids():
		var u: UnlockDef = DB.unlock(id)
		t.check(u.cost > 0, "у разблокировки %s есть цена" % id)
		t.check(not u.grants.is_empty(), "и она что-то открывает" )
		total += u.cost
	t.check_eq(total, 30 + 40 + 50 + 40 + 30 + 25 + 60 + 20 + 50 + 50 + 40 + 80,
		"суммарная цена совпадает с таблицей")

## Разблокировки ссылаются на реально существующие постройки, карты и рецепты.
static func test_unlock_references(t: TestCtx) -> void:
	for id: String in DB.unlock_ids():
		var g: Dictionary = DB.unlock(id).grants
		if g.has("building"):
			t.check(DB.has_building(str(g["building"])),
				"%s: нет постройки '%s'" % [id, str(g["building"])])
		if g.has("card"):
			t.check(DB.has_card(str(g["card"])), "%s: нет карты '%s'" % [id, str(g["card"])])
		if g.has("recipe"):
			t.check(DB.has_recipe(str(g["recipe"])),
				"%s: нет рецепта '%s'" % [id, str(g["recipe"])])

# --- Файл сейва -----------------------------------------------------------

## Четыре ловушки JSON разом: типы после parse, точность float, NAN и
## атомарность записи.
static func test_save_file_round_trip(t: TestCtx) -> void:
	var w: SimWorld = _world(777)
	t.run_ticks(w, Balance.TICKS_PER_CYCLE * 4 + 500)
	var data: Dictionary = {"save_version": 1, "seed": w.rng.seed_value,
		"world": w.to_dict(), "ui": {"shown_banners": ["storm"]}}
	t.check_eq(SaveIO.write_json(TEST_PATH, data), OK, "файл записан")
	var back: Dictionary = SaveIO.read_json(TEST_PATH)
	t.check(not back.is_empty(), "и прочитан обратно")
	t.check_eq(int(back["save_version"]), 1, "версия на месте")
	t.check_eq((back["ui"] as Dictionary)["shown_banners"], ["storm"],
		"секция интерфейса сохранена")

	var restored: SimWorld = SimWorld.new()
	restored.from_dict(back["world"] as Dictionary, _cliff())
	t.check_eq(JSON.stringify(restored.to_dict(), "", true, true),
		JSON.stringify(w.to_dict(), "", true, true), "состояние идентично")
	# И, главное, продолжается так же, как непрерывный прогон.
	for i: int in Balance.TICKS_PER_CYCLE * 2:
		t.run_ticks(w, 1)
		t.run_ticks(restored, 1)
	t.check_eq(TestCtx.state_hash(w), TestCtx.state_hash(restored),
		"через два цикла после загрузки состояния совпадают")

## NAN и INF в JSON превращаются в null: в состоянии их быть не должно.
static func test_no_non_finite_numbers(t: TestCtx) -> void:
	var w: SimWorld = _world(53)
	t.run_ticks(w, Balance.TICKS_PER_CYCLE * 2)
	var bad: Array[String] = SaveIO.find_non_finite(w.to_dict())
	t.check_eq(bad, [] as Array[String],
		"не-финитных чисел в сейве нет: %s" % str(bad))

static func test_broken_save_is_quarantined(t: TestCtx) -> void:
	var f: FileAccess = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	t.check(f != null, "тестовый файл открылся")
	if f == null:
		return
	f.store_string("{ это не json")
	f.close()
	var d: Dictionary = SaveIO.read_json(TEST_PATH)
	t.check(d.is_empty(), "битый сейв не грузится")
	t.check(not FileAccess.file_exists(TEST_PATH),
		"и уводится в карантин, а не удаляется молча")
	# Карантинный файл нужен для баг-репорта — он обязан остаться.
	t.check(FileAccess.file_exists(TEST_PATH.get_basename() + ".corrupt.json"),
		"карантинная копия на месте")

static func test_profile_round_trip(t: TestCtx) -> void:
	var profile: Dictionary = {
		"version": 1, "points_total": 120, "unlocked": ["u_winch", "u_card_ebb"],
		"relics_total": 3, "runs_played": 4, "runs_won": 1, "cycles_total": 33,
		"agents_lost": 7, "best_score": 88,
		"history": [{"n": 1, "score": 40, "end": 1, "cycles": 6, "deaths": []}],
	}
	t.check_eq(SaveIO.write_json(TEST_PATH, profile), OK, "профиль записан")
	var back: Dictionary = SaveIO.read_json(TEST_PATH)
	# JSON отдаёт все числа как float: без явного int() профиль «поплывёт».
	t.check_eq(int(back["points_total"]), 120, "очки целые после чтения")
	t.check_eq(typeof(int(back["runs_played"])), TYPE_INT, "и тип целый")
	t.check_eq((back["unlocked"] as Array).size(), 2, "разблокировки на месте")
