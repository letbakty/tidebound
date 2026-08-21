class_name AgentSystem
extends RefCounted
## Жизнь агентов: спавн, движение по графу, FSM, потребности, утопление,
## отзыв, пополнение колонии (docs/00 §6).
##
## FSM — enum + match в два уровня: сначала безусловные прерывания по
## приоритету DROWNING > RETURN > PANIC > потребности, потом работа состояния.
## Прерывание съедает тик целиком, иначе агент за один тик успеет и
## запаниковать, и сделать два шага — порядок эффектов станет неочевидным
## (research/15 §2).

var agents: Array[SimAgent] = []
var _next_id: int = 0
## На каком цикле последний раз пришёл новичок — для правила «не чаще 1 раза
## в 2 цикла» (docs/00 §6.1).
var _last_newcomer_cycle: int = -99
var _pending: Array[SimEvent] = []

# --- Спавн ----------------------------------------------------------------

func new_run(w: SimWorld) -> void:
	agents.clear()
	_next_id = 0
	_last_newcomer_cycle = -99
	_pending.clear()
	for i: int in Balance.START_AGENTS:
		_spawn(w)

func _spawn(w: SimWorld) -> SimAgent:
	var a: SimAgent = SimAgent.new()
	a.id = _next_id
	_next_id += 1
	a.agent_name = str(w.rng.pick(AgentPools.NAMES))
	a.bio_key = str(w.rng.pick(AgentPools.BIO_KEYS))
	# Две РАЗНЫЕ черты: вторую тянем, пока не отличается от первой.
	var ids: Array[String] = DB.trait_ids()
	var first: String = str(w.rng.pick(ids))
	var second: String = first
	while second == first and ids.size() > 1:
		second = str(w.rng.pick(ids))
	a.trait_ids = [first, second]
	a.init_needs()
	a.recompute_from_traits()

	var cell: Vector2i = w.cliff_spawn_cell()
	a.platform_id = w.terrain.platform_at(cell)
	a.x = float(cell.x)
	a.target_x = a.x
	agents.append(a)
	_pending.append(SimEvent.make("agent_spawned", {"id": a.id}))
	return a

func agent(id: int) -> SimAgent:
	for a: SimAgent in agents:
		if a.id == id:
			return a
	return null

func alive_count() -> int:
	var n: int = 0
	for a: SimAgent in agents:
		if a.is_alive():
			n += 1
	return n

# --- Тик ------------------------------------------------------------------

func tick(w: SimWorld) -> void:
	for a: SimAgent in agents:
		if not a.is_alive():
			continue
		a.state_ticks += 1
		_tick_needs(a, w)
		_tick_agent(a, w)
	# Отложенные апдейты досылаем одним проходом в конце тика: иначе последнее
	# изменение перед «тишиной» потеряется и UI застынет на устаревшем.
	for a2: SimAgent in agents:
		if a2.update_pending:
			_queue_agent_updated(a2, w)

func _tick_agent(a: SimAgent, w: SimWorld) -> void:
	if _check_drowning(a, w):
		return
	if _check_recall(a, w):
		return
	if _check_panic(a, w):
		return
	match a.state:
		SimTypes.AgentState.IDLE:
			_do_idle(a, w)
		SimTypes.AgentState.GOTO:
			_do_goto(a, w)
		SimTypes.AgentState.RETURN:
			_do_return(a, w)
		SimTypes.AgentState.REST:
			_do_rest(a, w)
		SimTypes.AgentState.EAT:
			_do_eat(a, w)
		SimTypes.AgentState.PANIC:
			_do_return(a, w)
		SimTypes.AgentState.GATHER:
			_do_gather(a, w)
		SimTypes.AgentState.HAUL:
			_do_haul(a, w)
		SimTypes.AgentState.WORK:
			# Станции — этап 08; до тех пор состояние просто отпускает агента.
			_finish_job(a, w)
		_:
			pass

# --- Потребности ----------------------------------------------------------

func _tick_needs(a: SimAgent, w: SimWorld) -> void:
	a.apply_rate("satiety", -a.hunger_rate_milli)
	var near_heat: bool = _near_heat(a, w)
	var warm_rate: int = -(a.warmth_wet_rate_milli if a.wet else a.warmth_rate_milli)
	if near_heat:
		warm_rate += Balance.WARMTH_HEAT_PER_CYCLE_MILLI
	a.apply_rate("warmth", warm_rate)
	if a.state != SimTypes.AgentState.REST:
		a.apply_rate("fatigue", -a.fatigue_rate_milli)
	# Мокрый флаг снимается у очага за 30 с (или сам на границе цикла).
	if a.wet and near_heat:
		a.heat_ticks += 1
		if a.heat_ticks >= int(Balance.WET_DRY_SEC_AT_HEAT * Balance.TICKS_PER_SEC):
			a.wet = false
			a.heat_ticks = 0
	elif not near_heat:
		a.heat_ticks = 0
	if a.state == SimTypes.AgentState.IDLE:
		a.idle_ticks_cycle += 1

func _near_heat(a: SimAgent, w: SimWorld) -> bool:
	var cell: Vector2i = agent_cell(a, w)
	for h: Vector2i in w.heat_sources():
		if absi(h.x - cell.x) + absi(h.y - cell.y) <= Balance.HEAT_RADIUS:
			return true
	return false

# --- Прерывания -----------------------------------------------------------

## Утопление считается счётчиком погружения, а не мгновенной смертью.
func _check_drowning(a: SimAgent, w: SimWorld) -> bool:
	if not Balance.is_markf_flooded(agent_mark_f(a, w), w.tide.level):
		a.submerged_ticks = 0
		a.drowning_warned = false
		if a.state == SimTypes.AgentState.DROWNING:
			_set_state(a, SimTypes.AgentState.RETURN, w)
		return false
	a.wet = true
	a.submerged_ticks += 1
	var warn_at: int = a.drown_limit_ticks - int(Balance.DROWN_WARN_SEC * Balance.TICKS_PER_SEC)
	# Ровно один раз за утопление, а не каждый тик последних двух секунд.
	if a.submerged_ticks >= warn_at and not a.drowning_warned:
		a.drowning_warned = true
		_pending.append(SimEvent.make("agent_drowning", {"id": a.id}))
	_set_state(a, SimTypes.AgentState.DROWNING, w)
	if a.submerged_ticks >= a.drown_limit_ticks:
		_kill(a, "drown", w)
		return true
	# Тонущий не стоит на месте: продолжает выбираться наверх.
	_do_return(a, w)
	return true

func _check_recall(a: SimAgent, w: SimWorld) -> bool:
	if not a.recalled:
		return false
	if a.state != SimTypes.AgentState.RETURN:
		_set_state(a, SimTypes.AgentState.RETURN, w)
		_set_return_target(a, w)
	_do_return(a, w)
	return true

## РЕШЕНИЕ: существ ещё нет (этап 09), поэтому паника опирается на вторую
## половину условия docs/00 §6.2 — «Дух<30 в воде». Считаем «в воде» как
## «на дне, ниже отметки 0»: там агента и застаёт прилив.
## Этап 09 добавит сюда проверку дистанции до существа и panic_range.
func _check_panic(a: SimAgent, w: SimWorld) -> bool:
	var panicking: bool = a.state == SimTypes.AgentState.PANIC
	if a.modifier("no_panic", 0.0) > 0.0:
		if panicking:
			_set_state(a, SimTypes.AgentState.IDLE, w)
		return false
	var low: int = Balance.NEED_LOW_ENTER_MILLI
	var exit_v: int = Balance.NEED_LOW_EXIT_MILLI
	var mark: float = agent_mark_f(a, w)
	if not panicking:
		if int(a.needs["mood"]) >= low or mark >= 0.0:
			return false
		_set_state(a, SimTypes.AgentState.PANIC, w)
		_set_return_target(a, w)
	elif int(a.needs["mood"]) >= exit_v and mark >= 0.0:
		_set_state(a, SimTypes.AgentState.IDLE, w)
		return false
	_do_return(a, w)
	return true

# --- Состояния ------------------------------------------------------------

func _do_idle(a: SimAgent, w: SimWorld) -> void:
	# Бродит по своей площадке: раз в пару секунд выбирает новую точку.
	if absf(a.target_x - a.x) > 0.01:
		_advance_on_platform(a, w)
		return
	if a.state_ticks % (Balance.TICKS_PER_SEC * 2) != 0:
		return
	var p: Dictionary = w.terrain.platforms[a.platform_id]
	a.target_x = float(w.rng.randi_range(int(p["x0"]), int(p["x1"])))

func _do_goto(a: SimAgent, w: SimWorld) -> void:
	if _advance_path(a, w):
		_set_state(a, a.intent, w)

func _do_return(a: SimAgent, w: SimWorld) -> void:
	if a.goto_platform < 0:
		_set_return_target(a, w)
	if _advance_path(a, w):
		if a.recall_hard:
			a.recall_hard = false
		if not a.recalled and a.state != SimTypes.AgentState.DROWNING:
			_set_state(a, SimTypes.AgentState.IDLE, w)

func _do_rest(a: SimAgent, w: SimWorld) -> void:
	if not _at_goal(a):
		_advance_path(a, w)
		return
	a.apply_rate("fatigue", a.fatigue_rest_milli)
	if int(a.needs["fatigue"]) >= Balance.NEED_MAX_MILLI:
		_finish_job(a, w)

func _do_eat(a: SimAgent, w: SimWorld) -> void:
	if not _at_goal(a):
		_advance_path(a, w)
		return
	var st: int = w.storage.storage_at(agent_cell(a, w))
	if st < 0:
		_finish_job(a, w)
		return
	# Провизия сытнее и не портит настроение — берём её первой.
	var got: Array[Dictionary] = w.storage.take(st, "rations", 1)
	var gain: int = Balance.EAT_RATIONS_MILLI
	var raw: bool = false
	if got.is_empty():
		got = w.storage.take(st, "catch", 1)
		gain = Balance.EAT_CATCH_MILLI
		raw = true
	if got.is_empty():
		_finish_job(a, w)
		return
	a.change_need("satiety", gain)
	if raw:
		a.change_need("mood", -Balance.MOOD_RAW_FOOD_MILLI)
	elif _near_heat(a, w):
		a.change_need("mood", Balance.MOOD_WARM_MEAL_MILLI)   # тёплый ужин
	_finish_job(a, w)

# --- Работы ---------------------------------------------------------------
# Задачу выдаёт JobSystem; здесь только исполнение. Резервирование —
# двусторонняя связь job.taken_by ⟺ agent.job_id, и рвать её можно только
# через JobSystem.release.

## Свободен ли агент для новой задачи. Тонущий, паникующий и отозванный —
## не свободны: их поведение приоритетнее любой работы.
func can_take_job(a: SimAgent) -> bool:
	return a.is_alive() and a.job_id == -1 and not a.recalled \
		and a.state == SimTypes.AgentState.IDLE

func start_job(a: SimAgent, j: Dictionary, w: SimWorld) -> void:
	a.work_ticks = 0
	var cell: Vector2i = j["cell"] as Vector2i
	var then: SimTypes.AgentState = _state_for_class(int(j["class"]))
	# Носильщик с полными руками идёт сразу к месту разгрузки.
	if then == SimTypes.AgentState.HAUL and not a.bag.is_empty():
		cell = j["to_cell"] as Vector2i
	_go_to_cell(a, w, cell, then)

func abandon_job(a: SimAgent, w: SimWorld) -> void:
	a.work_ticks = 0
	if not a.bag.is_empty():
		_start_self_haul(a, w)          # с грузом в руках — сначала донести
		return
	_set_state(a, SimTypes.AgentState.IDLE, w)

func _finish_job(a: SimAgent, w: SimWorld) -> void:
	w.jobs.release(a)
	a.work_ticks = 0
	_set_state(a, SimTypes.AgentState.IDLE, w)

static func _state_for_class(job_class: int) -> SimTypes.AgentState:
	match job_class:
		SimTypes.JobClass.GATHER:
			return SimTypes.AgentState.GATHER
		SimTypes.JobClass.HAUL:
			return SimTypes.AgentState.HAUL
		SimTypes.JobClass.EAT:
			return SimTypes.AgentState.EAT
		SimTypes.JobClass.REST:
			return SimTypes.AgentState.REST
	return SimTypes.AgentState.WORK

## Добыча: 1 единица за GATHER_SEC_PER_UNIT секунд (быстрее у Трудяги).
func _do_gather(a: SimAgent, w: SimWorld) -> void:
	if not _at_goal(a):
		_advance_path(a, w)
		return
	var j: Dictionary = w.jobs.jobs.get(a.job_id, {})
	if j.is_empty():
		_finish_job(a, w)
		return
	var di: int = w.terrain.deposit_index(int(j["target_id"]))
	if di < 0 or a.bag_free_slots() <= 0:
		_gather_done(a, w)
		return
	a.work_ticks += 1
	if a.work_ticks < a.gather_ticks_per_unit:
		return
	a.work_ticks = 0
	var dep: Dictionary = w.terrain.deposits[di]
	var item_id: String = str(j["item_id"])
	var got: int = w.terrain.take(int(j["target_id"]), 1)
	if got <= 0:
		_gather_done(a, w)
		return
	_put_in_bag(a, item_id, got)
	var mark: int = Balance.cell_to_mark(dep["cell"] as Vector2i)
	w.jobs.note_gathered(a, item_id, got, mark)
	w.jobs.queue_event(SimEvent.make("deposit_changed", {"id": int(dep["id"])}))
	_roll_relic(a, dep, mark, w)
	if int(w.terrain.deposits[di]["amount"]) <= 0 or a.bag_free_slots() <= 0:
		_gather_done(a, w)

## Реликвия выпадает только в глубоких руинах и только раз с депозита
## (docs/00 §3.2). Зоркий повышает шанс.
func _roll_relic(a: SimAgent, dep: Dictionary, mark: int, w: SimWorld) -> void:
	if str(dep["kind"]) != "ruins_deep" or mark > Balance.RELIC_MARK_MAX:
		return
	if bool(dep["relic_taken"]) or a.bag_free_slots() <= 0:
		return
	if not w.rng.chance(Balance.RELIC_CHANCE * a.modifier("relic_chance_mult")):
		return
	dep["relic_taken"] = true
	_put_in_bag(a, "relic", 1)
	for other: SimAgent in agents:
		if other.is_alive():
			other.change_need("mood", Balance.MOOD_RELIC_MILLI)
	w.jobs.queue_event(SimEvent.make("relic_found", {"agent": a.id}))

func _put_in_bag(a: SimAgent, item_id: String, n: int) -> void:
	var fresh: Dictionary = StackUtil.make(item_id, n, false)
	var def: ItemDef = DB.item(item_id)
	for s: Dictionary in a.bag:
		if StackUtil.can_merge(s, fresh) and int(s["count"]) < def.stack_size:
			s["count"] = int(s["count"]) + n
			return
	a.bag.append(fresh)

## Добыл сколько мог — теперь донести. Задача отпускается: пока агент идёт
## со своим грузом, депозит должен быть доступен другим.
func _gather_done(a: SimAgent, w: SimWorld) -> void:
	w.jobs.release(a)
	a.work_ticks = 0
	if a.bag.is_empty():
		_set_state(a, SimTypes.AgentState.IDLE, w)
		return
	_start_self_haul(a, w)

func _start_self_haul(a: SimAgent, w: SimWorld) -> void:
	var sid: int = _nearest_storage(a, w)
	if sid < 0:
		_set_state(a, SimTypes.AgentState.IDLE, w)
		return
	var cell: Vector2i = w.storage.storages[w.storage.storage_index(sid)]["cell"] as Vector2i
	_go_to_cell(a, w, cell, SimTypes.AgentState.HAUL)

func _nearest_storage(a: SimAgent, w: SimWorld) -> int:
	var best: int = -1
	var best_d: float = INF
	for s: Dictionary in w.storage.storages:
		if (s["stacks"] as Array).size() >= int(s["capacity"]):
			continue
		var pid: int = w.terrain.platform_at(s["cell"] as Vector2i)
		if pid < 0:
			continue
		var d: float = w.terrain.path_length_tiles(
			w.terrain.find_path(a.platform_id, pid))
		if pid != a.platform_id and is_equal_approx(d, 0.0):
			continue                                  # пути нет
		d += absf(a.x - float((s["cell"] as Vector2i).x))
		if d < best_d or (is_equal_approx(d, best_d) and int(s["id"]) < best):
			best_d = d
			best = int(s["id"])
	return best

## Переноска в две ноги: пустые руки — идём к грузу, полные — к складу.
func _do_haul(a: SimAgent, w: SimWorld) -> void:
	var j: Dictionary = w.jobs.jobs.get(a.job_id, {})
	if not j.is_empty():
		# Пустые руки — идём к грузу, полные — к складу.
		var dest: Vector2i = (j["cell"] as Vector2i) if a.bag.is_empty() \
			else (j["to_cell"] as Vector2i)
		_retarget(a, w, dest)
	if not _at_goal(a):
		_advance_path(a, w)
		return
	if a.bag.is_empty():
		if j.is_empty():
			_finish_job(a, w)
			return
		# Первая нога: подобрать груз с земли.
		var picked: Array[Dictionary] = w.storage.pickup_at(j["cell"] as Vector2i)
		if picked.is_empty():
			_finish_job(a, w)
			return
		for st: Dictionary in picked:
			a.bag.append(st)
		w.jobs.mark_dirty()
		_retarget(a, w, j["to_cell"] as Vector2i)
		return
	# Вторая нога: разгрузиться.
	var sid: int = w.storage.storage_at(agent_cell(a, w))
	if sid < 0:
		_finish_job(a, w)
		return
	var left: Array[Dictionary] = []
	for st2: Dictionary in a.bag:
		var rest: int = w.storage.store(sid, st2)
		if rest > 0:
			var keep: Dictionary = st2.duplicate()
			keep["count"] = rest
			left.append(keep)
	a.bag = left
	w.jobs.mark_dirty()
	_finish_job(a, w)

func _retarget(a: SimAgent, w: SimWorld, cell: Vector2i) -> void:
	var pid: int = w.terrain.platform_at(cell)
	if pid < 0 or (pid == a.goto_platform and is_equal_approx(a.goto_x, float(cell.x))):
		return
	a.goto_platform = pid
	a.goto_x = float(cell.x)
	_repath(a, w)

## Авто-возврат по Осторожности. Флаг тот же, что у ручного Отзыва: снимается
## на границе цикла.
func force_return(a: SimAgent, w: SimWorld) -> void:
	a.recalled = true
	_set_state(a, SimTypes.AgentState.RETURN, w)
	_set_return_target(a, w)

# --- Движение -------------------------------------------------------------

## Возвращает true, когда агент дошёл до цели (goto_platform, goto_x).
func _advance_path(a: SimAgent, w: SimWorld) -> bool:
	if a.goto_platform < 0:
		return true
	if a.climb_to >= 0:
		_advance_climb(a, w)
		return false
	# Лестницу могло смыть штормом — путь пересчитывается по версии графа.
	if a.path_graph_version != w.terrain.graph_version or a.path.is_empty():
		_repath(a, w)
	if a.platform_id == a.goto_platform:
		a.target_x = a.goto_x
		if absf(a.target_x - a.x) <= 0.01:
			a.x = a.target_x
			return true
		_advance_on_platform(a, w)
		return false
	var next_id: int = _next_platform(a)
	if next_id < 0:
		_repath(a, w)
		next_id = _next_platform(a)
		if next_id < 0:
			return true                   # пути нет — стоим, где стоим
	var ladder_x: int = _ladder_x_between(w, a.platform_id, next_id, a.x)
	if ladder_x < 0:
		_repath(a, w)
		return false
	a.target_x = float(ladder_x)
	if absf(a.target_x - a.x) > 0.01:
		_advance_on_platform(a, w)
		return false
	a.x = a.target_x
	a.climb_to = next_id
	a.climb_t = 0.0
	return false

func _advance_on_platform(a: SimAgent, w: SimWorld) -> void:
	var step: float = _speed(a, w, false) / float(Balance.TICKS_PER_SEC)
	var d: float = a.target_x - a.x
	if absf(d) <= step:
		a.x = a.target_x
		return
	# ⚠️ signf, а не signi: signi принимает int, и float-аргумент молча
	# усекается — при d = −0.8 направление становилось 0, и агент замирал
	# в трети тайла от цели навсегда.
	var dir: float = signf(d)
	a.facing = int(dir)
	# Квантование обязательно: непрерывное накопление float не переживает
	# сериализацию побитово (Balance.quant).
	a.x = Balance.quant(a.x + step * dir)

func _advance_climb(a: SimAgent, w: SimWorld) -> void:
	# Ярус — 3 тайла: столько лестницы и надо пройти.
	var tiles: float = float(Balance.TILES_PER_MARK)
	var step: float = _speed(a, w, true) / float(Balance.TICKS_PER_SEC) / tiles
	a.climb_t = Balance.quant(a.climb_t + step)
	if a.climb_t < 1.0:
		return
	a.platform_id = a.climb_to
	a.climb_to = -1
	a.climb_t = 0.0
	a.path_idx += 1

func _speed(a: SimAgent, w: SimWorld, ladder: bool) -> float:
	var base: float = Balance.LADDER_SPEED if ladder else Balance.WALK_SPEED
	# Порядок множителей фиксирован: черты → потребности → отзыв → карты цикла.
	# Разный порядок даёт разный float (research/11 §1).
	base *= a.modifier("ladder_speed_mult" if ladder else "speed_mult")
	if int(a.needs["satiety"]) < Balance.NEED_LOW_ENTER_MILLI:
		base *= Balance.NEED_SLOW_MULT
	if int(a.needs["warmth"]) <= 0:
		base *= Balance.NEED_SICK_MULT
	elif int(a.needs["warmth"]) < Balance.NEED_LOW_ENTER_MILLI:
		base *= Balance.NEED_SLOW_MULT
	if a.recall_hard:
		base *= Balance.HARD_RECALL_SPEED_MULT
	base *= float(w.cycle_modifiers.get("move_speed_mult", 1.0))
	return base

func _next_platform(a: SimAgent) -> int:
	if a.path.is_empty():
		return -1
	# Индекс мог разъехаться после пересчёта пути — ищем себя в пути.
	if a.path_idx >= a.path.size() or a.path[a.path_idx] != a.platform_id:
		a.path_idx = a.path.find(a.platform_id)
		if a.path_idx < 0:
			return -1
	if a.path_idx + 1 >= a.path.size():
		return -1
	return a.path[a.path_idx + 1]

## Ближайшая к агенту лестница между двумя ярусами, или −1.
## Тай-брейк по меньшему x обязателен: при равном расстоянии выбор иначе
## не определён, и два одинаковых забега разойдутся.
func _ladder_x_between(w: SimWorld, from_id: int, to_id: int, from_x: float) -> int:
	var top: int = maxi(int(w.terrain.platforms[from_id]["mark"]),
		int(w.terrain.platforms[to_id]["mark"]))
	var best: int = -1
	var best_d: float = INF
	for l: Dictionary in w.terrain.ladders:
		if int(l["mark_top"]) != top:
			continue
		var lx: int = int(l["x"])
		var dist: float = absf(float(lx) - from_x)
		if dist < best_d or (is_equal_approx(dist, best_d) and lx < best):
			best_d = dist
			best = lx
	return best

func _repath(a: SimAgent, w: SimWorld) -> void:
	a.path = w.terrain.find_path(a.platform_id, a.goto_platform)
	a.path_idx = 0
	a.path_graph_version = w.terrain.graph_version

func _go_to_cell(a: SimAgent, w: SimWorld, cell: Vector2i, then: SimTypes.AgentState) -> void:
	var pid: int = w.terrain.platform_at(cell)
	if pid < 0:
		return
	a.goto_platform = pid
	a.goto_x = float(cell.x)
	a.intent = then
	_repath(a, w)
	_set_state(a, SimTypes.AgentState.GOTO, w)

func _at_goal(a: SimAgent) -> bool:
	return a.climb_to < 0 and a.platform_id == a.goto_platform \
		and absf(a.x - a.goto_x) <= 0.01

## Цель отзыва — жилая площадка не ниже SAFE_MARK. Не отметка 0: в сизигию
## вода поднимается до +2, и «ноль» перестаёт быть безопасным.
func _set_return_target(a: SimAgent, w: SimWorld) -> void:
	var spawn: Vector2i = w.cliff_spawn_cell()
	var mark: int = maxi(Balance.cell_to_mark(spawn), Balance.SAFE_MARK)
	var pid: int = w.terrain.platform_of_mark(mark)
	if pid < 0:
		pid = w.terrain.platform_at(spawn)
	a.goto_platform = pid
	var p: Dictionary = w.terrain.platforms[pid]
	a.goto_x = float(clampi(spawn.x, int(p["x0"]), int(p["x1"])))
	_repath(a, w)

# --- Позиция --------------------------------------------------------------

## Дробная отметка: на лестнице агент между двумя ярусами, и вода достаёт его
## раньше, чем он долез.
func agent_mark_f(a: SimAgent, w: SimWorld) -> float:
	var from_m: float = float(int(w.terrain.platforms[a.platform_id]["mark"]))
	if a.climb_to < 0:
		return from_m
	var to_m: float = float(int(w.terrain.platforms[a.climb_to]["mark"]))
	return lerpf(from_m, to_m, a.climb_t)

func agent_cell(a: SimAgent, w: SimWorld) -> Vector2i:
	var mark: int = int(floor(agent_mark_f(a, w) + 0.5))
	return Vector2i(int(round(a.x)), Balance.mark_to_floor_cell_y(mark))

# --- Отзыв и смерть -------------------------------------------------------

func recall(hard: bool, w: SimWorld) -> void:
	for a: SimAgent in agents:
		if not a.is_alive():
			continue
		a.recalled = true
		a.recall_hard = hard
		if hard:
			# Жёсткий отзыв: груз бросают там, где стоят.
			for s: Dictionary in a.bag:
				w.storage.drop(agent_cell(a, w), s)
			a.bag.clear()
		_set_state(a, SimTypes.AgentState.RETURN, w)
		_set_return_target(a, w)

func clear_recall() -> void:
	for a: SimAgent in agents:
		a.recalled = false
		a.recall_hard = false

func _kill(a: SimAgent, cause: String, w: SimWorld) -> void:
	if not a.is_alive():
		return
	a.state = SimTypes.AgentState.DEAD
	a.bag.clear()
	a.has_gear = false                 # снаряжение теряется вместе с агентом
	w.jobs.on_agent_died(a)
	_pending.append(SimEvent.make("agent_died", {"id": a.id, "cause": cause}))
	# Смерть бьёт по всем живым сразу, без проверки дистанции (docs/00 §6.3).
	for other: SimAgent in agents:
		if other.is_alive():
			other.change_need("mood", -Balance.MOOD_DEATH_MILLI)

## Затопление склада — общее горе колонии (docs/00 §6.3).
func on_storage_flooded() -> void:
	for a: SimAgent in agents:
		if a.is_alive():
			a.change_need("mood", -Balance.MOOD_STORAGE_FLOODED_MILLI)

# --- Границы цикла --------------------------------------------------------

func on_cycle_started(w: SimWorld) -> void:
	clear_recall()
	for a: SimAgent in agents:
		a.idle_ticks_cycle = 0
		a.deep_gathered = 0
		a.wet = false                    # к началу нового цикла успел обсохнуть
		if a.state == SimTypes.AgentState.RETURN:
			_set_state(a, SimTypes.AgentState.IDLE, w)

## Возвращает сводку для итога цикла.
func on_cycle_ended(w: SimWorld) -> Dictionary:
	_apply_mood_aura()
	for a: SimAgent in agents:
		if not a.is_alive():
			continue
		if int(a.needs["warmth"]) < Balance.NEED_LOW_ENTER_MILLI:
			a.change_need("mood", -Balance.MOOD_COLD_PER_CYCLE_MILLI)
		var idle_penalty: float = a.modifier("idle_mood_penalty")
		if idle_penalty > 0.0 and a.idle_ticks_cycle > Balance.TICKS_PER_CYCLE / 2:
			a.change_need("mood", -int(idle_penalty * 1000.0))
	var newcomer: int = _try_newcomer(w)
	return {"agents_alive": alive_count(), "newcomer": newcomer}

## Весельчак/Угрюмый действуют на соседей ПО ЯРУСУ (docs/00 §6.4).
func _apply_mood_aura() -> void:
	var deltas: Dictionary[int, int] = {}
	for a: SimAgent in agents:
		if not a.is_alive():
			continue
		var aura: float = a.modifier("mood_aura")
		if is_zero_approx(aura):
			continue
		for other: SimAgent in agents:
			if other.id == a.id or not other.is_alive():
				continue
			if other.platform_id != a.platform_id:
				continue
			deltas[other.id] = int(deltas.get(other.id, 0)) + int(aura * 1000.0)
	for a2: SimAgent in agents:
		if deltas.has(a2.id):
			a2.change_need("mood", deltas[a2.id])

## Пополнение колонии: шанс 25% при среднем Духе > 60, не чаще раза в 2 цикла
## и не выше лимита (docs/00 §6.1). Возвращает id новичка или −1.
func _try_newcomer(w: SimWorld) -> int:
	if alive_count() == 0 or alive_count() >= Balance.MAX_AGENTS:
		return -1
	if w.clock.cycle - _last_newcomer_cycle < Balance.NEWCOMER_COOLDOWN_CYCLES:
		return -1
	if _average_mood() <= Balance.NEWCOMER_MOOD_MIN:
		return -1
	if not w.rng.chance(Balance.NEWCOMER_CHANCE):
		return -1
	_last_newcomer_cycle = w.clock.cycle
	var a: SimAgent = _spawn(w)
	for other: SimAgent in agents:
		if other.is_alive() and other.id != a.id:
			other.change_need("mood", Balance.MOOD_NEW_AGENT_MILLI)
	return a.id

func _average_mood() -> float:
	var n: int = 0
	var sum: float = 0.0
	for a: SimAgent in agents:
		if not a.is_alive():
			continue
		n += 1
		sum += a.mood()
	return 0.0 if n == 0 else sum / float(n)

# --- События --------------------------------------------------------------

func _set_state(a: SimAgent, s: SimTypes.AgentState, w: SimWorld) -> void:
	if a.state == s:
		return
	a.state = s
	a.state_ticks = 0
	_queue_agent_updated(a, w)

func _queue_agent_updated(a: SimAgent, w: SimWorld) -> void:
	if w.clock.total_ticks() - a.last_update_tick < Balance.TICKS_PER_SEC:
		a.update_pending = true
		return
	a.last_update_tick = w.clock.total_ticks()
	a.update_pending = false
	_pending.append(SimEvent.make("agent_updated", {"id": a.id}))

func drain_events() -> Array[SimEvent]:
	var out: Array[SimEvent] = _pending
	_pending = []
	return out

# --- Сериализация ---------------------------------------------------------

func to_dict() -> Dictionary:
	var list: Array = []
	for a: SimAgent in agents:
		list.append(a.to_dict())
	return {
		"next_id": _next_id,
		"last_newcomer_cycle": _last_newcomer_cycle,
		"agents": list,
	}

func from_dict(d: Dictionary) -> void:
	agents.clear()
	for v: Variant in d.get("agents", []) as Array:
		var a: SimAgent = SimAgent.new()
		a.from_dict(v as Dictionary)
		agents.append(a)
	_next_id = int(d.get("next_id", agents.size()))
	_last_newcomer_cycle = int(d.get("last_newcomer_cycle", -99))
	_pending.clear()
