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
func new_run(seed_value: int, cliff: CliffDef) -> void:
	clock = SimClock.new()
	tide = Tide.new()
	rng = SimRNG.new()
	rng.setup(seed_value)
	terrain = Terrain.new()
	storage = StorageSystem.new()
	agents = AgentSystem.new()
	jobs = JobSystem.new()
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
		agents.new_run(self)
		jobs.new_run()
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
		elif e.type == "cycle_started":
			events_out.append_array(terrain.on_cycle_started(rng))
			storage.spawn_driftwood(terrain, rng)
			agents.on_cycle_started(self)
			jobs.on_cycle_started()
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
	events_out.append_array(jobs.drain_events())
	events_out.append_array(agents.drain_events())
	events_out.append_array(storage.drain_events())
	events_out.append(SimEvent.make("sim_ticked", {"tick": clock.total_ticks()}))

func _tick_crises() -> void:
	pass    # этап 09

func _tick_buildings() -> void:
	pass    # этап 07

func _tick_production() -> void:
	pass    # этап 08

func _tick_jobs() -> void:
	jobs.tick(self)

func _tick_agents() -> void:
	agents.tick(self)

func _tick_storage() -> void:
	storage.on_tick(tide.level)

func _tick_run_state() -> void:
	pass    # этап 11

## Клетка старта колонии. Систему агентов деф карты напрямую не касается.
func cliff_spawn_cell() -> Vector2i:
	return _cliff.spawn_cell if _cliff != null else Vector2i.ZERO

## Источники тепла (радиус Balance.HEAT_RADIUS).
## TODO(этап 07): заменить на клетки построенных очагов. Пока это «костёр
## лагеря» на клетке спавна плюс список, который наполняет тест.
var debug_heat_sources: Array[Vector2i] = []

func beacon_cell() -> Vector2i:
	return jobs.beacon_cell

func heat_sources() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if _cliff != null:
		out.append(_cliff.spawn_cell)
	out.append_array(debug_heat_sources)
	return out

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
	policies.from_dict(d.get("policies", {}) as Dictionary)
	events_out.clear()
	_commands.clear()
