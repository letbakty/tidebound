class_name CrisisSystem
extends RefCounted
## Кризисы по расписанию: сизигия, шторм, Приход (docs/00 §9.2–9.4).
##
## Главное продуктовое правило игры — «кризис по расписанию, а не по кубику»:
## всё объявляется за цикл, и провал всегда остаётся просчётом игрока,
## а не невезением. Поэтому календарь — данные (Balance.CRISIS_CALENDAR),
## а не броски RNG.

## Существо: {id, platform, x, target_kind, target_id, target_cell, carrying,
## gnaw_ticks, spawn_platform, leaving}
var creatures: Array[Dictionary] = []
var active: Array[int] = []                 # типы кризисов текущего цикла
var announced: Array[int] = []              # объявлено на следующий цикл

## Лестницы, перекрытые шлюзом в этом тике. Производное состояние: считается
## в _refresh_wet_graph перед ходом существ, в сейв не идёт.
var _blocked_ladders: Array[int] = []

var _next_creature_id: int = 1
var _pending: Array[SimEvent] = []
## Урон и кражи за цикл — в итог цикла.
var _damage_cycle: int = 0
var _stolen_cycle: Dictionary[String, int] = {}
var _storm_deaths: int = 0
## +1 к следующей сизигии от карты «Великий отлив» (этап 10 выставит флаг).
var next_spring_bonus: float = 0.0
var _spring_applied: bool = false

func new_run() -> void:
	creatures.clear()
	active.clear()
	announced.clear()
	_next_creature_id = 1
	_pending.clear()
	_damage_cycle = 0
	_stolen_cycle.clear()
	_storm_deaths = 0
	next_spring_bonus = 0.0
	_spring_applied = false

# --- Календарь ------------------------------------------------------------

static func events_for_cycle(cycle: int) -> Array:
	return Balance.CRISIS_CALENDAR.get(cycle, [])

func on_cycle_started(w: SimWorld) -> void:
	_end_previous(w)
	active.clear()
	announced.clear()
	var cycle: int = w.clock.cycle
	for e: Variant in events_for_cycle(cycle):
		var type: int = int((e as Dictionary)["type"])
		active.append(type)
		_start(type, int((e as Dictionary).get("count", 0)), w)
	# Объявление — ровно за CRISIS_ANNOUNCE_LEAD циклов до события.
	for e2: Variant in events_for_cycle(cycle + Balance.CRISIS_ANNOUNCE_LEAD):
		var t2: int = int((e2 as Dictionary)["type"])
		announced.append(t2)
		_pending.append(SimEvent.make("crisis_announced",
			{"type": t2, "cycle": cycle + Balance.CRISIS_ANNOUNCE_LEAD}))

func _start(type: int, count: int, w: SimWorld) -> void:
	match type:
		SimTypes.CrisisType.SPRING_TIDE:
			# Сизигия поднимает плато высокой воды: склады на +1..+2 уходят
			# под воду, и это финальное испытание забега.
			w.tide.high_plateau = Balance.HIGH_LEVEL + Balance.SPRING_BONUS \
				+ next_spring_bonus
			next_spring_bonus = 0.0
			_spring_applied = true
		SimTypes.CrisisType.STORM:
			w.is_storm = true
			# Шторм укорачивает отлив на 30% — через phase_scale, а не правкой
			# формулы фаз (самое опасное место для детерминизма).
			w.refresh_cycle_effects()
		SimTypes.CrisisType.VISIT:
			_pending_visit = count
	_pending.append(SimEvent.make("crisis_started", {"type": type}))

var _pending_visit: int = 0

func _end_previous(w: SimWorld) -> void:
	for type: int in active:
		match type:
			SimTypes.CrisisType.SPRING_TIDE:
				if _spring_applied:
					w.tide.high_plateau = Balance.HIGH_LEVEL
					_spring_applied = false
			SimTypes.CrisisType.STORM:
				w.is_storm = false
				w.refresh_cycle_effects()
			_:
				pass
		_pending.append(SimEvent.make("crisis_ended", {"type": type}))

func is_active(type: int) -> bool:
	return active.has(type)

# --- Фазы -----------------------------------------------------------------

## Пик шторма и приход существ — оба в начале Высокой воды.
func on_phase_started(phase: int, w: SimWorld) -> void:
	if phase != int(SimTypes.Phase.HIGH):
		return
	if is_active(SimTypes.CrisisType.STORM):
		_storm_peak(w)
	if _pending_visit > 0:
		# Карта «Тихая вода» отменяет Приход этого цикла.
		if float(w.cycle_modifiers.get("cancel_visit", 0.0)) <= 0.0:
			_spawn_creatures(_pending_visit, w)
		_pending_visit = 0

func on_phase_ended(phase: int, w: SimWorld) -> void:
	if phase != int(SimTypes.Phase.HIGH):
		return
	_leave_all(w)

## Пик шторма: ниже +1 гибель, на +1..+2 мокрый и −15 духа (docs/00 §9.4).
## Гибель здесь — всегда следствие политики Жадность 3 / Осторожность 0:
## шторм объявлен за цикл, и авто-возврат работает.
func _storm_peak(w: SimWorld) -> void:
	w.buildings.on_storm(w)
	for b: Dictionary in w.buildings.with_special("raincatcher"):
		if w.buildings.is_working(b):
			_pending.append(SimEvent.make("building_state_changed", {"id": int(b["id"])}))
	w.production.storm_water_bonus(w)
	for a: SimAgent in w.agents.agents:
		if not a.is_alive():
			continue
		var mark: float = w.agents.agent_mark_f(a, w)
		if mark < float(Balance.STORM_DEATH_MARK):
			w.agents.kill(a, "storm", w)
			_storm_deaths += 1
		elif mark <= float(Balance.STORM_WET_MARK_HI):
			a.wet = true
			a.change_need("mood", -Balance.MOOD_STORM_MILLI)

# --- Существа -------------------------------------------------------------

## Приходят «из моря» — с крайней правой затопленной площадки.
func _spawn_creatures(n: int, w: SimWorld) -> void:
	var spawn: int = _spawn_platform(w)
	if spawn < 0:
		return
	var p: Dictionary = w.terrain.platforms[spawn]
	for i: int in n:
		var c: Dictionary = {
			"id": _next_creature_id, "platform": spawn,
			"x": float(int(p["x1"])), "target_kind": "", "target_id": -1,
			"target_cell": Vector2i.ZERO, "carrying": {}, "gnaw_ticks": 0,
			"spawn_platform": spawn, "leaving": false, "climb_to": -1, "climb_t": 0.0,
		}
		_next_creature_id += 1
		creatures.append(c)
		_pending.append(SimEvent.make("creature_spawned", {"id": int(c["id"])}))

func _spawn_platform(w: SimWorld) -> int:
	var best: int = -1
	var best_x: int = -99999
	for p: Dictionary in w.terrain.platforms:
		if not Balance.is_mark_flooded(int(p["mark"]), w.tide.level):
			continue
		if int(p["x1"]) > best_x:
			best_x = int(p["x1"])
			best = int(p["id"])
	return best

func _leave_all(w: SimWorld) -> void:
	for c: Dictionary in creatures:
		_pending.append(SimEvent.make("creature_left", {"id": int(c["id"])}))
	creatures.clear()

func tick(w: SimWorld) -> void:
	if creatures.is_empty():
		return
	_refresh_wet_graph(w)
	for c: Dictionary in creatures:
		_tick_creature(c, w)
	_scare_agents(w)

## Блокировки пересобираются вместе с графом: фонарь запрещает узел,
## шлюз — ребро.
func _refresh_wet_graph(w: SimWorld) -> void:
	var blocked_nodes: Array[int] = []
	var radius: float = Balance.LANTERN_RADIUS_BIG \
		if w.unlocked.has(Balance.UNLOCK_LANTERN_BRIGHT) else Balance.LANTERN_RADIUS
	for lamp: Dictionary in w.buildings.with_special("lantern"):
		if not w.buildings.is_working(lamp):
			continue
		var lc: Vector2i = lamp["cell"] as Vector2i
		for p: Dictionary in w.terrain.platforms:
			var pid: int = int(p["id"])
			if blocked_nodes.has(pid):
				continue
			var py: int = Balance.mark_to_floor_cell_y(int(p["mark"]))
			# Узел считается «освещённым», если фонарь достаёт до его отрезка.
			var nearest_x: int = clampi(lc.x, int(p["x0"]), int(p["x1"]))
			var d: float = Vector2(Vector2i(nearest_x, py) - lc).length()
			if d <= radius:
				blocked_nodes.append(pid)
	var blocked_edges: Array[int] = []
	for gate: Dictionary in w.buildings.with_special("sluice"):
		if not w.buildings.is_working(gate):
			continue
		var gc: Vector2i = gate["cell"] as Vector2i
		var lid: int = w.terrain.ladder_id_at(gc.x, int(gate["mark"]))
		if lid >= 0:
			blocked_edges.append(lid)
	blocked_nodes.sort()
	blocked_edges.sort()
	_blocked_ladders = blocked_edges
	w.terrain.rebuild_wet_graph(w.tide.level, blocked_nodes, blocked_edges)

func _tick_creature(c: Dictionary, w: SimWorld) -> void:
	if bool(c["leaving"]):
		_move_towards(c, int(c["spawn_platform"]),
			float(int(w.terrain.platforms[int(c["spawn_platform"])]["x1"])), w)
		return
	if int(c["target_id"]) < 0 or not _target_valid(c, w):
		_pick_target(c, w)
	if int(c["target_id"]) < 0:
		# Целей в воде нет — бродит у спавна. Это не сбой, а заслуженный
		# итог планировки игрока.
		return
	var b: Dictionary = w.buildings.buildings.get(int(c["target_id"]), {})
	if b.is_empty():
		c["target_id"] = -1
		return
	var goal_platform: int = w.terrain.platform_at(BuildingSystem.storage_cell(b))
	var goal_x: float = float((b["cell"] as Vector2i).x)
	if int(c["platform"]) != goal_platform or absf(float(c["x"]) - goal_x) > 0.5:
		_move_towards(c, goal_platform, goal_x, w)
		return
	_act_on_target(c, b, w)

func _target_valid(c: Dictionary, w: SimWorld) -> bool:
	var b: Dictionary = w.buildings.buildings.get(int(c["target_id"]), {})
	if b.is_empty():
		return false
	return Balance.is_mark_flooded(int(b["mark"]), w.tide.level)

## Цель — ближайшая затопленная постройка. Никакого рандома: поведение
## определяет ТИП цели (docs/00 §9.3).
func _pick_target(c: Dictionary, w: SimWorld) -> void:
	var best: int = -1
	var best_d: float = INF
	for id: int in w.buildings.order:
		var b: Dictionary = w.buildings.buildings[id]
		if not Balance.is_mark_flooded(int(b["mark"]), w.tide.level):
			continue
		var pid: int = w.terrain.platform_at(BuildingSystem.storage_cell(b))
		if pid < 0 or not w.terrain.is_wet_node(pid):
			continue
		if pid != int(c["platform"]) \
				and w.terrain.find_wet_path(int(c["platform"]), pid).is_empty():
			continue
		var d: float = absf(float((b["cell"] as Vector2i).x) - float(c["x"])) \
			+ absf(float(int(b["mark"]) - _creature_mark(c, w))) * float(Balance.TILES_PER_MARK)
		if d < best_d or (is_equal_approx(d, best_d) and id < best):
			best_d = d
			best = id
	c["target_id"] = best
	c["gnaw_ticks"] = 0

func _creature_mark(c: Dictionary, w: SimWorld) -> int:
	return int(w.terrain.platforms[int(c["platform"])]["mark"])

## Склад — украсть стак и уйти; всё остальное — грызть, пока не сломает.
func _act_on_target(c: Dictionary, b: Dictionary, w: SimWorld) -> void:
	var special: String = DB.building(str(b["def_id"])).special
	if special == "storage":
		var sid: int = w.storage.storage_at(BuildingSystem.storage_cell(b))
		var stacks: Array = w.storage.storages[w.storage.storage_index(sid)]["stacks"] \
			as Array if sid >= 0 else []
		if sid < 0 or stacks.is_empty():
			c["target_id"] = -1
			return
		var idx: int = w.rng.randi_range(0, stacks.size() - 1)
		var stolen: Dictionary = (stacks[idx] as Dictionary).duplicate()
		var got: Array[Dictionary] = w.storage.take(sid, str(stolen["item_id"]),
			int(stolen["count"]), false)
		var n: int = 0
		for st: Dictionary in got:
			n += int(st["count"])
		_stolen_cycle[str(stolen["item_id"])] = int(
			_stolen_cycle.get(str(stolen["item_id"]), 0)) + n
		c["carrying"] = {"item_id": str(stolen["item_id"]), "count": n}
		c["leaving"] = true
		w.agents.on_storage_flooded()      # кража бьёт по духу так же, как потоп
		return
	c["gnaw_ticks"] = int(c["gnaw_ticks"]) + 1
	if int(c["gnaw_ticks"]) < int(Balance.CREATURE_GNAW_SEC * Balance.TICKS_PER_SEC):
		return
	c["gnaw_ticks"] = 0
	_damage_cycle += 1
	if w.buildings.apply_damage(int(b["id"]), w):
		c["target_id"] = -1                # сломал — ищет следующую

## Плавание по мокрому графу: по площадке — в x, между ярусами — через
## колонку лестницы (ребро графа), иначе шлюз ничего не перекрывал бы.
func _move_towards(c: Dictionary, goal_platform: int, goal_x: float, w: SimWorld) -> void:
	var step: float = Balance.CREATURE_SPEED / float(Balance.TICKS_PER_SEC)
	if int(c["climb_to"]) >= 0:
		c["climb_t"] = Balance.quant(float(c["climb_t"])
			+ step / float(Balance.TILES_PER_MARK))
		if float(c["climb_t"]) >= 1.0:
			c["platform"] = int(c["climb_to"])
			c["climb_to"] = -1
			c["climb_t"] = 0.0
		return
	if int(c["platform"]) == goal_platform:
		_step_x(c, goal_x, step)
		return
	var path: Array[int] = w.terrain.find_wet_path(int(c["platform"]), goal_platform)
	if path.size() < 2:
		c["target_id"] = -1
		return
	var next_id: int = path[1]
	var top: int = maxi(_creature_mark(c, w), int(w.terrain.platforms[next_id]["mark"]))
	var lx: int = _open_ladder_x(top, float(c["x"]), w)
	if lx < 0:
		c["target_id"] = -1
		return
	if absf(float(c["x"]) - float(lx)) > step:
		_step_x(c, float(lx), step)
		return
	c["x"] = float(lx)
	c["climb_to"] = next_id
	c["climb_t"] = 0.0

## Колонка лестницы между отметками top и top−1, ближайшая к существу.
##
## ⚠️ Перекрытые шлюзом лестницы пропускаются. Раньше бралась ПЕРВАЯ попавшаяся
## с нужной отметкой, и существо лезло по той самой лестнице, на которой стоит
## шлюз (SIM-05). Ребро графа при этом может остаться живым — если между теми же
## ярусами есть вторая, открытая лестница. Тогда существо честно обходит шлюз
## через неё, и это правило игры, а не дефект: чтобы запереть ярус, шлюзы нужны
## на всех его лестницах.
##
## Тай-брейк по меньшему id обязателен: при равном расстоянии порядок иначе
## не определён и два забега с одним сидом разойдутся.
func _open_ladder_x(top: int, from_x: float, w: SimWorld) -> int:
	var best_x: int = -1
	var best_id: int = -1
	var best_d: float = INF
	for l: Dictionary in w.terrain.ladders:
		if int(l["mark_top"]) != top or _blocked_ladders.has(int(l["id"])):
			continue
		var id: int = int(l["id"])
		var d: float = absf(from_x - float(int(l["x"])))
		if d < best_d or (is_equal_approx(d, best_d) and id < best_id):
			best_d = d
			best_id = id
			best_x = int(l["x"])
	return best_x

func _step_x(c: Dictionary, goal_x: float, step: float) -> void:
	var d: float = goal_x - float(c["x"])
	if absf(d) <= step:
		c["x"] = goal_x
		return
	c["x"] = Balance.quant(float(c["x"]) + step * signf(d))

## Существо рядом — минус дух, ОДИН раз за цикл на агента (иначе −10
## прилетало бы каждые десять тиков).
##
## ⚠️ Радиус духа — CREATURE_FEAR_TILES для ВСЕХ (docs/00 §6.3: «существо
## в пределах 4 тайлов −10»). Раньше здесь стоял panic_range, и черта Пугливый
## работала как «шире радиус минус-духа» — то есть чистый штраф без обещанной
## паники. Сам panic_range теперь означает ровно то, что называется:
## дистанцию, с которой Пугливый впадает в PANIC (AgentSystem._creature_panic).
func _scare_agents(w: SimWorld) -> void:
	for a: SimAgent in w.agents.agents:
		if not a.is_alive() or a.scared_this_cycle:
			continue
		if not creature_within(a, w, Balance.CREATURE_FEAR_TILES):
			continue
		a.scared_this_cycle = true
		a.change_need("mood", -Balance.MOOD_CREATURE_MILLI)

## Есть ли существо в range_tiles от агента. Метрика — манхэттен по клеткам,
## одна на весь испуг: и минус дух, и паника обязаны мерить одинаково.
func creature_within(a: SimAgent, w: SimWorld, range_tiles: float) -> bool:
	if creatures.is_empty() or range_tiles <= 0.0:
		return false
	var cell: Vector2i = w.agents.agent_cell(a, w)
	for c: Dictionary in creatures:
		var cy: int = Balance.mark_to_floor_cell_y(_creature_mark(c, w))
		var d: float = absf(float(cell.x) - float(c["x"])) \
			+ absf(float(cell.y - cy))
		if d <= range_tiles:
			return true
	return false

# --- Итог цикла -----------------------------------------------------------

func on_cycle_ended(w: SimWorld) -> Dictionary:
	# Шторм пережит без поломок и смертей — колония приободрилась.
	if is_active(SimTypes.CrisisType.STORM) and _damage_cycle == 0 and _storm_deaths == 0:
		for a: SimAgent in w.agents.agents:
			if a.is_alive():
				a.change_need("mood", Balance.MOOD_STORM_SURVIVED_MILLI)
	var report: Dictionary = {
		"crises": active.duplicate(),
		"damage": _damage_cycle,
		"stolen": _stolen_cycle.duplicate(),
		"storm_deaths": _storm_deaths,
	}
	_damage_cycle = 0
	_stolen_cycle.clear()
	_storm_deaths = 0
	return report

func drain_events() -> Array[SimEvent]:
	var out: Array[SimEvent] = _pending
	_pending = []
	return out

# --- Сериализация ---------------------------------------------------------

func to_dict() -> Dictionary:
	var list: Array = []
	for c: Dictionary in creatures:
		list.append({
			"id": int(c["id"]), "platform": int(c["platform"]), "x": float(c["x"]),
			"target_id": int(c["target_id"]), "gnaw": int(c["gnaw_ticks"]),
			"spawn": int(c["spawn_platform"]), "leaving": bool(c["leaving"]),
			"climb_to": int(c["climb_to"]), "climb_t": float(c["climb_t"]),
			"carrying": (c["carrying"] as Dictionary).duplicate(),
		})
	var stolen: Dictionary = {}
	var keys: Array[String] = []
	keys.assign(_stolen_cycle.keys())
	keys.sort()
	for k: String in keys:
		stolen[k] = int(_stolen_cycle[k])
	return {
		"creatures": list, "active": active.duplicate(),
		"announced": announced.duplicate(), "next_id": _next_creature_id,
		"damage": _damage_cycle, "stolen": stolen, "storm_deaths": _storm_deaths,
		"pending_visit": _pending_visit, "next_spring": next_spring_bonus,
		"spring_applied": _spring_applied,
	}

func from_dict(d: Dictionary) -> void:
	creatures.clear()
	for v: Variant in d.get("creatures", []) as Array:
		var s: Dictionary = v as Dictionary
		creatures.append({
			"id": int(s["id"]), "platform": int(s["platform"]), "x": float(s["x"]),
			"target_kind": "", "target_id": int(s["target_id"]),
			"target_cell": Vector2i.ZERO, "gnaw_ticks": int(s["gnaw"]),
			"spawn_platform": int(s["spawn"]), "leaving": bool(s["leaving"]),
			"climb_to": int(s["climb_to"]), "climb_t": float(s["climb_t"]),
			"carrying": (s.get("carrying", {}) as Dictionary).duplicate(),
		})
	active.clear()
	for av: Variant in d.get("active", []) as Array:
		active.append(int(av))
	announced.clear()
	for nv: Variant in d.get("announced", []) as Array:
		announced.append(int(nv))
	_next_creature_id = int(d.get("next_id", 1))
	_damage_cycle = int(d.get("damage", 0))
	_stolen_cycle.clear()
	for k: Variant in d.get("stolen", {}) as Dictionary:
		_stolen_cycle[str(k)] = int((d["stolen"] as Dictionary)[k])
	_storm_deaths = int(d.get("storm_deaths", 0))
	_pending_visit = int(d.get("pending_visit", 0))
	next_spring_bonus = float(d.get("next_spring", 0.0))
	_spring_applied = bool(d.get("spring_applied", false))
	_pending.clear()
