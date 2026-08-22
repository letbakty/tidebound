extends RefCounted
## Приёмка этапа 06: скоринг, резервирование, политики, маяк, добыча,
## авто-возврат Осторожности, автовыдача Снаряжения.

const CLIFF: String = "res://data/cliffs/cliff_01.tres"

static func _cliff() -> CliffDef:
	return load(CLIFF) as CliffDef

## Мир с достроенным спуском до −8: без лестниц дно недостижимо и добывать
## нечего (стартовая лестница кончается на −2).
static func _world(seed_value: int) -> SimWorld:
	var w: SimWorld = SimWorld.new()
	w.new_run(seed_value, _cliff())
	for mark: int in range(-2, -9, -1):
		var span: Array[int] = w.terrain.platform_x_range(mark)
		var below: Array[int] = w.terrain.platform_x_range(mark - 1)
		if span.is_empty() or below.is_empty():
			continue
		w.terrain.add_ladder(Vector2i(maxi(span[0], below[0]),
			Balance.mark_to_floor_cell_y(mark)))
	w.events_out.clear()
	return w

## Мир без достроенного спуска: ровно то, с чего начинается забег. Нужен
## тестам про лестницы — в _world их уже восемь штук, и любая проверка
## «лестниц нет» на нём бессмысленна.
static func _plain_world(seed_value: int) -> SimWorld:
	var w: SimWorld = SimWorld.new()
	w.new_run(seed_value, _cliff())
	w.events_out.clear()
	return w

static func _totals(w: SimWorld) -> Dictionary:
	return w.storage.totals()

# --- Основной сценарий ----------------------------------------------------

## Главная приёмка этапа: колония сама себя кормит и снабжает.
static func test_colony_gathers_over_a_cycle(t: TestCtx) -> void:
	var w: SimWorld = _world(4242)
	t.run_ticks(w, Balance.TICKS_PER_CYCLE * 2)
	var tot: Dictionary = _totals(w)
	t.check(int(tot.get("scrap", 0)) >= 8 + 4,
		"за два цикла принесли ≥8 утиля сверх стартовых 4 (стало %d)"
		% int(tot.get("scrap", 0)))
	t.check(int(tot.get("catch", 0)) >= 4,
		"и ≥4 сырой добычи (стало %d)" % int(tot.get("catch", 0)))

## Заготовка = 0 — класс запрещён целиком, а не «低ий приоритет».
static func test_supply_zero_stops_gathering(t: TestCtx) -> void:
	var w: SimWorld = _world(7)
	w.policies.set_value(SimTypes.Policy.SUPPLY, 0)
	w.jobs.mark_dirty()
	var before: int = int(_totals(w).get("scrap", 0))
	t.run_ticks(w, Balance.TICKS_PER_CYCLE)
	t.check_eq(int(_totals(w).get("scrap", 0)), before, "при Заготовке 0 добычи нет")
	for a: SimAgent in w.agents.agents:
		t.check(a.state != SimTypes.AgentState.GATHER, "никто не добывает")

# --- Жадность -------------------------------------------------------------

## Жадность — фильтр по расстоянию цели от ближайшей лестницы.
static func test_greed_limits_distance(t: TestCtx) -> void:
	var w: SimWorld = _world(11)
	w.policies.set_value(SimTypes.Policy.GREED, 0)
	w.jobs.mark_dirty()
	var limit: float = float(Balance.GREED_LADDER_LIMIT[0])
	var violations: int = 0
	for i: int in Balance.TICKS_PER_CYCLE:
		t.run_ticks(w, 1)
		for a: SimAgent in w.agents.agents:
			if a.job_id == -1:
				continue
			var j: Dictionary = w.jobs.jobs.get(a.job_id, {})
			if j.is_empty():
				continue
			var cell: Vector2i = j["cell"] as Vector2i
			if Balance.cell_to_mark(cell) >= 0:
				continue
			if w.terrain.nearest_ladder_dist(cell) > limit:
				violations += 1
	t.check_eq(violations, 0, "при Жадности 0 никто не берёт цели дальше 4 тайлов")

## TEST-10 · колония не запирается сама (SIM-07).
##
## Фильтр Жадности отсекал задачи по nearest_ladder_dist. Ремонт лестницы —
## единственный способ вернуть доступ на дно — попадал под тот же фильтр:
## чинить нельзя, потому что нет лестниц, а лестниц нет, потому что не чинят.
## Жадность про риск ДОБЫЧИ, стройки и ремонта она касаться не должна.
static func test_deep_ladder_is_repaired_at_low_greed(t: TestCtx) -> void:
	var w: SimWorld = _plain_world(61)
	w.policies.set_value(SimTypes.Policy.GREED, 0)
	w.policies.set_value(SimTypes.Policy.REPAIR, 3)
	w.storage.store(0, StackUtil.make("driftwood", 10, false))
	# Убираем стартовую лестницу −1 ↔ −2, свою ставим в дальней колонке:
	# иначе ближайшая целая лестница окажется в двух тайлах и лимит не сработает.
	for l: Dictionary in w.terrain.ladders.duplicate():
		if int(l["mark_top"]) == -1:
			w.terrain.remove_ladder(int(l["id"]))
	var cell: Vector2i = Vector2i(22, Balance.mark_to_floor_cell_y(-1))
	var lid: int = w.buildings.place("ladder_wood", cell, w, true)
	t.check(lid > 0, "лестница на дно поставлена")
	var guard: int = 0
	while not bool(w.buildings.buildings[lid]["damaged"]) and guard < 20:
		w.buildings.apply_damage(lid, w)
		guard += 1
	t.check(bool(w.buildings.buildings[lid]["damaged"]), "и сломана")
	t.check(w.terrain.nearest_ladder_dist(cell)
			> float(Balance.GREED_LADDER_LIMIT[0]),
		"ближайшая целая лестница дальше лимита Жадности 0")
	w.jobs.mark_dirty()
	t.check(_repair_taken(t, w, lid), "ремонт взят несмотря на Жадность 0")

## Была ли задача ремонта постройки кем-то взята за цикл.
static func _repair_taken(t: TestCtx, w: SimWorld, building_id: int) -> bool:
	for i: int in Balance.TICKS_PER_CYCLE:
		t.run_ticks(w, 1)
		if not bool(w.buildings.buildings[building_id]["damaged"]):
			return true                      # уже починили
		for id: int in w.jobs.order:
			var j: Dictionary = w.jobs.jobs[id]
			if int(j["class"]) == int(SimTypes.JobClass.REPAIR) \
					and int(j["target_id"]) == building_id \
					and int(j["taken_by"]) != -1:
				return true
	return false

## Лестницу вниз обязаны уметь СТРОИТЬ. Работа у лестницы назначалась на
## нижнюю площадку — ту самую, куда без неё не попасть, — и задача висела
## в пуле вечно: агенты не могли построить ни одной лестницы за забег.
static func test_agents_can_build_ladder_down(t: TestCtx) -> void:
	var w: SimWorld = _plain_world(67)
	w.policies.set_value(SimTypes.Policy.BUILD, 3)
	w.storage.store(0, StackUtil.make("driftwood", 10, false))
	var deep: int = w.terrain.platform_of_mark(-3)
	t.check_eq(w.terrain.find_path(w.terrain.platform_of_mark(6), deep).size(), 0,
		"до −3 пути пока нет")
	var id: int = w.buildings.place("ladder_wood",
		Vector2i(25, Balance.mark_to_floor_cell_y(-2)), w)
	t.check(id > 0, "лестница запланирована")
	var built: bool = false
	for i: int in Balance.TICKS_PER_CYCLE * 2:
		t.run_ticks(w, 1)
		if not w.buildings.buildings.has(id):
			break
		if int(w.buildings.buildings[id]["state"]) == int(SimTypes.BuildState.ACTIVE):
			built = true
			break
	t.check(built, "агенты сами достроили лестницу вниз")
	t.check(w.terrain.find_path(w.terrain.platform_of_mark(6), deep).size() > 0,
		"и путь на −3 открылся")

static func test_greed_three_allows_far_targets(t: TestCtx) -> void:
	var far: Vector2i = Vector2i(46, Balance.mark_to_floor_cell_y(-8))
	t.check(_far_job_taken(t, 3, far), "при Жадности 3 дальние цели берут")
	t.check(not _far_job_taken(t, 0, far), "при Жадности 0 — нет")

## Берёт ли кто-нибудь задачу дальше лимита Жадности 0 за цикл.
static func _far_job_taken(t: TestCtx, greed: int, far_cell: Vector2i) -> bool:
	var w: SimWorld = _world(11)
	w.policies.set_value(SimTypes.Policy.GREED, greed)
	w.policies.set_value(SimTypes.Policy.CAUTION, 0)    # чтобы не отзывали
	w.jobs.mark_dirty()
	var limit: float = float(Balance.GREED_LADDER_LIMIT[0])
	for i: int in Balance.TICKS_PER_CYCLE:
		t.run_ticks(w, 1)
		for a: SimAgent in w.agents.agents:
			if a.job_id == -1:
				continue
			var j: Dictionary = w.jobs.jobs.get(a.job_id, {})
			if j.is_empty():
				continue
			var cell: Vector2i = j["cell"] as Vector2i
			if Balance.cell_to_mark(cell) < 0 \
					and w.terrain.nearest_ladder_dist(cell) > limit:
				return true
	return false

# --- Осторожность ---------------------------------------------------------

static func test_caution_three_brings_everyone_up(t: TestCtx) -> void:
	var w: SimWorld = _world(21)
	w.policies.set_value(SimTypes.Policy.CAUTION, 3)
	w.policies.set_value(SimTypes.Policy.GREED, 3)
	w.jobs.mark_dirty()
	t.run_ticks(w, Balance.TICKS_PER_CYCLE)           # ровно до начала HIGH цикла 2
	t.run_ticks(w, 450 + 1500 + 300)
	for a: SimAgent in w.agents.agents:
		if not a.is_alive():
			continue
		t.check(w.agents.agent_mark_f(a, w) >= -1.0,
			"при Осторожности 3 к началу HIGH никто не ниже −1 (%s на %.1f)"
			% [a.agent_name, w.agents.agent_mark_f(a, w)])

## Обратная сторона: Осторожность 0 + Жадность 3 = кто-то реально мокнет.
static func test_reckless_policies_get_agents_wet(t: TestCtx) -> void:
	var w: SimWorld = _world(21)
	w.policies.set_value(SimTypes.Policy.CAUTION, 0)
	w.policies.set_value(SimTypes.Policy.GREED, 3)
	w.jobs.mark_dirty()
	var risked: bool = false
	for i: int in Balance.TICKS_PER_CYCLE * 2:
		t.run_ticks(w, 1)
		for a: SimAgent in w.agents.agents:
			if a.submerged_ticks > 0:
				risked = true
		if risked:
			break
	t.check(risked, "без Осторожности кто-то оказывается в воде")

# --- Отдых ----------------------------------------------------------------

static func test_rest_policy_on_high(t: TestCtx) -> void:
	var w: SimWorld = _world(31)
	w.policies.set_value(SimTypes.Policy.REST, 3)
	w.policies.set_value(SimTypes.Policy.SUPPLY, 0)
	w.jobs.mark_dirty()
	for a: SimAgent in w.agents.agents:
		a.needs["fatigue"] = 20_000
		a.needs["satiety"] = 20_000
	# Ждём фазу, а не считаем тики: карта цикла меняет длину отлива.
	var guard: int = 0
	while w.clock.phase != SimTypes.Phase.HIGH and guard < Balance.TICKS_PER_CYCLE * 2:
		t.run_ticks(w, 1)
		guard += 1
	t.run_ticks(w, 400)                               # середина Высокой воды
	t.check_eq(int(w.clock.phase), int(SimTypes.Phase.HIGH), "мы на Высокой воде")
	var busy: int = 0
	for a2: SimAgent in w.agents.agents:
		if a2.state == SimTypes.AgentState.REST or a2.state == SimTypes.AgentState.EAT \
				or a2.state == SimTypes.AgentState.GOTO:
			busy += 1
	t.check(busy >= 4, "при Отдыхе 3 на HIGH колония ест и отдыхает (%d из 6)" % busy)

# --- Маяк -----------------------------------------------------------------

## Маяк смещает выбор между равноценными целями. Радиус евклидов — игрок
## видит круг и ждёт, что бонус внутри круга.
static func test_beacon_shifts_choice(t: TestCtx) -> void:
	var w: SimWorld = _world(41)
	var a: SimAgent = w.agents.agents[0]
	# Цели заведомо дальше радиуса маяка друг от друга (12 тайлов по прямой),
	# иначе обе окажутся в круге и тест ничего не проверит.
	var near_cell: Vector2i = Vector2i(24, Balance.mark_to_floor_cell_y(-3))
	var far_cell: Vector2i = Vector2i(46, Balance.mark_to_floor_cell_y(-8))
	var j_near: Dictionary = _fake_job(w, near_cell)
	var j_far: Dictionary = _fake_job(w, far_cell)
	var base_near: int = w.jobs.score(a, j_near, w)
	var base_far: int = w.jobs.score(a, j_far, w)

	w.jobs.beacon_cell = far_cell
	t.check_eq(w.jobs.score(a, j_near, w), base_near, "цель вне круга бонуса не получила")
	t.check(w.jobs.score(a, j_far, w) > base_far, "цель у маяка получила бонус")
	t.check_approx(float(w.jobs.score(a, j_far, w)) / float(base_far),
		Balance.BEACON_BONUS, 0.02, "бонус ровно ×1.3")

static func _fake_job(w: SimWorld, cell: Vector2i) -> Dictionary:
	return {
		"id": 0, "class": SimTypes.JobClass.GATHER, "kind": "gather",
		"cell": cell, "platform": w.terrain.platform_at(cell),
		"base": float(Balance.JOB_BASE[SimTypes.JobClass.GATHER]),
		"taken_by": -1, "item_id": "scrap", "n": 0, "target_id": -1,
		"to_cell": cell, "to_id": -1,
	}

# --- Резервирование -------------------------------------------------------

## Двусторонняя связь job.taken_by ⟺ agent.job_id обязана держаться всегда:
## её разрыв — это либо шесть агентов на одной куче, либо зависший агент.
static func test_reservation_invariant_holds(t: TestCtx) -> void:
	var w: SimWorld = _world(51)
	var bad: int = 0
	for i: int in 6000:
		t.run_ticks(w, 1)
		if i % 100 != 0:
			continue
		for id: int in w.jobs.order:
			var owner: int = int(w.jobs.jobs[id]["taken_by"])
			if owner == -1:
				continue
			var a: SimAgent = w.agents.agent(owner)
			if a == null or a.job_id != id:
				bad += 1
		for a2: SimAgent in w.agents.agents:
			if a2.job_id == -1:
				continue
			var j: Dictionary = w.jobs.jobs.get(a2.job_id, {})
			if j.is_empty() or int(j["taken_by"]) != a2.id:
				bad += 1
	t.check_eq(bad, 0, "резервация не рассинхронизировалась ни разу за 6000 тиков")

static func test_dead_agent_frees_its_job(t: TestCtx) -> void:
	var w: SimWorld = _world(61)
	t.run_ticks(w, 600)
	var victim: SimAgent = null
	for a: SimAgent in w.agents.agents:
		if a.job_id != -1:
			victim = a
			break
	t.check(victim != null, "кто-то взял задачу")
	if victim == null:
		return
	var job_id: int = victim.job_id
	w.agents._kill(victim, "test", w)
	t.check_eq(victim.job_id, -1, "у погибшего задачи нет")
	var j: Dictionary = w.jobs.jobs.get(job_id, {})
	t.check(j.is_empty() or int(j["taken_by"]) == -1, "задача освободилась")

## Один агент — максимум одна задача.
static func test_one_job_per_agent(t: TestCtx) -> void:
	var w: SimWorld = _world(71)
	for i: int in 2000:
		t.run_ticks(w, 1)
		var owners: Dictionary[int, int] = {}
		for id: int in w.jobs.order:
			var owner: int = int(w.jobs.jobs[id]["taken_by"])
			if owner == -1:
				continue
			t.check(not owners.has(owner), "агент %d держит две задачи" % owner)
			owners[owner] = id
			if owners.size() > 20:
				return
	t.check(true, "двойных назначений нет")

# --- Реликвия и снаряжение ------------------------------------------------

## Реликвия выпадает только в глубоких руинах и только один раз с депозита.
static func test_relic_only_once_per_deposit(t: TestCtx) -> void:
	var w: SimWorld = _world(81)
	var a: SimAgent = w.agents.agents[0]
	var di: int = -1
	for i: int in w.terrain.deposits.size():
		var d: Dictionary = w.terrain.deposits[i]
		if str(d["kind"]) == "ruins_deep" \
				and Balance.cell_to_mark(d["cell"] as Vector2i) <= Balance.RELIC_MARK_MAX:
			di = i
			break
	t.check(di >= 0, "глубокие руины на −7/−8 есть")
	if di < 0:
		return
	var dep: Dictionary = w.terrain.deposits[di]
	var mark: int = Balance.cell_to_mark(dep["cell"] as Vector2i)
	var relics: int = 0
	for i2: int in 200:
		a.bag.clear()
		w.agents._roll_relic(a, dep, mark, w)
		relics += a.bag_count("relic")
	t.check_eq(relics, 1, "с депозита сходит ровно одна реликвия за забег")
	t.check(bool(dep["relic_taken"]), "флаг «реликвия взята» выставлен")

static func test_relic_not_in_shallow_ruins(t: TestCtx) -> void:
	var w: SimWorld = _world(82)
	var a: SimAgent = w.agents.agents[0]
	var dep: Dictionary = {"kind": "ruins_near", "relic_taken": false,
		"cell": Vector2i(26, Balance.mark_to_floor_cell_y(-2)), "id": 0, "amount": 5}
	for i: int in 200:
		w.agents._roll_relic(a, dep, -2, w)
	t.check_eq(a.bag_count("relic"), 0, "в ближних руинах реликвий не бывает")

## Снаряжение выдаётся тому, кто больше всех работал на глубине.
static func test_gear_goes_to_deepest_worker(t: TestCtx) -> void:
	var w: SimWorld = _world(91)
	w.storage.store(0, StackUtil.make("gear", 1, false))
	w.agents.agents[0].deep_gathered = 2
	w.agents.agents[3].deep_gathered = 9
	w.agents.agents[4].deep_gathered = 9        # ничья → больший id
	w.jobs.mark_dirty()
	t.run_ticks(w, 2)
	t.check(w.agents.agents[4].has_gear, "снаряжение у самого «глубокого» (при ничьей — старший id)")
	t.check(not w.agents.agents[3].has_gear, "второму не досталось")
	t.check_eq(w.storage.count_in(0, "gear"), 0, "со склада снаряжение забрали")

## Приёмка промпта: агент со снаряжением переживает 10 секунд под водой.
static func test_gear_survives_ten_seconds(t: TestCtx) -> void:
	var w: SimWorld = _world(92)
	var a: SimAgent = w.agents.agents[0]
	a.trait_ids = []
	a.has_gear = true
	a.recompute_from_traits()
	a.platform_id = w.terrain.platform_at(Vector2i(40, Balance.mark_to_floor_cell_y(-8)))
	a.x = 40.0
	a.target_x = 40.0
	w.tide.level_override = 0.0
	t.run_ticks(w, 100)
	t.check(a.is_alive(), "со снаряжением 10 секунд под водой не смертельны")

# --- Отчёт цикла ----------------------------------------------------------

static func test_cycle_report_has_gathered(t: TestCtx) -> void:
	var w: SimWorld = _world(101)
	t.run_ticks(w, Balance.TICKS_PER_CYCLE - 1)
	w.tick()
	var report: Dictionary = {}
	for e: SimEvent in w.events_out:
		if e.type == "cycle_ended":
			report = e.data
	t.check(report.has("gathered"), "в итоге цикла есть колонка «добыто»")
	var g: Dictionary = report["gathered"] as Dictionary
	var total: int = 0
	for k: Variant in g:
		total += int(g[k])
	t.check(total > 0, "и она не пустая (добыто %d единиц)" % total)

# --- Политики -------------------------------------------------------------

static func test_policy_defaults_and_command(t: TestCtx) -> void:
	var w: SimWorld = _world(111)
	t.check_eq(w.policies.get_value(SimTypes.Policy.GREED), 1, "Жадность 1 по умолчанию")
	t.check_eq(w.policies.get_value(SimTypes.Policy.CAUTION), 2, "Осторожность 2")
	t.check_eq(w.policies.get_value(SimTypes.Policy.SUPPLY), 2, "Заготовка 2")
	w.apply_command({"kind": "set_policy", "policy": SimTypes.Policy.GREED, "value": 3})
	w.tick()
	t.check_eq(w.policies.get_value(SimTypes.Policy.GREED), 3, "команда меняет политику")
	var found: bool = false
	for e: SimEvent in w.events_out:
		if e.type == "policy_changed":
			found = true
	t.check(found, "и эмитит policy_changed")
	w.apply_command({"kind": "set_policy", "policy": SimTypes.Policy.GREED, "value": 99})
	w.tick()
	t.check_eq(w.policies.get_value(SimTypes.Policy.GREED), 3, "значение зажато в 0..3")

static func test_beacon_command(t: TestCtx) -> void:
	var w: SimWorld = _world(112)
	var cell: Vector2i = Vector2i(30, Balance.mark_to_floor_cell_y(-4))
	w.apply_command({"kind": "set_beacon", "cell": SimTypes.v2i_to_arr(cell)})
	w.tick()
	t.check_eq(w.jobs.beacon_cell, cell, "маяк переставлен")
	var found: bool = false
	for e: SimEvent in w.events_out:
		if e.type == "beacon_moved":
			found = true
	t.check(found, "и эмитит beacon_moved")

# --- Детерминизм ----------------------------------------------------------

static func test_determinism_with_jobs(t: TestCtx) -> void:
	var a: SimWorld = _world(31337)
	var b: SimWorld = _world(31337)
	for i: int in 20000:
		t.run_ticks(a, 1)
		t.run_ticks(b, 1)
		if i % 2000 == 0 and TestCtx.state_hash(a) != TestCtx.state_hash(b):
			t.check(false, "миры с работами разошлись на тике %d" % i)
			return
	t.check_eq(TestCtx.state_hash(a), TestCtx.state_hash(b),
		"20 000 тиков с работами: состояния совпадают")

static func test_jobs_survive_save(t: TestCtx) -> void:
	var w: SimWorld = _world(2024)
	t.run_ticks(w, 4000)
	var text: String = JSON.stringify(w.to_dict(), "", true, true)
	var restored: SimWorld = SimWorld.new()
	restored.from_dict(JSON.parse_string(text) as Dictionary, _cliff())
	t.check_eq(JSON.stringify(restored.to_dict(), "", true, true), text,
		"пул задач и политики переживают JSON")
	for i: int in 2000:
		t.run_ticks(w, 1)
		t.run_ticks(restored, 1)
	t.check_eq(TestCtx.state_hash(w), TestCtx.state_hash(restored),
		"после загрузки мир с работами продолжается идентично")

# --- Резервация не переживает прерывания (C1.1) ---------------------------

## Ставит план постройки и гоняет мир, пока кто-нибудь не возьмёт build-задачу.
## Возвращает агента или null.
static func _agent_on_build_job(w: SimWorld, max_ticks: int) -> SimAgent:
	for i: int in max_ticks:
		t_tick(w)
		for a: SimAgent in w.agents.agents:
			if a.job_id == -1:
				continue
			var j: Dictionary = w.jobs.jobs.get(a.job_id, {})
			if not j.is_empty() and str(j["kind"]) == "build":
				return a
	return null

static func t_tick(w: SimWorld) -> void:
	w.tick()
	w.events_out.clear()

## Отзыв во время стройки не должен выключать агента из игры до конца забега:
## задача обязана вернуться в пул, а сам он — снова работать после цикла.
static func test_recall_releases_taken_job(t: TestCtx) -> void:
	var w: SimWorld = _world(909)
	var cell: Vector2i = Vector2i(10, Balance.mark_to_floor_cell_y(3) - 1)
	t.check(w.buildings.place("hearth", cell, w) > 0, "план очага поставлен")
	var a: SimAgent = _agent_on_build_job(w, 4000)
	t.check(a != null, "кто-то взял стройку очага")
	if a == null:
		return
	var job_id: int = a.job_id
	w.agents.recall(false, w)
	t_tick(w)
	t.check_eq(a.job_id, -1, "Отзыв освободил резервацию")
	var j: Dictionary = w.jobs.jobs.get(job_id, {})
	if not j.is_empty():
		t.check_eq(int(j["taken_by"]), -1, "и задача снова свободна")

## Паника и утопление рвут ту же связь — проверяем их отдельно от Отзыва.
static func test_panic_releases_taken_job(t: TestCtx) -> void:
	var w: SimWorld = _world(911)
	var cell: Vector2i = Vector2i(10, Balance.mark_to_floor_cell_y(3) - 1)
	w.buildings.place("hearth", cell, w)
	var a: SimAgent = _agent_on_build_job(w, 4000)
	t.check(a != null, "кто-то взял стройку очага")
	if a == null:
		return
	# Дух в ноль, агент на −2, вода подошла вплотную (но ещё не топит).
	a.needs["mood"] = 0
	a.recalled = false
	_put_on_mark(w, a, -2, 20)
	w.tide.level_override = -2.5
	t_tick(w)
	t.check_eq(a.state, SimTypes.AgentState.PANIC, "агент запаниковал")
	t.check_eq(a.job_id, -1, "паника освободила резервацию")

static func test_drowning_releases_taken_job(t: TestCtx) -> void:
	var w: SimWorld = _world(912)
	var cell: Vector2i = Vector2i(10, Balance.mark_to_floor_cell_y(3) - 1)
	w.buildings.place("hearth", cell, w)
	var a: SimAgent = _agent_on_build_job(w, 4000)
	t.check(a != null, "кто-то взял стройку очага")
	if a == null:
		return
	a.recalled = false
	_put_on_mark(w, a, -2, 20)
	w.tide.level_override = 4.0
	t_tick(w)
	t.check_eq(a.state, SimTypes.AgentState.DROWNING, "агент тонет")
	t.check_eq(a.job_id, -1, "утопление освободило резервацию")

## Переставляет агента на отметку: тестам нужна воспроизводимая мизансцена.
static func _put_on_mark(w: SimWorld, a: SimAgent, mark: int, x: int) -> void:
	a.platform_id = w.terrain.platform_of_mark(mark)
	a.x = float(x)
	a.target_x = a.x
	a.climb_to = -1
	a.climb_t = 0.0
	a.path.clear()
	a.path_graph_version = -1

## Главный ущерб C1.1: после эпизода Отзыва стройку никто не достраивает.
static func test_hearth_finishes_after_recall(t: TestCtx) -> void:
	var w: SimWorld = _world(913)
	var cell: Vector2i = Vector2i(10, Balance.mark_to_floor_cell_y(3) - 1)
	var bid: int = w.buildings.place("hearth", cell, w)
	var a: SimAgent = _agent_on_build_job(w, 4000)
	t.check(a != null, "кто-то взял стройку очага")
	w.agents.recall(false, w)
	t_tick(w)
	w.agents.clear_recall()               # как на границе цикла
	var done: bool = false
	for i: int in 12000:
		t_tick(w)
		if int(w.buildings.buildings[bid]["state"]) == int(SimTypes.BuildState.ACTIVE):
			done = true
			break
	t.check(done, "очаг всё-таки достроен, колония не залипла")

# --- A1.2: дно потребностей (docs/00 §6.3) --------------------------------

## Первая задача указанного вида, за которую агент прямо сейчас взялся бы.
static func _applicable_job(w: SimWorld, a: SimAgent, kind: String) -> Dictionary:
	for id: int in w.jobs.order:
		var j: Dictionary = w.jobs.jobs[id]
		if str(j["kind"]) != kind:
			continue
		if w.jobs.applies_to(a, j, w):
			return j
	return {}

## Сытость = 0 — «не работает: только ест/лежит». Голодный агент брал любую
## работу наравне с сытым: две полосы из трёх были без дна.
static func test_starving_agent_only_eats(t: TestCtx) -> void:
	var w: SimWorld = _world(101)
	# До Малой воды: на старте вода стоит на нуле, и вся добыча под ней.
	t.run_ticks(w, 600)
	var a: SimAgent = w.agents.agents[0]
	var gather: Dictionary = _applicable_job(w, a, "gather")
	t.check(not gather.is_empty(), "сытому агенту добыча по силам")
	if gather.is_empty():
		return
	a.needs["satiety"] = 0
	t.check(not w.jobs.applies_to(a, gather, w), "голодный за ту же добычу не берётся")
	# Но еда ему по-прежнему доступна — иначе он просто умрёт стоя.
	var eat: Dictionary = _applicable_job(w, a, "eat")
	t.check(not eat.is_empty(), "а поесть голодный идёт")

## Дух = 0 — «отказ спускаться в этом цикле». Флаг латч: Дух может отрасти
## внутри цикла, но вниз агент в этом цикле уже не пойдёт.
static func test_broken_spirit_refuses_to_descend(t: TestCtx) -> void:
	var w: SimWorld = _world(103)
	t.run_ticks(w, 600)
	# Стройка на +3: работа «дома», которой отказ спускаться касаться не должен.
	# Ставим ПОСЛЕ прокрутки, иначе агенты успевают её закончить.
	var plan: int = w.buildings.place("hearth",
		Vector2i(10, Balance.mark_to_floor_cell_y(3) - 1), w)
	for k: String in DB.building("hearth").cost:
		w.buildings.deliver(plan, StackUtil.make(k,
			int(DB.building("hearth").cost[k]), false), w)
	t_tick(w)
	var a: SimAgent = w.agents.agents[0]
	var below: Dictionary = {}
	for id: int in w.jobs.order:
		var j: Dictionary = w.jobs.jobs[id]
		if float(Balance.cell_to_mark(j["cell"] as Vector2i)) >= w.danger_mark():
			continue
		if w.jobs.applies_to(a, j, w):
			below = j
			break
	t.check(not below.is_empty(), "в пуле есть работа в отливной зоне, и агент за неё берётся")
	if below.is_empty():
		return
	# Работа «дома» — её отказ спускаться трогать не должен. Ищем до того, как
	# уронили Дух, и без потребностей: те зависят от сытости, а не от спуска.
	var home: Dictionary = {}
	for id2: int in w.jobs.order:
		var j2: Dictionary = w.jobs.jobs[id2]
		if str(j2["kind"]) == "eat" or str(j2["kind"]) == "rest":
			continue
		if float(Balance.cell_to_mark(j2["cell"] as Vector2i)) < w.danger_mark():
			continue
		if w.jobs.applies_to(a, j2, w):
			home = j2
			break
	a.needs["mood"] = 0
	t_tick(w)
	t.check(a.no_descend_cycle, "Дух в ноль поднял флаг «вниз не пойду»")
	t.check(not w.jobs.applies_to(a, below, w), "и работу внизу агент не берёт")
	# Дом при этом продолжает работать: отказ касается только спуска.
	t.check(not home.is_empty(), "в пуле нашлась работа выше воды")
	if not home.is_empty():
		t.check(w.jobs.applies_to(a, home, w), "а работу наверху берёт как раньше")
	a.needs["mood"] = Balance.NEED_MAX_MILLI
	t.check(not w.jobs.applies_to(a, below, w),
		"отказ держится до конца цикла, а не отпускает вместе с Духом")
	w.agents.on_cycle_started(w)
	t.check(not a.no_descend_cycle, "новый цикл флаг снимает")
	t.check(w.jobs.applies_to(a, below, w), "и агент снова спускается")

## R11: отдых берётся только на Высокой воде, но взятая задача жила вечно —
## агент, начавший отдых под конец HIGH, простаивал пол-отлива.
static func test_rest_ends_with_high_water(t: TestCtx) -> void:
	var w: SimWorld = _world(105)
	var rester: SimAgent = null
	for i: int in Balance.TICKS_PER_CYCLE * 2:
		for a0: SimAgent in w.agents.agents:
			a0.needs["fatigue"] = 0        # вымотаны: отдых им точно нужен
		t_tick(w)
		if w.clock.phase != SimTypes.Phase.HIGH:
			continue
		for a: SimAgent in w.agents.agents:
			if a.state == SimTypes.AgentState.REST:
				rester = a
				break
		if rester != null:
			break
	t.check(rester != null, "кто-то лёг отдыхать на Высокой воде")
	if rester == null:
		return
	# Докручиваем до Спада.
	for i2: int in Balance.TICKS_PER_CYCLE:
		t_tick(w)
		if w.clock.phase == SimTypes.Phase.EBB:
			break
	t.check_eq(w.clock.phase, SimTypes.Phase.EBB, "начался Спад")
	t_tick(w)
	t.check(rester.state != SimTypes.AgentState.REST,
		"на Спаде отдых прерван, а не тянется полфазы")

## R1: голодный ныряет за едой. Склад под водой всё равно «рекламировал» еду,
## и агент на Высокой воде шёл к нему через DROWNING.
static func test_no_eating_from_flooded_storage(t: TestCtx) -> void:
	var w: SimWorld = _world(107)
	var sid: int = w.storage.add_storage(Vector2i(20, Balance.mark_to_floor_cell_y(-2)))
	w.storage.store(sid, StackUtil.make("rations", 5, false))
	var a: SimAgent = w.agents.agents[0]
	a.needs["satiety"] = 0
	# Сухо: склад кормит.
	w.tide.level_override = -6.0
	t_tick(w)
	var jid: int = _eat_job_for(w, sid)
	t.check(jid >= 0, "сухой склад предлагает еду")
	if jid < 0:
		return
	t.check(w.jobs.applies_to(a, w.jobs.jobs[jid], w), "и голодный за ней идёт")

	# Накрыло водой: за этой едой не идёт никто.
	w.tide.level_override = 1.0
	t_tick(w)
	t.check(not w.jobs.applies_to(a, w.jobs.jobs[jid], w),
		"за едой на затопленный склад голодный не ныряет")
	# И заново такая задача не порождается.
	w.jobs.mark_dirty()
	t_tick(w)
	t.check_eq(_eat_job_for(w, sid), -1, "затопленный склад еду не рекламирует")

## id задачи «поесть» на указанном складе, или −1.
static func _eat_job_for(w: SimWorld, sid: int) -> int:
	for id: int in w.jobs.order:
		var j: Dictionary = w.jobs.jobs[id]
		if str(j["kind"]) == "eat" and int(j["target_id"]) == sid:
			return id
	return -1
