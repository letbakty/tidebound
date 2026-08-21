class_name SimWorld
extends RefCounted
## Владелец всего состояния симуляции и единственная точка входа для tick().
## Ни одной ноды, ни одного await, ни одного обращения к Time.* — ядро должно
## гоняться в headless-тестах без сцены (docs/02 §1).
##
## Детерминизм: одинаковый сид + одинаковая последовательность команд
## → одинаковое состояние. Команды применяются ТОЛЬКО в начале тика.

const SAVE_VERSION: int = 1

var clock: SimClock = SimClock.new()
var tide: Tide = Tide.new()
var rng: SimRNG = SimRNG.new()
var terrain: Terrain = Terrain.new()
var storage: StorageSystem = StorageSystem.new()
var agents: AgentSystem = AgentSystem.new()
var jobs: JobSystem = JobSystem.new()
var buildings: BuildingSystem = BuildingSystem.new()
var production: ProductionSystem = ProductionSystem.new()
var crisis: CrisisSystem = CrisisSystem.new()
var run_state: RunState = RunState.new()
var policies: PolicySet = PolicySet.new()

## Разбирается Game после tick(); Game обязан очистить массив.
var events_out: Array[SimEvent] = []

## Версия графа навигации: инкремент при любом изменении (лестница построена
## или смыта). Кэш путей агентов (этапы 05/06) и оверлей дебага (03) сравнивают
## её со своей, чтобы не пересчитывать путь каждый тик (research/11 §7).
##
## Только чтение, сквозь Terrain. Хранить здесь СВОЮ копию нельзя: она отстаёт
## от рельефа между тиками (лестницу поставили — счётчик мира ещё старый),
## и сейв получается несогласованным сам с собой.
var graph_version: int:
	get: return terrain.graph_version

## Модификаторы текущего цикла (карты вылазки, кризисы). Заведён пустым уже
## сейчас, чтобы этапы 05/06/08/10 читали его, а не хардкод (research/11 §11).
var cycle_modifiers: Dictionary = {}

## Журнал команд для реплея и баг-репортов: сид + журнал воспроизводят забег
## целиком (research/25 §2.1). Пишется только при record = true — флаг в
## конструкторе, а не OS.is_debug_build(), чтобы не тащить OS.* в ядро.
var command_log: Array[Dictionary] = []

var _commands: Array[Dictionary] = []
var _record: bool = false
## Деф карты: нужен, чтобы восстановить площадки при загрузке.
var _cliff: CliffDef = null

func _init(record: bool = false) -> void:
	_record = record

# --- Забег ----------------------------------------------------------------

## cliff — карта утёса. Загружает её Game/тест: ResourceLoader в sim/ не место.
## unlock_list — разблокировки Журнала; этап 11 передаст сюда Meta.
func new_run(seed_value: int, cliff: CliffDef, unlock_list: Array[String] = []) -> void:
	clock = SimClock.new()
	tide = Tide.new()
	rng = SimRNG.new()
	rng.setup(seed_value)
	terrain = Terrain.new()
	storage = StorageSystem.new()
	agents = AgentSystem.new()
	jobs = JobSystem.new()
	buildings = BuildingSystem.new()
	production = ProductionSystem.new()
	crisis = CrisisSystem.new()
	run_state = RunState.new()
	policies = PolicySet.new()
	_cliff = cliff
	events_out.clear()
	_commands.clear()
	command_log.clear()
	cycle_modifiers.clear()
	tide.reset(clock)
	if cliff == null:
		push_error("SimWorld.new_run: карта утёса не передана")
	else:
		terrain.build(cliff, rng)
		storage.new_run(cliff)
		jobs.new_run()
		# Стартовый склад — тоже постройка, поэтому запасы кладём после неё.
		buildings.new_run(self, cliff)
		storage.stock_start(cliff)
		# Очаг горит с первого тика: иначе колония весь первый цикл живёт
		# без единого источника тепла.
		buildings.light_start_fires()
		production.new_run()
		crisis.new_run()
		run_state.new_run(unlock_list)
		unlocked = unlock_list.duplicate()
		# Первый цикл — тоже Спад: драфт положен и на нём.
		run_state.start_draft(self)
		refresh_heat_sources()
		agents.new_run(self)
	events_out.append(SimEvent.make("run_started", {"seed": seed_value}))
	events_out.append(SimEvent.make("cycle_started", {"cycle": clock.cycle}))

# --- Команды --------------------------------------------------------------

## Кладёт команду в очередь. Немедленно её НЕ исполняет: применение вне
## границы тика — прямой путь к рассинхрону (docs/02 §3.4).
func apply_command(cmd: Dictionary) -> void:
	if _record:
		command_log.append({"t": clock.total_ticks(), "cmd": cmd.duplicate(true)})
	_commands.append(cmd)

func _consume_commands() -> void:
	for cmd: Dictionary in _commands:
		var kind: String = str(cmd.get("kind", ""))
		match kind:
			"recall":
				var hard: bool = bool(cmd.get("hard", false))
				agents.recall(hard, self)
				events_out.append(SimEvent.make("recall_issued", {"hard": hard}))
			"set_policy":
				var pol: int = int(cmd.get("policy", -1))
				var val: int = int(cmd.get("value", 0))
				if policies.set_value(pol, val):
					jobs.mark_dirty()
					events_out.append(SimEvent.make("policy_changed",
						{"policy": pol, "value": policies.get_value(pol)}))
			"place_building":
				var def_id: String = str(cmd.get("def_id", ""))
				var pcell: Vector2i = SimTypes.arr_to_v2i(cmd.get("cell", [0, 0]) as Array)
				buildings.place(def_id, pcell, self)
			"demolish":
				buildings.demolish(int(cmd.get("id", -1)), self)
			"pick_card":
				run_state.pick_card(str(cmd.get("card", "")), self)
			"set_beacon":
				var cell: Vector2i = SimTypes.arr_to_v2i(cmd.get("cell", [0, 0]) as Array)
				jobs.beacon_cell = cell
				jobs.mark_dirty()
				events_out.append(SimEvent.make("beacon_moved", {"cell": cell}))
			# Остальные команды появятся на этапах 07 (стройка) и 10 (карты).
			# Ветка _: намеренно шумит.
			_:
				push_warning("SimWorld: неизвестная команда '%s'" % kind)
	_commands.clear()

# --- Тик ------------------------------------------------------------------

## Один атом времени. Порядок систем ФИКСИРОВАН (docs/02 §4) — перестановка
## меняет результат при том же сиде.
func tick() -> void:
	_consume_commands()
	var clock_events: Array[SimEvent] = clock.tick()
	events_out.append_array(clock_events)
	# Восполнение депозитов и плавник — на границе цикла, до всех остальных
	# систем: иначе первый тик нового цикла увидел бы пустую отмель.
	for e: SimEvent in clock_events:
		if e.type == "cycle_ended":
			# Порча и сушка считаются ДО того, как отчёт уйдёт наружу:
			# иначе итог цикла показал бы вчерашние числа.
			e.data.merge(storage.on_cycle_ended(), true)
			e.data.merge(agents.on_cycle_ended(self), true)
			e.data.merge(jobs.on_cycle_ended(), true)
			e.data.merge(production.on_cycle_ended(self), true)
			e.data.merge(crisis.on_cycle_ended(self), true)
			e.data.merge(run_state.end_cycle(self), true)
		elif e.type == "phase_changed":
			# Спад кончился, а карта не выбрана — страховка от зависшего цикла.
			if int(e.data["prev"]) == int(SimTypes.Phase.EBB):
				run_state.auto_pick_if_needed(self)
			# prev нужен именно здесь: «конец LOW» и «начало SIGNAL» — разные
			# события, и испаритель отдаёт соль по первому.
			production.on_phase_ended(int(e.data["prev"]), self)
			crisis.on_phase_ended(int(e.data["prev"]), self)
			buildings.on_phase_started(int(e.data["phase"]))
			crisis.on_phase_started(int(e.data["phase"]), self)
		elif e.type == "cycle_started":
			tide.reset_cycle_high()
			crisis.on_cycle_started(self)
			# Драфт — на каждом Спаде, то есть на границе цикла.
			run_state.start_draft(self)
			events_out.append_array(terrain.on_cycle_started(rng))
			storage.spawn_driftwood(terrain, rng)
			agents.on_cycle_started(self)
			jobs.on_cycle_started()
			buildings.on_cycle_started(self)
	events_out.append_array(tide.update(clock))
	# Заглушки будущих систем — порядок задан здесь, чтобы этапы 05–11
	# вставляли вызовы на готовые места, а не спорили об очерёдности.
	_tick_crises()
	_tick_buildings()
	_tick_production()
	_tick_jobs()
	_tick_agents()
	_tick_storage()
	_tick_run_state()
	events_out.append_array(run_state.drain_events())
	events_out.append_array(crisis.drain_events())
	events_out.append_array(buildings.drain_events())
	events_out.append_array(production.drain_events())
	events_out.append_array(jobs.drain_events())
	events_out.append_array(agents.drain_events())
	events_out.append_array(storage.drain_events())
	events_out.append(SimEvent.make("sim_ticked", {"tick": clock.total_ticks()}))

func _tick_crises() -> void:
	crisis.tick(self)

func _tick_buildings() -> void:
	buildings.tick(self)
	refresh_heat_sources()

func _tick_production() -> void:
	production.tick(self)

func _tick_jobs() -> void:
	jobs.tick(self)

func _tick_agents() -> void:
	agents.tick(self)

func _tick_storage() -> void:
	# Корзины лебёдки вода не вымывает — в этом их смысл.
	storage.on_tick(tide.level, production.basket_cells(self))

func _tick_run_state() -> void:
	pass    # этап 11

## Клетка старта колонии. Систему агентов деф карты напрямую не касается.
func cliff_spawn_cell() -> Vector2i:
	return _cliff.spawn_cell if _cliff != null else Vector2i.ZERO

## Идёт ли шторм. Наполняет этап 09; испаритель и дождесборник читают его
## уже сейчас.
var is_storm: bool = false

## Разблокировки Журнала. Наполняет этап 11; до тех пор — пустой список,
## и 🔒-постройки просто недоступны.
var unlocked: Array[String] = []

## Источники тепла — клетки РАБОТАЮЩИХ незатопленных очагов (заглушка этапа 05
## закрыта). debug_heat_sources остаётся для тестов, которым нужен очаг
## в произвольном месте.
var debug_heat_sources: Array[Vector2i] = []
## Пересчитывается раз в тик, а не на каждого агента: _near_heat зовётся
## шесть раз за тик, и перебирать постройки каждый раз было заметно дорого.
var _heat_cache: Array[Vector2i] = []

func beacon_cell() -> Vector2i:
	return jobs.beacon_cell

func heat_sources() -> Array[Vector2i]:
	return _heat_cache

func refresh_heat_sources() -> void:
	_heat_cache.clear()
	for b: Dictionary in buildings.with_special("hearth"):
		if buildings.is_working(b):
			_heat_cache.append(b["cell"] as Vector2i)
	_heat_cache.append_array(debug_heat_sources)

## Пересчёт всего, на что влияют карта цикла и шторм. Единственное место,
## где эти два источника сходятся: и карта, и шторм правят длительность
## отлива, и писать в phase_scale по очереди значило бы затирать друг друга.
func refresh_cycle_effects() -> void:
	tide.low_plateau = Balance.LOW_LEVEL \
		+ float(cycle_modifiers.get("low_plateau_add", 0.0))
	var scale: float = float(cycle_modifiers.get("low_time_mult", 1.0))
	if is_storm:
		scale *= Balance.STORM_LOW_SCALE
	clock.phase_scale[SimTypes.Phase.LOW] = scale

func heat_radius() -> int:
	return Balance.HEAT_RADIUS_BIG if unlocked.has(Balance.UNLOCK_HEARTH_BIG) \
		else Balance.HEAT_RADIUS

# --- Реплей ---------------------------------------------------------------

## Воспроизводит забег из сида и журнала команд: сид + килобайты лога вместо
## полного сейва (research/25 §2.1). Нужен баг-репортам и сценарным тестам.
static func replay(seed_value: int, log: Array[Dictionary], until_tick: int,
		cliff: CliffDef) -> SimWorld:
	var w: SimWorld = SimWorld.new()
	w.new_run(seed_value, cliff)
	w.events_out.clear()
	var i: int = 0
	while w.clock.total_ticks() < until_tick:
		while i < log.size() and int(log[i]["t"]) == w.clock.total_ticks():
			w.apply_command(log[i]["cmd"] as Dictionary)
			i += 1
		w.tick()
		w.events_out.clear()
	return w

# --- Сериализация ---------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"clock": clock.to_dict(),
		"tide": tide.to_dict(),
		"rng": rng.to_dict(),
		"cycle_modifiers": cycle_modifiers.duplicate(true),
		"terrain": terrain.to_dict(),
		"storage": storage.to_dict(),
		"agents": agents.to_dict(),
		"jobs": jobs.to_dict(),
		"buildings": buildings.to_dict(),
		"production": production.to_dict(),
		"crisis": crisis.to_dict(),
		"run_state": run_state.to_dict(),
		"policies": policies.to_dict(),
	}

## Требует, чтобы деф карты был известен: либо мир уже прошёл new_run,
## либо деф передан явно.
func from_dict(d: Dictionary, cliff: CliffDef = null) -> void:
	if cliff != null:
		_cliff = cliff
	var v: int = int(d.get("save_version", 0))
	if v != SAVE_VERSION:
		push_error("SimWorld.from_dict: версия сейва %d, ожидалась %d" % [v, SAVE_VERSION])
		return
	clock.from_dict(d.get("clock", {}) as Dictionary)
	tide.from_dict(d.get("tide", {}) as Dictionary)
	rng.from_dict(d.get("rng", {}) as Dictionary)
	cycle_modifiers = (d.get("cycle_modifiers", {}) as Dictionary).duplicate(true)
	# Площадки берутся из дефа, из сейва — только лестницы и депозиты.
	if _cliff != null:
		terrain.build_static(_cliff)
	terrain.from_dict(d.get("terrain", {}) as Dictionary)
	storage.from_dict(d.get("storage", {}) as Dictionary)
	agents.from_dict(d.get("agents", {}) as Dictionary)
	jobs.from_dict(d.get("jobs", {}) as Dictionary)
	buildings.from_dict(d.get("buildings", {}) as Dictionary)
	production.from_dict(d.get("production", {}) as Dictionary)
	crisis.from_dict(d.get("crisis", {}) as Dictionary)
	run_state.from_dict(d.get("run_state", {}) as Dictionary)
	unlocked = run_state.unlocks.duplicate()
	refresh_cycle_effects()
	is_storm = crisis.is_active(SimTypes.CrisisType.STORM)
	refresh_heat_sources()
	policies.from_dict(d.get("policies", {}) as Dictionary)
	events_out.clear()
	_commands.clear()
