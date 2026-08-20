extends Node
## Оркестратор: владеет SimWorld, тикает его фиксированным шагом, транслирует
## events_out в сигналы Events и принимает команды игрока cmd_* (docs/02 §3.3, §4).
##
## Это граница между чистым ядром и движком: всё нодовое, что нужно симуляции,
## живёт здесь, а не в res://sim/.

const TICKS_PER_SEC: int = Balance.TICKS_PER_SEC
const STEP: float = 1.0 / float(TICKS_PER_SEC)
## Защита от «спирали смерти»: при лаге не пытаться догнать всё разом
## (research/11 §3). Лучше играть медленнее, чем зависнуть.
const MAX_TICKS_PER_FRAME: int = 12

## 0 = пауза. Паузу делаем скоростью, get_tree().paused не трогаем (docs/01 §6).
var speed: int = 0
var world: SimWorld = null

var _accum: float = 0.0
## Время последнего кадра симуляции, мс — для графика в дебаг-панели (этап 03).
var _tick_budget_ms: float = 0.0
## Сколько событий не нашли своего сигнала. Этапу 19 это даёт бесплатную
## «санитарию сигналов»: прогон забега с проверкой, что счётчик остался нулём.
var _error_count: int = 0
## Поднят на время промотки времени дебаг-панелью: View-ноды пропускают
## анимации и создают/удаляют себя без Tween'ов.
var fast_forwarding: bool = false

func _physics_process(delta: float) -> void:
	if speed == 0 or world == null:
		return
	_accum += delta * float(speed)
	var steps: int = 0
	var t0: int = Time.get_ticks_usec()
	while _accum >= STEP and steps < MAX_TICKS_PER_FRAME:
		_accum -= STEP
		steps += 1
		world.tick()
		_flush_events()
	if steps >= MAX_TICKS_PER_FRAME:
		# Долг не копим: иначе кадр за кадром будет всё хуже.
		_accum = 0.0
	_tick_budget_ms = float(Time.get_ticks_usec() - t0) / 1000.0

# --- Команды игрока (единственный вход в sim) -----------------------------

## Карта утёса №1. Загружает её Game, а не sim: ResourceLoader — движковая
## вещь, в ядре её быть не должно (docs/02 §1).
const CLIFF_PATH: String = "res://data/cliffs/cliff_01.tres"

func cliff_def() -> CliffDef:
	return load(CLIFF_PATH) as CliffDef

func cmd_new_run(seed_value: int = 0) -> void:
	world = SimWorld.new(OS.is_debug_build())
	world.new_run(seed_value, cliff_def())
	_accum = 0.0
	_error_count = 0
	_flush_events()
	cmd_set_speed(1)

func cmd_set_speed(mult: int) -> void:
	var m: int = clampi(mult, 0, 3)
	if m == speed:
		return
	speed = m
	Events.speed_changed.emit(speed)

# --- Чтение состояния (не команды) ----------------------------------------

## Дробное сим-время для шейдеров (этап 18): целые тики + недотиканный остаток.
func sim_seconds() -> float:
	if world == null:
		return 0.0
	return float(world.clock.total_ticks()) * STEP + _accum

## Промотка времени для дебаг-панели (этап 03). Гейт стоит здесь, а не только
## в панели: один рубеж защиты — это ноль рубежей.
func debug_fast_forward(ticks: int) -> void:
	if not OS.is_debug_build() or world == null:
		return
	# View-ноды по этому флагу пропускают анимации: 3000 пачек сигналов подряд
	# иначе захлебнут UI созданием Tween'ов (research/13 §8).
	fast_forwarding = true
	for i: int in ticks:
		world.tick()
		_flush_events()
	fast_forwarding = false

## Тиков до ближайшей границы фазы / цикла — для кнопок «+1 фаза» и «+1 цикл».
func debug_ticks_to_next_phase() -> int:
	if world == null:
		return 0
	return maxi(1, world.clock.phase_len(world.clock.phase) - world.clock.tick_in_phase)

func debug_ticks_to_next_cycle() -> int:
	if world == null:
		return 0
	var left: int = debug_ticks_to_next_phase()
	var p: int = int(world.clock.phase)
	for i: int in range(p + 1, SimTypes.PHASE_ORDER.size()):
		left += world.clock.phase_len(i as SimTypes.Phase)
	return left

func tick_budget_ms() -> float:
	return _tick_budget_ms

func error_count() -> int:
	return _error_count

# --- Трансляция событий ---------------------------------------------------

## events_out → сигналы Events. Ветка _: обязательна: без неё неизвестный тип
## события терялся бы молча (research/11 §6).
func _flush_events() -> void:
	if world == null:
		return
	for e: SimEvent in world.events_out:
		match e.type:
			"sim_ticked":
				Events.sim_ticked.emit(int(e.data["tick"]))
			"phase_changed":
				Events.phase_changed.emit(int(e.data["phase"]), int(e.data["cycle"]))
			"water_level_changed":
				Events.water_level_changed.emit(float(e.data["level"]))
			"cycle_started":
				Events.cycle_started.emit(int(e.data["cycle"]))
			"cycle_ended":
				Events.cycle_ended.emit(e.data as Dictionary)
			"run_started":
				Events.run_started.emit(int(e.data["seed"]))
			"deposit_changed":
				Events.deposit_changed.emit(int(e.data["id"]))
			"storage_changed":
				Events.storage_changed.emit(int(e.data["id"]))
			"resources_changed":
				Events.resources_changed.emit(e.data["totals"] as Dictionary)
			_:
				_error_count += 1
				push_error("SimEvent без маппинга: %s" % e.type)
	world.events_out.clear()
