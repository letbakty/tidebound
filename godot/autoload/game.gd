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

## Имя глобального шейдер-uniform времени (project.godot, [shader_globals]).
const SIM_TIME: StringName = &"sim_time"

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
## Скорость до автопаузы (драфт, итог цикла) — её возвращает resume_prev_speed.
var _paused_speed: int = 1
## Глубина автопаузы. СЧЁТЧИК, а не флаг: драфт может лечь поверх итога цикла,
## и закрытие верхнего окна не должно снимать паузу нижнего (research/21 §5).
var _pause_depth: int = 0
## Мир скрыт экраном (главное меню, настройки, Журнал) — тик не идёт вовсе.
##
## ⚠️ Это НЕ автопауза, и намеренно. Счётчик автопауз обнуляют cmd_new_run и
## restore_world, поэтому любая долгоживущая «заявка» на паузу поверх них
## разъезжается со счётчиком: после «Продолжить» снятие экранной паузы съедало
## паузу стартового драфта, и окно выбора висело над идущей игрой. Флаг живёт
## отдельно, выбранную игроком скорость не трогает и возвращает её сам
## (аудит B1.5).
var world_hidden: bool = false
## Секция интерфейса в сейве: показанные банеры и подсказки. Наполняют
## этапы 13 и 15; sim о ней не знает.
var ui_state: Dictionary = {}
## Результат последней записи сейва. Метка «Сохранено» не имеет права врать:
## именно из-за неё игрок спокойно закрывает игру (аудит B5).
var last_save_ok: bool = true

func _ready() -> void:
	# Своя метрика в Monitors рядом со встроенными графиками: бюджет тика
	# ≤2 мс (docs/00 §16) иначе видно только по дебаг-панели, а на телефоне
	# и Deck дебаггер недоступен вовсе (research/07).
	Performance.add_custom_monitor(&"tidebound/tick_ms", tick_budget_ms)

func _physics_process(delta: float) -> void:
	if speed == 0 or world == null or world_hidden:
		# Время шейдеров пушим и на паузе: значение не меняется, но материалы,
		# созданные во время паузы, должны получить актуальное число.
		_push_shader_time()
		return
	_accum += delta * float(speed)
	var steps: int = 0
	var t0: int = Time.get_ticks_usec()
	while _accum >= STEP and steps < MAX_TICKS_PER_FRAME:
		_accum -= STEP
		steps += 1
		world.tick()
		_flush_events()
		# ⚠️ speed проверяется КАЖДЫЙ тик, а не один раз на входе. Автопауза
		# ставится изнутри _flush_events (итог цикла, драфт, конец забега),
		# и без этой проверки при ×3 после конца цикла проходило ещё до
		# одиннадцати тиков: отчёт показывал одно, картинка — другое (SIM-10).
		if speed == 0:
			_accum = 0.0        # накопленное время паузу не переживает
			return
	if steps >= MAX_TICKS_PER_FRAME:
		# Долг не копим: иначе кадр за кадром будет всё хуже.
		_accum = 0.0
	_tick_budget_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	_push_shader_time()

# --- Команды игрока (единственный вход в sim) -----------------------------

## Карта утёса №1. Загружает её Game, а не sim: ResourceLoader — движковая
## вещь, в ядре её быть не должно (docs/02 §1).
const CLIFF_PATH: String = "res://data/cliffs/cliff_01.tres"

func cliff_def() -> CliffDef:
	return load(CLIFF_PATH) as CliffDef

## Забег всегда стартует с разблокировками Журнала: sim их не читает,
## Game передаёт копию (docs/02 §1).
##
## ⚠️ start_speed выставляется ДО раздачи стартовых событий: первый Спад даёт
## драфт, драфт ставит автопаузу, и «включить» скорость после этого значило бы
## молча её снять — окно выбора висело бы над идущей игрой (аудит B1.4).
func cmd_new_run(seed_value: int = 0, start_speed: int = 1) -> void:
	world = SimWorld.new(OS.is_debug_build())
	world.new_run(seed_value, cliff_def(), Meta.unlocked.duplicate())
	SaveService.delete_run()
	_accum = 0.0
	_error_count = 0
	_pause_depth = 0
	ui_state = {"banners": []}
	cmd_set_speed(clampi(start_speed, 0, 3))
	_flush_events()

## Досрочный уход: судно вызывается на следующий цикл, очки ×0.75.
func cmd_leave_early() -> void:
	if world != null:
		world.apply_command({"kind": "leave_early"})

## Немедленная сдача по решению игрока.
func cmd_surrender() -> void:
	if world != null:
		world.apply_command({"kind": "surrender"})

func cmd_save() -> void:
	last_save_ok = SaveService.save_run(ui_state)

func cmd_load() -> bool:
	return SaveService.load_run()

func has_save() -> bool:
	return SaveService.has_save()

## Восстановление мира из сейва + повторная эмиссия событий для UI.
## ui — секция интерфейса того же сейва (показанные банеры).
func restore_world(data: Dictionary, ui: Dictionary = {}) -> void:
	world = SimWorld.new(OS.is_debug_build())
	world.from_dict(data, cliff_def())
	_accum = 0.0
	_error_count = 0
	_pause_depth = 0
	ui_state = _ui_from_dict(ui)
	world.events_out.clear()
	rebroadcast_state()
	cmd_set_speed(0)

## После загрузки View-ноды пусты: их создают события, которых уже не будет.
## Любая View-нода, рождающаяся по событию, обязана быть покрыта здесь
## (research/18 §7) — новый тип сущности добавляет сюда строку.
func rebroadcast_state() -> void:
	if world == null:
		return
	Events.run_started.emit(world.rng.seed_value)
	Events.cycle_started.emit(world.clock.cycle)
	Events.phase_changed.emit(int(world.clock.phase), world.clock.cycle)
	Events.water_level_changed.emit(world.tide.level)
	for a: SimAgent in world.agents.agents:
		if a.is_alive():
			Events.agent_spawned.emit(a.id)
	for id: int in world.buildings.order:
		Events.building_placed.emit(id)
		Events.building_state_changed.emit(id)
	for d: Dictionary in world.terrain.deposits:
		Events.deposit_changed.emit(int(d["id"]))
	for s: Dictionary in world.storage.storages:
		Events.storage_changed.emit(int(s["id"]))
	for c: Dictionary in world.crisis.creatures:
		Events.creature_spawned.emit(int(c["id"]))
	Events.resources_changed.emit(world.storage.totals())
	Events.beacon_moved.emit(world.beacon_cell())
	for pol: int in SimTypes.POLICY_ORDER:
		Events.policy_changed.emit(pol, world.policies.get_value(pol))
	_rebroadcast_pending()

## Разовые события, которые уже прозвучали, но ещё не отыграны: их состояние
## в сейве есть, а сигнала после загрузки не будет (REL-04).
##
## ⚠️ Драфт — не косметика. Без него после «Продолжить» панель выбора не
## появится, автопауза не встанет, и на границе Спада auto_pick_if_needed
## возьмёт первую карту за игрока (docs/03 §8, research/24 §9).
func _rebroadcast_pending() -> void:
	for type: int in world.crisis.announced:
		Events.crisis_announced.emit(type,
			world.clock.cycle + Balance.CRISIS_ANNOUNCE_LEAD)
	for type2: int in world.crisis.active:
		Events.crisis_started.emit(type2)
	if world.run_state.ship_arrived and not world.run_state.finished:
		Events.ship_arrived.emit()
	if world.run_state.draft.is_empty() or world.run_state.drafted_this_cycle:
		return
	var ids: Array[String] = world.run_state.draft.duplicate()
	if Settings.pause_on_draft:
		push_pause()
	Events.draft_ready.emit(ids)

## Единственная прямая команда агентам (docs/00 §6.7).
func cmd_recall(hard: bool = false) -> void:
	if world == null:
		return
	world.apply_command({"kind": "recall", "hard": hard})

## Политики — единственный постоянный рычаг игрока (docs/00 §6.6).
## Снятие автопаузы: вернуть скорость, бывшую до неё (docs/02 §3.3).
func resume_prev_speed() -> void:
	if speed == 0:
		cmd_set_speed(maxi(1, _paused_speed))

## Автопауза с глубиной: сколько сущностей просят паузу, столько раз надо её
## снять. Все окна (драфт, итог цикла, банер, пауза) ходят через эту пару.
func push_pause() -> void:
	if _pause_depth == 0:
		_paused_speed = maxi(1, speed)
	_pause_depth += 1
	cmd_set_speed(0)

func pop_pause() -> void:
	# Ноль — значит паузу никто не ставил (настройка автопаузы выключена):
	# «снимать» её было бы вмешательством в текущую скорость игрока.
	if _pause_depth == 0:
		return
	_pause_depth -= 1
	if _pause_depth == 0:
		cmd_set_speed(_paused_speed)

func pause_depth() -> int:
	return _pause_depth

func cmd_set_policy(policy: int, value: int) -> void:
	if world == null:
		return
	world.apply_command({"kind": "set_policy", "policy": policy, "value": value})

## Маяк: центр притяжения работ на дне (docs/00 §6.7).
func cmd_set_beacon(cell: Vector2i) -> void:
	if world == null:
		return
	world.apply_command({"kind": "set_beacon", "cell": SimTypes.v2i_to_arr(cell)})

## Выбор плана вылазки.
##
## ⚠️ Автопаузу драфта снимает ScreenRouter при закрытии окна — по одному
## снятию на одну постановку. Второй pop_pause здесь уводил бы счётчик в чужую
## паузу: банер кризиса под драфтом отпускало бы вместе с ним, и игра шла бы
## под открытым банером.
func cmd_pick_card(card_id: String) -> void:
	if world == null:
		return
	world.apply_command({"kind": "pick_card", "card": card_id})

func cmd_set_speed(mult: int) -> void:
	var m: int = clampi(mult, 0, 3)
	if m == speed:
		return
	speed = m
	Events.speed_changed.emit(speed)

# --- Чтение состояния (не команды) ----------------------------------------

## Глобальный uniform времени для всех шейдеров мира (этап 18).
##
## ⚠️ Встроенный TIME запрещён: он не останавливается на паузе (research/05,
## подтверждено документацией 4.7). На тактической паузе — главной механике
## управления — вода продолжала бы волноваться, и пауза перестала бы читаться
## как пауза. Отсюда же скорость ×3 бесплатно ускоряет волну.
func _push_shader_time() -> void:
	RenderingServer.global_shader_parameter_set(SIM_TIME, sim_seconds())

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
	for i: int in mini(ticks, MAX_FAST_FORWARD_TICKS):
		world.tick()
		_flush_events()
	fast_forwarding = false
	# Пересборка картинки одним заходом: частые события во время промотки
	# отброшены (см. NOISY_EVENTS), и без этого мир на экране остался бы
	# в состоянии на начало промотки.
	rebroadcast_state()

## Потолок промотки за один вызов. Замер этапа 19: промотка целого забега
## одним куском разгоняет процесс до 2 ГБ — тики идут внутри одного кадра,
## и движку негде освободить то, что накопилось за них. Кнопки дебаг-панели
## просят максимум цикл, поэтому потолок в два цикла ничего не ломает.
const MAX_FAST_FORWARD_TICKS: int = Balance.TICKS_PER_CYCLE * 2

## Частые события, которые во время промотки НЕ рассылаются: за 3000 тиков их
## набегают десятки тысяч, и каждое дёргает весь интерфейс. Всё, что они
## сообщают, восстанавливается rebroadcast_state() в конце промотки —
## в отличие от отчётов цикла и забега, которые больше нигде не взять.
const NOISY_EVENTS: Array[String] = ["sim_ticked", "water_level_changed",
	"agent_updated", "storage_changed", "resources_changed", "deposit_changed",
	"building_state_changed", "production_spilled", "relic_found"]

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

## Срез часов для шкалы прилива: таймер фазы и плато текущего цикла.
## Зовётся раз в секунду, а не каждый кадр (research/21 §2).
func query_clock() -> Dictionary:
	if world == null:
		return {}
	return {
		"phase": int(world.clock.phase), "cycle": world.clock.cycle,
		"tick_in_phase": world.clock.tick_in_phase,
		"phase_len": world.clock.phase_len(world.clock.phase),
		"ticks_left": world.clock.ticks_left_in_phase(),
		"level": world.tide.level,
		"low_plateau": world.tide.low_plateau,
		"high_plateau": world.tide.high_plateau,
		# Докуда вода дошла в этом цикле: по этой отметке этап 18 рисует
		# мокрые тайлы после отлива (docs/00 §5).
		"last_high": world.tide.last_high_level,
		"announced": world.crisis.announced.duplicate(),
	}

## Остатки на складах. Нужны на СТАРТЕ забега: стартовый запас кладётся без
## события (storage.stock_start чистит pending — «старт не изменение»),
## и без этого запроса чипы показывали бы нули до первой добычи.
func query_totals() -> Dictionary:
	if world == null:
		return {}
	return world.storage.totals()

## Сухие остатки: «топливо-сухое» в HUD — не то же, что предмет вообще.
func query_dry_totals() -> Dictionary:
	if world == null:
		return {}
	return world.storage.totals_dry()

## Лёгкий срез для КАДРА: три поля без единой копии. Полный query_agent
## вызывает только карточка агента и раз в секунду — глубокая копия котомки
## шестьдесят раз в секунду на каждого агента не нужна никому (review/04 PERF-01).
func query_agent_look(id: int) -> Dictionary:
	if world == null:
		return {}
	var a: SimAgent = world.agents.agent(id)
	if a == null:
		return {}
	# mark и worst_need здесь, а не в query_agent: HUD дёргает срез на каждое
	# agent_updated, а полный срез копирует котомку целиком (аудит B3, PERF-01).
	# carry — ФЛАГ, а не котомка: спрайту нужна только поза «несёт», а копия
	# стаков на каждом кадре и была тем, от чего этот срез отделяли.
	return {"state": int(a.state), "wet": a.wet, "facing": a.facing,
		"mark": world.agents.agent_mark_f(a, world),
		"worst_need": minf(minf(a.satiety(), a.warmth()), a.mood()),
		"carry": not a.bag.is_empty(),
		"name": a.agent_name, "dead": a.state == SimTypes.AgentState.DEAD}

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

## «Починить» из панели постройки: ремонт и так рекламируется сам, но приказ
## игрока поднимает его срочность выше прочих дел (docs/03 §5.4).
func cmd_repair(building_id: int) -> void:
	if world == null:
		return
	world.apply_command({"kind": "repair", "id": building_id})

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
		"mark": int(b["mark"]), "state": int(b["state"]),
		"flooded": bool(b["flooded"]),
		"damaged": bool(b["damaged"]), "hp": int(b["hp"]),
		"progress": world.buildings.build_progress(b),
		"working": world.buildings.is_working(b),
		# Очагу и фонарю нужен остаток топлива (docs/03 §5.5).
		"lit": bool(b["lit"]), "fuel_left": int(b["fuel_left"]),
	}

## Срез станции для StationPanel: рецепт, буфер, прогресс и ПРИЧИНА ПРОСТОЯ
## текстом. Причину считает sim (одна логика на всех), панель только переводит.
func query_station(id: int) -> Dictionary:
	if world == null:
		return {}
	var b: Dictionary = world.buildings.buildings.get(id, {})
	if b.is_empty():
		return {}
	var rid: String = world.production.pick_recipe(b, world, true)
	var inputs: Dictionary = {}
	var outputs: Dictionary = {}
	var work_seconds: float = 0.0
	if not rid.is_empty():
		var r: RecipeDef = DB.recipe(rid)
		inputs = r.inputs.duplicate()
		outputs = r.outputs.duplicate()
		work_seconds = r.work_seconds
	var have: Dictionary = {}
	for k: Variant in inputs:
		have[str(k)] = BuildingSystem.buffer_count(b, str(k), false)
	var progress: float = 0.0
	if work_seconds > 0.0:
		progress = clampf(float(int(b["progress_ticks"]))
			/ (work_seconds * float(Balance.TICKS_PER_SEC)), 0.0, 1.0)
	return {
		"id": id, "def_id": str(b["def_id"]), "cell": b["cell"],
		"recipe": rid, "inputs": inputs, "outputs": outputs, "have": have,
		"progress": progress, "damaged": bool(b["damaged"]),
		"flooded": bool(b["flooded"]),
		"reason": ProductionSystem.idle_reason(b, world),
		"repair_cost": BuildingSystem.repair_cost(DB.building(str(b["def_id"]))),
	}

## Срез склада для StoragePanel: стаки со влажностью и остатком до порчи.
func query_storage(id: int) -> Dictionary:
	if world == null:
		return {}
	var i: int = world.storage.storage_index(id)
	if i < 0:
		return {}
	var s: Dictionary = world.storage.storages[i]
	var stacks: Array = []
	for v: Variant in s["stacks"] as Array:
		var cur: Dictionary = v as Dictionary
		var def: ItemDef = DB.item(str(cur["item_id"]))
		stacks.append({
			"item_id": str(cur["item_id"]), "count": int(cur["count"]),
			"wet": bool(cur["wet"]), "spoil_left": int(cur["spoil_left"]),
			"spoil_cycles": 0 if def == null else def.spoil_cycles,
		})
	var cell: Vector2i = s["cell"] as Vector2i
	return {
		"id": id, "cell": cell, "mark": Balance.cell_to_mark(cell),
		"capacity": int(s["capacity"]), "stacks": stacks,
	}

## id склада в клетке (склад — постройка, но склады нумерует StorageSystem).
func query_storage_at(cell: Vector2i) -> int:
	if world == null:
		return -1
	var floor_cell: Vector2i = Vector2i(cell.x,
		Balance.mark_to_floor_cell_y(Balance.cell_to_mark(cell)))
	var id: int = world.storage.storage_at(floor_cell)
	return id if id >= 0 else world.storage.storage_at(cell)

## Срез депозита для подсказки: сколько осталось, восполняется ли, реликвия.
func query_deposit(id: int) -> Dictionary:
	if world == null:
		return {}
	for d: Dictionary in world.terrain.deposits:
		if int(d["id"]) != id:
			continue
		var kind: String = str(d["kind"])
		var def: Dictionary = Balance.DEPOSIT_KINDS.get(kind, {}) as Dictionary
		var cell: Vector2i = d["cell"] as Vector2i
		return {
			"id": id, "kind": kind, "cell": cell,
			"item": str(def.get("item", "")),
			"amount": int(d["amount"]), "capacity": int(def.get("capacity", 0)),
			"refill": int(def.get("refill", 0)),
			"relic": not bool(d["relic_taken"])
				and Balance.cell_to_mark(cell) <= Balance.RELIC_MARK_MAX,
			"relic_marked": bool(d["relic_marked"]),
		}
	return {}

## Текущие значения политик — панель открывается уже настроенной, даже если
## policy_changed прилетал до её создания.
func query_policies() -> Dictionary:
	var out: Dictionary = {}
	if world == null:
		return out
	for pol: int in SimTypes.POLICY_ORDER:
		out[pol] = world.policies.get_value(pol)
	return out

## Живые агенты для экрана итога: имена нужны рядом с эпитафиями погибших.
func query_survivors() -> Array:
	var out: Array = []
	if world == null:
		return out
	for a: SimAgent in world.agents.agents:
		if a.is_alive():
			out.append({"name": a.agent_name, "bio": a.bio_key})
	return out

## Списки для панелей и радиала: что вообще можно построить в этом забеге.
func query_unlocked_buildings() -> Array[String]:
	var out: Array[String] = []
	for bid: String in DB.building_ids():
		var d: BuildingDef = DB.building(bid)
		if not d.buildable:
			continue                      # стартовая постройка без цены (C2.4)
		if d.unlock_id.is_empty() or (world != null and world.unlocked.has(d.unlock_id)):
			out.append(bid)
	return out

## Можно ли заложить постройку ПРЯМО СЕЙЧАС: материалы на складах лежат и
## хотя бы одна клетка утёса её примет. По этому признаку радиал стройки
## делит список на две страницы — иначе первым слотом на первом забеге стоит
## койка, а игрок ещё ни разу ничего не строил (docs/03 §6).
##
## Обход всего утёса стоит пары тысяч проверок, и это нормально: зовётся один
## раз на открытие радиала, а не в кадре.
func query_can_build_now(def_id: String) -> bool:
	if world == null:
		return false
	var d: BuildingDef = DB.building(def_id)
	if d == null or not d.buildable:
		return false
	var have: Dictionary[String, int] = world.storage.totals()
	for k: String in d.cost:
		if int(have.get(k, 0)) < int(d.cost[k]):
			return false
	return _has_build_spot(def_id, d)

## Есть ли на утёсе клетка, куда постройка встаёт по всем правилам.
##
## ⚠️ Нижний ряд постройки лежит на клетку ВЫШЕ пола яруса: опора проверяется
## под ним, и y = пол яруса вернул бы ERR_NO_SUPPORT на всей карте. Лестница
## живёт не на сетке, а на ребре графа — у неё своя проверка.
func _has_build_spot(def_id: String, d: BuildingDef) -> bool:
	for mark: int in range(Balance.TOP_MARK, Balance.BOTTOM_MARK - 1, -1):
		var pidx: int = world.terrain.platform_of_mark(mark)
		if pidx < 0:
			continue
		var pl: Dictionary = world.terrain.platforms[pidx]
		var y: int = Balance.mark_to_floor_cell_y(mark)
		if d.special != "ladder":
			y -= d.size.y
		for x: int in range(int(pl["x0"]), int(pl["x1"]) + 1):
			if world.buildings.place_error(def_id, Vector2i(x, y), world).is_empty():
				return true
	return false

## Ближайшие склады, где лежит нужный материал — для линий призрака стройки
## (паттерн Against the Storm).
func query_material_sources(def_id: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if world == null:
		return out
	var d: BuildingDef = DB.building(def_id)
	if d == null:
		return out
	for s: Dictionary in world.storage.storages:
		for k: String in d.cost:
			if world.storage.count_in(int(s["id"]), k) > 0:
				out.append(s["cell"] as Vector2i)
				break
	return out

## Срез существа для CreatureView: грызёт постройку или просто идёт. Поза —
## единственный канал, которым существо о себе сообщает: подписей у него нет.
func query_creature_look(id: int) -> Dictionary:
	if world == null:
		return {}
	for c: Dictionary in world.crisis.creatures:
		if int(c["id"]) == id:
			return {"gnaw": int(c["gnaw_ticks"]) > 0,
				"leaving": bool(c["leaving"])}
	return {}

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

## Конец забега: очки уходят в Журнал, сейв забега удаляется, игра встаёт.
func _on_run_ended(report: Dictionary) -> void:
	Meta.record_run(report)
	SaveService.delete_run()
	cmd_set_speed(0)
	Events.run_ended.emit(report)

# --- Секция интерфейса в сейве --------------------------------------------

## Банер первого появления кризиса за забег. Возвращает true, если тип этого
## кризиса ещё не показывали — тогда HUD ставит автопаузу.
##
## Список, а не словарь: ключи Dictionary[int, bool] после JSON round-trip
## станут строками (research/21 §5).
## JSON отдаёт числа float'ами, а банеры сравниваются как int: без приведения
## `shown.has(type)` промахивается, и каждый банер после загрузки снова первый.
func _ui_from_dict(ui: Dictionary) -> Dictionary:
	var shown: Array[int] = []
	for v: Variant in ui.get("banners", []) as Array:
		shown.append(int(v))
	shown.sort()
	return {"banners": shown}

func note_banner(type: int) -> bool:
	var shown: Array = ui_state.get("banners", []) as Array
	if shown.has(type):
		return false
	shown.append(type)
	shown.sort()
	ui_state["banners"] = shown
	return true

# --- Трансляция событий ---------------------------------------------------

## events_out → сигналы Events. Ветка _: обязательна: без неё неизвестный тип
## события терялся бы молча (research/11 §6).
func _flush_events() -> void:
	if world == null:
		return
	for e: SimEvent in world.events_out:
		if fast_forwarding and NOISY_EVENTS.has(e.type):
			continue
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
				# Автопауза Итога цикла и автосейв на границе (docs/00 §4, §14).
				# Какие события паузят — решает игрок (docs/03 §3.6).
				if Settings.pause_on_cycle:
					push_pause()
				last_save_ok = SaveService.save_run(ui_state)
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
			"draft_ready":
				var ids: Array[String] = []
				for v: Variant in e.data["cards"] as Array:
					ids.append(str(v))
				# Автопауза драфта: скорость запоминаем, чтобы вернуть её
				# после выбора (docs/00 §4).
				if Settings.pause_on_draft:
					push_pause()
				Events.draft_ready.emit(ids)
			"card_picked":
				Events.card_picked.emit(str(e.data["card"]))
			"ship_arrived":
				Events.ship_arrived.emit()
			"run_ended":
				_on_run_ended(e.data["report"] as Dictionary)
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
