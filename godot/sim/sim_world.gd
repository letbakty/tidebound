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

## Разбирается Game после tick(); Game обязан очистить массив.
var events_out: Array[SimEvent] = []

## Версия графа навигации: инкремент при любом изменении (лестница построена
## или смыта). Кэш путей агентов (этапы 05/06) и оверлей дебага (03) сравнивают
## её со своей, чтобы не пересчитывать путь каждый тик (research/11 §7).
var graph_version: int = 0

## Модификаторы текущего цикла (карты вылазки, кризисы). Заведён пустым уже
## сейчас, чтобы этапы 05/06/08/10 читали его, а не хардкод (research/11 §11).
var cycle_modifiers: Dictionary = {}

## Журнал команд для реплея и баг-репортов: сид + журнал воспроизводят забег
## целиком (research/25 §2.1). Пишется только при record = true — флаг в
## конструкторе, а не OS.is_debug_build(), чтобы не тащить OS.* в ядро.
var command_log: Array[Dictionary] = []

var _commands: Array[Dictionary] = []
var _record: bool = false

func _init(record: bool = false) -> void:
	_record = record

# --- Забег ----------------------------------------------------------------

func new_run(seed_value: int) -> void:
	clock = SimClock.new()
	tide = Tide.new()
	rng = SimRNG.new()
	rng.setup(seed_value)
	events_out.clear()
	_commands.clear()
	command_log.clear()
	graph_version = 0
	cycle_modifiers.clear()
	tide.reset(clock)
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
			# Команды появятся на этапах 06 (политики), 07 (стройка),
			# 10 (карты), 11 (отзыв/маяк). Ветка _: намеренно шумит.
			_:
				push_warning("SimWorld: неизвестная команда '%s'" % kind)
	_commands.clear()

# --- Тик ------------------------------------------------------------------

## Один атом времени. Порядок систем ФИКСИРОВАН (docs/02 §4) — перестановка
## меняет результат при том же сиде.
func tick() -> void:
	_consume_commands()
	events_out.append_array(clock.tick())
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
	events_out.append(SimEvent.make("sim_ticked", {"tick": clock.total_ticks()}))

func _tick_crises() -> void:
	pass    # этап 09

func _tick_buildings() -> void:
	pass    # этап 07

func _tick_production() -> void:
	pass    # этап 08

func _tick_jobs() -> void:
	pass    # этап 06

func _tick_agents() -> void:
	pass    # этап 05

func _tick_storage() -> void:
	pass    # этап 04 (порча)

func _tick_run_state() -> void:
	pass    # этап 11

# --- Реплей ---------------------------------------------------------------

## Воспроизводит забег из сида и журнала команд: сид + килобайты лога вместо
## полного сейва (research/25 §2.1). Нужен баг-репортам и сценарным тестам.
static func replay(seed_value: int, log: Array[Dictionary], until_tick: int) -> SimWorld:
	var w: SimWorld = SimWorld.new()
	w.new_run(seed_value)
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
		"graph_version": graph_version,
		"cycle_modifiers": cycle_modifiers.duplicate(true),
	}

func from_dict(d: Dictionary) -> void:
	var v: int = int(d.get("save_version", 0))
	if v != SAVE_VERSION:
		push_error("SimWorld.from_dict: версия сейва %d, ожидалась %d" % [v, SAVE_VERSION])
		return
	clock.from_dict(d.get("clock", {}) as Dictionary)
	tide.from_dict(d.get("tide", {}) as Dictionary)
	rng.from_dict(d.get("rng", {}) as Dictionary)
	graph_version = int(d.get("graph_version", 0))
	cycle_modifiers = (d.get("cycle_modifiers", {}) as Dictionary).duplicate(true)
	events_out.clear()
	_commands.clear()
