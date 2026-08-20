extends RefCounted
## Приёмка этапа 05: движение по графу, утопление, потребности, отзыв,
## пополнение колонии, детерминизм.

const CLIFF: String = "res://data/cliffs/cliff_01.tres"

static func _cliff() -> CliffDef:
	return load(CLIFF) as CliffDef

static func _world(seed_value: int) -> SimWorld:
	var w: SimWorld = SimWorld.new()
	w.new_run(seed_value, _cliff())
	w.events_out.clear()
	return w

## Ставит агента в конкретную клетку — тестам нужна воспроизводимая мизансцена.
static func _place(w: SimWorld, a: SimAgent, cell: Vector2i) -> void:
	a.platform_id = w.terrain.platform_at(cell)
	a.x = float(cell.x)
	a.target_x = a.x
	a.climb_to = -1
	a.climb_t = 0.0
	a.path.clear()
	a.path_graph_version = -1

# --- Спавн ----------------------------------------------------------------

static func test_spawn(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	t.check_eq(w.agents.agents.size(), Balance.START_AGENTS, "на старте 6 агентов")
	for a: SimAgent in w.agents.agents:
		t.check(not a.agent_name.is_empty(), "у агента есть имя")
		t.check(AgentPools.BIO_KEYS.has(a.bio_key), "биография из пула")
		t.check_eq(a.trait_ids.size(), 2, "ровно две черты")
		t.check(a.trait_ids[0] != a.trait_ids[1], "черты разные")
		for tid: String in a.trait_ids:
			t.check(DB.has_trait(tid), "черта '%s' существует" % tid)
		t.check_approx(a.satiety(), 100.0, 0.1, "сытость на старте полная")

## Свёртка модификаторов: множители перемножаются, а drown_seconds ЗАМЕНЯЕТ
## базу — Ныряльщик держится 10 секунд, а не в 10 раз дольше.
static func test_trait_folding(t: TestCtx) -> void:
	var a: SimAgent = SimAgent.new()
	a.init_needs()
	a.trait_ids = ["diver"]
	a.recompute_from_traits()
	t.check_eq(a.drown_limit_ticks, int(10.0 * Balance.TICKS_PER_SEC),
		"Ныряльщик тонет за 10 с, а не за 50")
	a.trait_ids = ["glutton"]
	a.recompute_from_traits()
	t.check_eq(a.hunger_rate_milli, 24_000, "Прожорливый теряет 24 сытости за цикл")
	a.trait_ids = ["sinew"]
	a.recompute_from_traits()
	t.check_eq(a.bag_slots, Balance.BAG_SLOTS + 1, "Жила даёт лишний слот котомки")
	a.trait_ids = ["hardy", "chilly"]
	a.recompute_from_traits()
	# 0.6 × 1.4 = 0.84 — множители складываются мультипликативно.
	t.check_eq(a.warmth_rate_milli, 8_400, "две черты тепла перемножаются")

# --- Движение -------------------------------------------------------------

## Расчётное время: 8 ярусов по 3 тайла лестницы (1.2 т/с) + горизонталь
## по площадкам (2.0 т/с). Допуск ±10% по приёмке.
static func test_walks_from_bottom_to_top(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	# Достраиваем спуск до −8, иначе пути просто нет (см. test_terrain).
	_build_ladders_down_to(w, -8)
	# Вода не должна мешать: тест про дорогу, а не про утопление.
	w.tide.level_override = -12.0

	var a: SimAgent = w.agents.agents[0]
	var bottom: Vector2i = Vector2i(40, Balance.mark_to_floor_cell_y(-8))
	_place(w, a, bottom)
	var top_mark: int = Balance.TOP_MARK
	var span_top: Array[int] = w.terrain.platform_x_range(top_mark)
	var goal: Vector2i = Vector2i(span_top[0] + 2, Balance.mark_to_floor_cell_y(top_mark))
	a.goto_platform = w.terrain.platform_at(goal)
	a.goto_x = float(goal.x)
	a.intent = SimTypes.AgentState.IDLE
	a.state = SimTypes.AgentState.GOTO
	a.path_graph_version = -1

	var ticks: int = 0
	while ticks < 20000 and a.platform_id != w.terrain.platform_of_mark(top_mark):
		t.run_ticks(w, 1)
		ticks += 1
	t.check(a.platform_id == w.terrain.platform_of_mark(top_mark),
		"агент поднялся с −8 на +6 (за %d тиков)" % ticks)
	# 14 переходов между ярусами × 3 тайла / 1.2 т/с = 35 с = 350 тиков на лазанье.
	var climb_ticks: float = 14.0 * float(Balance.TILES_PER_MARK) \
		/ Balance.LADDER_SPEED * float(Balance.TICKS_PER_SEC)
	t.check(float(ticks) > climb_ticks * 0.9,
		"быстрее физического минимума подъёма не получилось (%d)" % ticks)
	t.check(float(ticks) < climb_ticks * 6.0,
		"и не заблудился по дороге (%d тиков)" % ticks)

static func test_path_survives_broken_ladder(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var a: SimAgent = w.agents.agents[0]
	_place(w, a, Vector2i(4, Balance.mark_to_floor_cell_y(6)))
	a.goto_platform = w.terrain.platform_of_mark(0)
	a.goto_x = 4.0
	a.intent = SimTypes.AgentState.IDLE
	a.state = SimTypes.AgentState.GOTO
	t.run_ticks(w, 30)
	var gv: int = w.terrain.graph_version
	w.terrain.add_ladder(Vector2i(8, Balance.mark_to_floor_cell_y(5)))
	t.check(w.terrain.graph_version > gv, "граф изменился")
	# Больше одного подъёма по лестнице: пока агент на ней, путь намеренно
	# не пересчитывается — бросать лестницу на полпути нельзя.
	t.run_ticks(w, 40)
	t.check_eq(a.path_graph_version, w.terrain.graph_version,
		"агент пересчитал путь после изменения графа")

# --- Утопление ------------------------------------------------------------

static func test_drowning(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var a: SimAgent = w.agents.agents[0]
	_place(w, a, Vector2i(40, Balance.mark_to_floor_cell_y(-8)))
	w.tide.level_override = 0.0                 # накрыло с головой
	var warned: int = 0
	var ticks: int = 0
	while a.is_alive() and ticks < 200:
		w.tick()
		for e: SimEvent in w.events_out:
			if e.type == "agent_drowning" and int(e.data["id"]) == a.id:
				warned += 1
		w.events_out.clear()
		ticks += 1
	t.check(not a.is_alive(), "агент утонул")
	t.check_eq(ticks, int(Balance.DROWN_SEC * Balance.TICKS_PER_SEC), "ровно 5 секунд")
	# Предупреждение — ровно одно, а не каждый тик последних двух секунд.
	t.check_eq(warned, 1, "agent_drowning пришло один раз")

static func test_gear_extends_drowning(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var a: SimAgent = w.agents.agents[0]
	a.has_gear = true
	a.trait_ids = []                            # чтобы Ныряльщик не мешал счёту
	a.recompute_from_traits()
	_place(w, a, Vector2i(40, Balance.mark_to_floor_cell_y(-8)))
	w.tide.level_override = 0.0
	var ticks: int = 0
	while a.is_alive() and ticks < 400:
		t.run_ticks(w, 1)
		ticks += 1
	t.check_eq(ticks, int(Balance.DROWN_GEAR_SEC * Balance.TICKS_PER_SEC),
		"со снаряжением 20 секунд")

static func test_submersion_counter_resets(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var a: SimAgent = w.agents.agents[0]
	_place(w, a, Vector2i(40, Balance.mark_to_floor_cell_y(-8)))
	w.tide.level_override = 0.0
	t.run_ticks(w, 30)
	t.check(a.submerged_ticks >= 30, "счётчик погружения идёт")
	w.tide.level_override = -12.0               # вода ушла
	t.run_ticks(w, 2)
	t.check_eq(a.submerged_ticks, 0, "вышел из воды — счётчик сброшен")
	t.check(a.is_alive(), "и остался жив")

static func test_death_hits_everyones_mood(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var victim: SimAgent = w.agents.agents[0]
	var witness: SimAgent = w.agents.agents[1]
	var before: float = witness.mood()
	_place(w, victim, Vector2i(40, Balance.mark_to_floor_cell_y(-8)))
	w.tide.level_override = 0.0
	t.run_ticks(w, 60)
	t.check(not victim.is_alive(), "агент погиб")
	t.check_approx(witness.mood(), before - 25.0, 1.0, "дух остальных упал на 25")

# --- Потребности ----------------------------------------------------------

static func test_hunger_drains_per_cycle(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var a: SimAgent = w.agents.agents[0]
	a.trait_ids = []
	a.recompute_from_traits()
	# Убираем еду, иначе агент уйдёт есть и sat подскочит.
	w.storage.storages.clear()
	var before: float = a.satiety()
	t.run_ticks(w, Balance.TICKS_PER_CYCLE)
	t.check_approx(a.satiety(), before - 18.0, 0.2, "сытость −18 за цикл")

static func test_hungry_agent_eats(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var a: SimAgent = w.agents.agents[0]
	a.needs["satiety"] = 20_000
	var before_rations: int = w.storage.count_in(0, "rations")
	var ticks: int = 0
	while a.satiety() < 60.0 and ticks < 3000:
		t.run_ticks(w, 1)
		ticks += 1
	t.check(a.satiety() >= 60.0, "голодный дошёл до склада и поел (%d тиков)" % ticks)
	t.check(w.storage.count_in(0, "rations") < before_rations, "провизия израсходована")

## Без гистерезиса агент вибрировал бы у порога каждый тик.
static func test_needs_do_not_flicker(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var a: SimAgent = w.agents.agents[0]
	a.needs["satiety"] = Balance.NEED_LOW_ENTER_MILLI + 200
	var switches: int = 0
	var prev: SimTypes.AgentState = a.state
	for i: int in 3000:
		t.run_ticks(w, 1)
		if a.state != prev:
			switches += 1
			prev = a.state
	t.check(switches < 30, "смен состояния единицы, а не сотни (было %d)" % switches)

static func test_warmth_at_heat_source(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var a: SimAgent = w.agents.agents[0]
	a.trait_ids = []
	a.recompute_from_traits()
	a.wet = true
	a.needs["warmth"] = 40_000
	# Заглушка источника тепла ровно там, где стоит агент (TODO этапа 07).
	w.debug_heat_sources = [w.agents.agent_cell(a, w)]
	var before: float = a.warmth()
	t.run_ticks(w, Balance.TICKS_PER_CYCLE)
	# Мокрый теряет 25, у очага получает 30 — итог +5 за цикл.
	t.check(a.warmth() > before, "мокрый у очага отогревается (%.1f → %.1f)"
		% [before, a.warmth()])
	t.check(not a.wet, "и обсох за 30 секунд у очага")

static func test_warmth_drains_without_heat(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var a: SimAgent = w.agents.agents[0]
	a.trait_ids = []
	a.recompute_from_traits()
	# Вода убрана: тест про тепло, а не про утопление. Площадка −1 целиком
	# дальше радиуса тепла от «костра лагеря» на клетке спавна.
	w.tide.level_override = -12.0
	_place(w, a, Vector2i(20, Balance.mark_to_floor_cell_y(-1)))
	a.goto_platform = a.platform_id
	a.goto_x = a.x
	var before: float = a.warmth()
	t.run_ticks(w, Balance.TICKS_PER_CYCLE)
	t.check_approx(a.warmth(), before - 10.0, 0.5, "вдали от очага тепло −10 за цикл")

# --- Отзыв ----------------------------------------------------------------

## Сценарий приёмки: агенты на −4 (спуск туда игрок уже построил), Отзыв
## даётся в начале Сигнала — к началу Высокой воды все обязаны быть выше нуля.
static func test_recall_moves_everyone_up(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	_build_ladders_down_to(w, -4)
	t.run_ticks(w, 450 + 1500)                  # дошли до Сигнала, дно осушено
	for a: SimAgent in w.agents.agents:
		_place(w, a, Vector2i(30, Balance.mark_to_floor_cell_y(-4)))
	w.apply_command({"kind": "recall", "hard": false})
	w.tick()
	for a2: SimAgent in w.agents.agents:
		t.check_eq(int(a2.state), int(SimTypes.AgentState.RETURN), "все в RETURN")
	t.run_ticks(w, 300)                         # весь Сигнал
	for a3: SimAgent in w.agents.agents:
		t.check(w.agents.agent_mark_f(a3, w) >= 0.0,
			"к началу HIGH никто не остался ниже нуля (%s на %.1f)"
			% [a3.agent_name, w.agents.agent_mark_f(a3, w)])

## Достраивает спуск, которого на старте нет (стартовая лестница кончается на −2).
static func _build_ladders_down_to(w: SimWorld, bottom: int) -> void:
	for mark: int in range(-2, bottom - 1, -1):
		var span: Array[int] = w.terrain.platform_x_range(mark)
		var below: Array[int] = w.terrain.platform_x_range(mark - 1)
		if span.is_empty() or below.is_empty():
			continue
		w.terrain.add_ladder(Vector2i(maxi(span[0], below[0]),
			Balance.mark_to_floor_cell_y(mark)))

static func test_hard_recall_drops_cargo(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var a: SimAgent = w.agents.agents[0]
	var cell: Vector2i = Vector2i(20, Balance.mark_to_floor_cell_y(-2))
	_place(w, a, cell)
	a.bag.append(StackUtil.make("scrap", 3, false))
	w.apply_command({"kind": "recall", "hard": true})
	w.tick()
	t.check_eq(a.bag.size(), 0, "жёсткий отзыв освободил котомку")
	t.check_eq(w.storage.ground_at(cell).size(), 1, "груз лежит там, где бросили")

# --- События --------------------------------------------------------------

## agent_updated не чаще раза в секунду на агента (иначе UI захлебнётся).
static func test_agent_updated_throttled(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var counts: Dictionary[int, int] = {}
	# Отзыв гарантирует поток смен состояния — иначе бродящие агенты молчат
	# и тест проходит вхолостую.
	w.apply_command({"kind": "recall", "hard": false})
	for i: int in 100:
		w.tick()
		for e: SimEvent in w.events_out:
			if e.type == "agent_updated":
				var id: int = int(e.data["id"])
				counts[id] = int(counts.get(id, 0)) + 1
		w.events_out.clear()
	t.check(counts.size() > 0, "события agent_updated вообще идут")
	for id2: int in counts:
		t.check(int(counts[id2]) <= 11,
			"агент %d получил %d апдейтов за 100 тиков" % [id2, int(counts[id2])])

# --- Пополнение колонии ---------------------------------------------------

static func test_newcomer_needs_good_mood(t: TestCtx) -> void:
	var w: SimWorld = _world(5)
	for a: SimAgent in w.agents.agents:
		a.needs["mood"] = 40_000
	var before: int = w.agents.agents.size()
	t.run_ticks(w, Balance.TICKS_PER_CYCLE * 6)
	t.check_eq(w.agents.agents.size(), before, "при духе 40 новички не приходят")

static func test_newcomer_arrives_and_respects_limit(t: TestCtx) -> void:
	var w: SimWorld = _world(5)
	var arrivals: int = 0
	for c: int in 40:
		for a: SimAgent in w.agents.agents:
			if a.is_alive():
				a.needs["mood"] = 90_000        # держим дух высоким весь прогон
		var before: int = w.agents.agents.size()
		t.run_ticks(w, Balance.TICKS_PER_CYCLE)
		if w.agents.agents.size() > before:
			arrivals += 1
	t.check(arrivals > 0, "при высоком духе новички приходят")
	t.check(w.agents.alive_count() <= Balance.MAX_AGENTS,
		"лимит в 12 агентов соблюдён (стало %d)" % w.agents.alive_count())

## Один сид — один и тот же цикл прихода: иначе баг-репорт не воспроизвести.
static func test_newcomer_is_deterministic(t: TestCtx) -> void:
	var cycles_a: Array[int] = _newcomer_cycles(t, 77)
	var cycles_b: Array[int] = _newcomer_cycles(t, 77)
	t.check_eq(cycles_a, cycles_b, "циклы прихода совпадают при одном сиде")
	t.check(not cycles_a.is_empty(), "хотя бы один новичок пришёл")

static func _newcomer_cycles(t: TestCtx, seed_value: int) -> Array[int]:
	var w: SimWorld = _world(seed_value)
	var out: Array[int] = []
	for c: int in 12:
		for a: SimAgent in w.agents.agents:
			if a.is_alive():
				a.needs["mood"] = 90_000
		var before: int = w.agents.agents.size()
		t.run_ticks(w, Balance.TICKS_PER_CYCLE)
		if w.agents.agents.size() > before:
			out.append(w.clock.cycle)
	return out

# --- Детерминизм ----------------------------------------------------------

static func test_determinism_with_agents(t: TestCtx) -> void:
	var a: SimWorld = _world(31337)
	var b: SimWorld = _world(31337)
	for i: int in 20000:
		t.run_ticks(a, 1)
		t.run_ticks(b, 1)
		if i % 2000 == 0 and TestCtx.state_hash(a) != TestCtx.state_hash(b):
			t.check(false, "миры с агентами разошлись на тике %d" % i)
			return
	t.check_eq(TestCtx.state_hash(a), TestCtx.state_hash(b),
		"20 000 тиков с агентами: состояния совпадают")

static func test_agents_survive_save(t: TestCtx) -> void:
	var w: SimWorld = _world(2024)
	t.run_ticks(w, 5000)
	var text: String = JSON.stringify(w.to_dict(), "", true, true)
	var restored: SimWorld = SimWorld.new()
	restored.from_dict(JSON.parse_string(text) as Dictionary, _cliff())
	t.check_eq(JSON.stringify(restored.to_dict(), "", true, true), text,
		"агенты переживают JSON")
	for i: int in 3000:
		t.run_ticks(w, 1)
		t.run_ticks(restored, 1)
	t.check_eq(TestCtx.state_hash(w), TestCtx.state_hash(restored),
		"после загрузки мир с агентами продолжается идентично")
