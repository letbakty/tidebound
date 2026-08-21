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

## Единственная прямая команда агентам (docs/00 §6.7).
func cmd_recall(hard: bool = false) -> void:
	if world == null:
		return
	world.apply_command({"kind": "recall", "hard": hard})

## Политики — единственный постоянный рычаг игрока (docs/00 §6.6).
func cmd_set_policy(policy: int, value: int) -> void:
	if world == null:
		return
	world.apply_command({"kind": "set_policy", "policy": policy, "value": value})

## Маяк: центр притяжения работ на дне (docs/00 §6.7).
func cmd_set_beacon(cell: Vector2i) -> void:
	if world == null:
		return
	world.apply_command({"kind": "set_beacon", "cell": SimTypes.v2i_to_arr(cell)})

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

## ЕДИНСТВЕННЫЙ разрешённый синхронный «pull» из sim (docs/02 §3.3):
## срез данных агента для View и карточки. Только чтение, только через Game.
func query_agent(id: int) -> Dictionary:
	if world == null:
		return {}
	var a: SimAgent = world.agents.agent(id)
	if a == null:
		return {}
	return {
		"id": a.id, "name": a.agent_name, "bio": a.bio_key,
		"traits": a.trait_ids.duplicate(),
		"state": int(a.state), "facing": a.facing, "wet": a.wet,
		"satiety": a.satiety(), "warmth": a.warmth(), "mood": a.mood(),
		"fatigue": a.fatigue(), "has_gear": a.has_gear,
		"mark": world.agents.agent_mark_f(a, world),
		"bag": a.bag.duplicate(true),
	}

## Мировая позиция агента в пикселях — для AgentView каждый кадр.
func query_agent_pos(id: int) -> Vector2:
	if world == null:
		return Vector2.ZERO
	var a: SimAgent = world.agents.agent(id)
	if a == null:
		return Vector2.ZERO
	var mark: float = world.agents.agent_mark_f(a, world)
	# Ноги агента на полу яруса: WorldGeo даёт верх яруса, добавляем два тайла.
	var y: float = WorldGeo.mark_to_world_y(mark) 		+ float((Balance.TILES_PER_MARK - 1) * WorldGeo.TILE)
	return Vector2(a.x * float(WorldGeo.TILE) + float(WorldGeo.TILE) * 0.5, y)

## Размещение постройки. Возвращает false, если место невалидно — тогда
## команда даже не уйдёт в очередь.
func cmd_place_building(def_id: String, cell: Vector2i) -> bool:
	if world == null or not world.buildings.can_place(def_id, cell, world):
		return false
	world.apply_command({"kind": "place_building", "def_id": def_id,
		"cell": SimTypes.v2i_to_arr(cell)})
	return true

func cmd_demolish(building_id: int) -> void:
	if world == null:
		return
	world.apply_command({"kind": "demolish", "id": building_id})

## Синхронное чтение для призрака размещения — тот же разрешённый «pull»,
## что и query_agent. Зовётся при смене клетки, а не каждый кадр.
func query_can_place(def_id: String, cell: Vector2i) -> bool:
	if world == null:
		return false
	return world.buildings.can_place(def_id, cell, world)

## Причина отказа ключом локализации ("" = можно) — для подсказки этапа 14.
func query_place_error(def_id: String, cell: Vector2i) -> String:
	if world == null:
		return "ERR_OCCUPIED"
	return world.buildings.place_error(def_id, cell, world)

func query_building(id: int) -> Dictionary:
	if world == null:
		return {}
	var b: Dictionary = world.buildings.buildings.get(id, {})
	if b.is_empty():
		return {}
	return {
		"id": id, "def_id": str(b["def_id"]), "cell": b["cell"],
		"state": int(b["state"]), "flooded": bool(b["flooded"]),
		"damaged": bool(b["damaged"]), "hp": int(b["hp"]),
		"progress": world.buildings.build_progress(b),
		"working": world.buildings.is_working(b),
	}

## Мировая позиция существа — для CreatureView каждый кадр.
func query_creature_pos(id: int) -> Vector2:
	if world == null:
		return Vector2.ZERO
	for c: Dictionary in world.crisis.creatures:
		if int(c["id"]) != id:
			continue
		var from_m: float = float(int(
			world.terrain.platforms[int(c["platform"])]["mark"]))
		var mark: float = from_m
		if int(c["climb_to"]) >= 0:
			mark = lerpf(from_m, float(int(
				world.terrain.platforms[int(c["climb_to"])]["mark"])), float(c["climb_t"]))
		var y: float = WorldGeo.mark_to_world_y(mark) \
			+ float((Balance.TILES_PER_MARK - 1) * WorldGeo.TILE)
		return Vector2(float(c["x"]) * float(WorldGeo.TILE)
			+ float(WorldGeo.TILE) * 0.5, y)
	return Vector2.ZERO

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
			"agent_spawned":
				Events.agent_spawned.emit(int(e.data["id"]))
			"agent_updated":
				Events.agent_updated.emit(int(e.data["id"]))
			"agent_died":
				Events.agent_died.emit(int(e.data["id"]), str(e.data["cause"]))
			"agent_drowning":
				Events.agent_drowning.emit(int(e.data["id"]))
			"recall_issued":
				Events.recall_issued.emit(bool(e.data["hard"]))
			"building_placed":
				Events.building_placed.emit(int(e.data["id"]))
			"building_state_changed":
				Events.building_state_changed.emit(int(e.data["id"]))
			"building_removed":
				Events.building_removed.emit(int(e.data["id"]))
			"crisis_announced":
				Events.crisis_announced.emit(int(e.data["type"]), int(e.data["cycle"]))
			"crisis_started":
				Events.crisis_started.emit(int(e.data["type"]))
			"crisis_ended":
				Events.crisis_ended.emit(int(e.data["type"]))
			"creature_spawned":
				Events.creature_spawned.emit(int(e.data["id"]))
			"creature_left":
				Events.creature_left.emit(int(e.data["id"]))
			"production_spilled":
				# Отдельного сигнала в контракте нет: выход на землю виден
				# как обычное изменение постройки (docs/02 §3.2).
				Events.building_state_changed.emit(int(e.data["id"]))
			"policy_changed":
				Events.policy_changed.emit(int(e.data["policy"]), int(e.data["value"]))
			"beacon_moved":
				Events.beacon_moved.emit(e.data["cell"] as Vector2i)
			"relic_found":
				# Отдельного сигнала под реликвию в контракте нет: она видна
				# через agent_updated и отчёт цикла (docs/02 §3.2).
				Events.agent_updated.emit(int(e.data["agent"]))
			_:
				_error_count += 1
				push_error("SimEvent без маппинга: %s" % e.type)
	world.events_out.clear()
