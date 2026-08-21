class_name JobSystem
extends RefCounted
## Утилитарный ИИ: задачи порождает МИР, а не агент (модель The Sims —
## объекты «рекламируют» полезность), конфликты решает резервирование
## (модель RimWorld). Агент только выбирает из готового пула.
##
## Почему так: иначе каждый агент сканирует весь мир каждый тик —
## O(агенты × мир) вместо O(мир) + O(агенты × задачи) (research/16 §1).

## id -> задача. Поля: class, kind, cell, platform, base, taken_by,
## item_id, n, from_*, to_* — см. _make_job.
var jobs: Dictionary[int, Dictionary] = {}
## Детерминированный порядок обхода: словарь порядка вставки не гарантирует.
var order: Array[int] = []
var beacon_cell: Vector2i = Balance.NO_BEACON

var _next_id: int = 1
var _dirty: bool = true
## Кэш длин путей между площадками, инвалидируется по версии графа.
var _dist_cache: Dictionary[int, float] = {}
var _dist_cache_gv: int = -1
var _pending: Array[SimEvent] = []
## Добыто за текущий цикл: item_id -> count. Уходит в итог цикла.
var _gathered_cycle: Dictionary[String, int] = {}

func mark_dirty() -> void:
	_dirty = true

func new_run() -> void:
	jobs.clear()
	order.clear()
	_next_id = 1
	_dirty = true
	_dist_cache.clear()
	_dist_cache_gv = -1
	_pending.clear()
	_gathered_cycle.clear()
	beacon_cell = Balance.NO_BEACON

# --- Тик ------------------------------------------------------------------

func tick(w: SimWorld) -> void:
	if _dirty:
		_rebuild(w)
		_dirty = false
	_check_auto_recall(w)
	_assign(w)

## Пул пересобирается ПО СОБЫТИЯМ, а не каждый тик. Взятые задачи переносятся
## как есть: иначе агент с грузом в руках потерял бы задачу на полпути
## и завис (research/16 §2).
func _rebuild(w: SimWorld) -> void:
	var kept: Dictionary[int, Dictionary] = {}
	for id: int in order:
		var j: Dictionary = jobs[id]
		if int(j["taken_by"]) != -1 and _still_valid(j, w):
			kept[id] = j
	jobs = kept
	_generate_gather(w)
	_generate_haul(w)
	_generate_needs(w)
	_reorder()
	_assign_gear(w)

func _reorder() -> void:
	order.clear()
	order.assign(jobs.keys())
	order.sort()

# --- Генерация задач ------------------------------------------------------

func _make_job(job_class: int, kind: String, cell: Vector2i, w: SimWorld) -> Dictionary:
	var id: int = _next_id
	_next_id += 1
	var j: Dictionary = {
		"id": id, "class": job_class, "kind": kind,
		"cell": cell, "platform": w.terrain.platform_at(cell),
		"base": float(Balance.JOB_BASE[job_class]),
		"taken_by": -1, "item_id": "", "n": 0,
		"target_id": -1, "to_cell": cell, "to_id": -1,
		# Общая задача: её могут исполнять несколько агентов сразу.
		# Склад кормит всю колонию, очаг греет всех — резервировать их значит
		# отправить обедать ровно одного и оставить пятерых голодными.
		"shared": false,
	}
	jobs[id] = j
	return j

func _has_job_for(kind: String, target_id: int) -> bool:
	for id: int in jobs:
		var j: Dictionary = jobs[id]
		if str(j["kind"]) == kind and int(j["target_id"]) == target_id:
			return true
	return false

## Непустой достижимый депозит «рекламирует» добычу.
## Безопасность (успеет ли агент вернуться) НЕ проверяется: за риск отвечает
## игрок политиками Жадность и Осторожность — в этом вся игра.
func _generate_gather(w: SimWorld) -> void:
	for d: Dictionary in w.terrain.deposits:
		if int(d["amount"]) <= 0:
			continue
		var id: int = int(d["id"])
		if _has_job_for("gather", id):
			continue
		var cell: Vector2i = d["cell"] as Vector2i
		if w.terrain.platform_at(cell) < 0:
			continue
		var j: Dictionary = _make_job(SimTypes.JobClass.GATHER, "gather", cell, w)
		j["target_id"] = id
		var def: Dictionary = Balance.DEPOSIT_KINDS[str(d["kind"])] as Dictionary
		j["item_id"] = str(def["item"])

## Предмет на земле «рекламирует» переноску на ближайший склад со слотом.
func _generate_haul(w: SimWorld) -> void:
	for i: int in w.storage.ground.size():
		var g: Dictionary = w.storage.ground[i]
		var cell: Vector2i = g["cell"] as Vector2i
		var key: int = _cell_key(cell)
		if _has_job_for("haul_ground", key):
			continue
		if w.terrain.platform_at(cell) < 0:
			continue
		var dest: int = _nearest_storage_with_room(w, cell)
		if dest < 0:
			continue
		var j: Dictionary = _make_job(SimTypes.JobClass.HAUL, "haul_ground", cell, w)
		j["target_id"] = key
		j["item_id"] = str((g["stack"] as Dictionary)["item_id"])
		j["to_id"] = dest
		j["to_cell"] = w.storage.storages[w.storage.storage_index(dest)]["cell"]

## Потребности тоже «рекламируются»: еда — складом с провизией, отдых —
## жилой площадкой. Кому это нужно, решает скоринг (urgency у каждого свой).
func _generate_needs(w: SimWorld) -> void:
	for s: Dictionary in w.storage.storages:
		var sid: int = int(s["id"])
		if w.storage.count_in(sid, "rations") <= 0 and w.storage.count_in(sid, "catch") <= 0:
			continue
		if _has_job_for("eat", sid):
			continue
		var j: Dictionary = _make_job(SimTypes.JobClass.EAT, "eat", s["cell"] as Vector2i, w)
		j["target_id"] = sid
		j["shared"] = true
	# Отдых — у источника тепла: коек ещё нет (этап 07), очаг заменяет.
	for h: Vector2i in w.heat_sources():
		var key: int = _cell_key(h)
		if _has_job_for("rest", key):
			continue
		if w.terrain.platform_at(h) < 0:
			continue
		var j2: Dictionary = _make_job(SimTypes.JobClass.REST, "rest", h, w)
		j2["target_id"] = key
		j2["shared"] = true

static func _cell_key(cell: Vector2i) -> int:
	return cell.x * 10000 + cell.y

func _nearest_storage_with_room(w: SimWorld, from_cell: Vector2i) -> int:
	var best: int = -1
	var best_d: float = INF
	for s: Dictionary in w.storage.storages:
		if (s["stacks"] as Array).size() >= int(s["capacity"]):
			continue
		var c: Vector2i = s["cell"] as Vector2i
		var d: float = absf(float(c.x - from_cell.x)) + absf(float(c.y - from_cell.y))
		# Тай-брейк по меньшему id: при равном расстоянии выбор иначе не определён.
		if d < best_d or (is_equal_approx(d, best_d) and int(s["id"]) < best):
			best_d = d
			best = int(s["id"])
	return best

# --- Валидность и резервирование ------------------------------------------

func _still_valid(j: Dictionary, w: SimWorld) -> bool:
	match str(j["kind"]):
		"gather":
			var i: int = w.terrain.deposit_index(int(j["target_id"]))
			return i >= 0 and int(w.terrain.deposits[i]["amount"]) > 0 \
				and _is_dry(j["cell"] as Vector2i, w)
		"haul_ground":
			# Носильщик с грузом в руках доносит его при любой воде.
			if _carrier_holds(j, w):
				return true
			return not w.storage.ground_at(j["cell"] as Vector2i).is_empty() \
				and _is_dry(j["cell"] as Vector2i, w)
		"eat":
			var sid: int = int(j["target_id"])
			return w.storage.storage_index(sid) >= 0
		"rest":
			return true
	return true

## Носильщик уже подобрал груз — задача жива, пока он не донёс.
func _carrier_holds(j: Dictionary, w: SimWorld) -> bool:
	var owner: int = int(j["taken_by"])
	if owner < 0:
		return false
	var a: SimAgent = w.agents.agent(owner)
	return a != null and a.is_alive() and not a.bag.is_empty()

func release(a: SimAgent) -> void:
	if a.job_id == -1:
		return
	var j: Dictionary = jobs.get(a.job_id, {})
	if not j.is_empty():
		j["taken_by"] = -1
	a.job_id = -1

func _claim(a: SimAgent, job_id: int) -> void:
	release(a)
	jobs[job_id]["taken_by"] = a.id
	a.job_id = job_id

## Задачи погибшего освобождаются в тот же тик.
func on_agent_died(a: SimAgent) -> void:
	release(a)
	mark_dirty()

# --- Назначение -----------------------------------------------------------

## Порядок агентов строго по id: кто выбирает первым, тот берёт лучшую задачу,
## и этот порядок обязан быть одинаковым между прогонами.
func _assign(w: SimWorld) -> void:
	for a: SimAgent in w.agents.agents:
		if not a.is_alive():
			continue
		if a.job_id != -1:
			# Задача могла стать невалидной — тогда агент освобождается,
			# а не идёт в пустоту.
			var cur: Dictionary = jobs.get(a.job_id, {})
			if cur.is_empty() or not _still_valid(cur, w):
				release(a)
				w.agents.abandon_job(a, w)
			continue
		if not w.agents.can_take_job(a):
			continue
		var best: int = _best_job_for(a, w)
		if best < 0:
			continue
		# Общие задачи не резервируются: агент просто идёт их делать.
		if not bool(jobs[best].get("shared", false)):
			_claim(a, best)
		w.agents.start_job(a, jobs[best], w)

func _best_job_for(a: SimAgent, w: SimWorld) -> int:
	var best_id: int = -1
	var best_s: int = 0
	for id: int in order:
		var j: Dictionary = jobs.get(id, {})
		if j.is_empty() or int(j["taken_by"]) != -1:
			continue
		if not _applies_to(a, j, w):
			continue
		if not _greed_allows(a, j, w):
			continue
		if not _reachable(a, j, w):
			continue
		var s: int = score(a, j, w)
		# СТРОГО больше: при ничьей выигрывает меньший id — тай-брейк бесплатный
		# и тотальный, без sort_custom (тот в Godot не стабилен).
		if s > best_s:
			best_s = s
			best_id = id
	return best_id

## Кому эта задача вообще имеет смысл.
func _applies_to(a: SimAgent, j: Dictionary, w: SimWorld) -> bool:
	match str(j["kind"]):
		"eat":
			return int(a.needs["satiety"]) < Balance.EAT_WANT_MILLI
		"rest":
			# Отдых — только на Высокой воде (docs/00 §6.6).
			return w.clock.phase == SimTypes.Phase.HIGH \
				and int(a.needs["fatigue"]) < Balance.REST_WANT_MILLI
		"gather":
			if a.bag_free_slots() <= 0:
				return false
			if not _is_dry(j["cell"] as Vector2i, w):
				return false
			# Боязнь глубины: черта запрещает спускаться ниже своей отметки.
			var min_mark: float = a.modifier("min_mark", -99.0)
			return float(Balance.cell_to_mark(j["cell"] as Vector2i)) >= min_mark
		"haul_ground":
			return a.bag_free_slots() > 0 and _is_dry(j["cell"] as Vector2i, w)
	return true

## Цель ПОД ВОДОЙ прямо сейчас — не «риск», а бессмыслица: под водой не
## добывают, и агент просто утонет по дороге. Риск, за который отвечает игрок
## политиками, — это «успею ли вернуться», а не «не захлебнусь ли сразу».
## Без этой проверки колония уходила на дно в первые секунды Спада, пока вода
## ещё стояла, и вымирала к восьмому циклу.
func _is_dry(cell: Vector2i, w: SimWorld) -> bool:
	return not w.terrain.is_flooded(cell, w.tide.level)

## Жадность — ФИЛЬТР, а не штраф: приёмка требует бинарного «никто не берёт
## дальше N тайлов от лестниц».
func _greed_allows(a: SimAgent, j: Dictionary, w: SimWorld) -> bool:
	var limit: int = Balance.GREED_LADDER_LIMIT[w.policies.get_value(SimTypes.Policy.GREED)]
	if limit < 0:
		return true
	# На жилом утёсе лимит не действует: он про риск на дне.
	if Balance.cell_to_mark(j["cell"] as Vector2i) >= 0:
		return true
	return w.terrain.nearest_ladder_dist(j["cell"] as Vector2i) <= float(limit)

func _reachable(a: SimAgent, j: Dictionary, w: SimWorld) -> bool:
	var pid: int = int(j["platform"])
	if pid < 0:
		return false
	if pid == a.platform_id:
		return true
	return not w.terrain.find_path(a.platform_id, pid).is_empty()

# --- Скоринг --------------------------------------------------------------

## score = policy_weight × base × urgency ÷ (1 + 0.1 × dist), затем маяк,
## затем черты (docs/00 §6.5). Порядок множителей ФИКСИРОВАН: перестановка
## даёт другой float и другой выбор при близких скорах.
##
## Результат квантуется в целое «в сотых»: это снимает float-дрожь и делает
## сравнение тотальным без sort_custom (research/11 §1.1).
func score(a: SimAgent, j: Dictionary, w: SimWorld) -> int:
	var weight: float = w.policies.weight_for_class(int(j["class"]))
	if weight <= 0.0:
		return -1                                   # класс запрещён политикой
	var base: float = float(j["base"])
	if str(j["kind"]) == "eat" and int(a.needs["satiety"]) < Balance.NEED_LOW_ENTER_MILLI:
		base = Balance.JOB_BASE_EAT_STARVING
	var s: float = weight * base * _urgency(a, j, w) / (1.0 + 0.1 * _dist_tiles(a, j, w))
	if _in_beacon_radius(j):
		s *= Balance.BEACON_BONUS
	s *= a.modifier("work_mult")
	return int(round(s * 100.0))

func _urgency(a: SimAgent, j: Dictionary, w: SimWorld) -> float:
	var u: float = 1.0
	if str(j["kind"]) == "haul_ground":
		var def: ItemDef = DB.item(str(j["item_id"]))
		if def != null and def.spoil_cycles > 0:
			u *= Balance.URGENCY_PERISHABLE
		# Груз ниже будущего уровня воды на Сигнале — забрать сейчас или никогда.
		if w.clock.phase == SimTypes.Phase.SIGNAL \
				and Balance.is_mark_flooded(Balance.cell_to_mark(j["cell"] as Vector2i),
					Balance.SIGNAL_LEVEL):
			u *= Balance.URGENCY_BELOW_WATER_IN_SIGNAL
	return u

## Радиус маяка — ЕВКЛИДОВ, в отличие от dist в скоринге.
## Причина не техническая, а игроцкая: игрок видит на экране круг радиусом 12
## и ждёт, что бонус внутри круга. Путь по графу дал бы «дырявый» круг.
func _in_beacon_radius(j: Dictionary) -> bool:
	if beacon_cell == Balance.NO_BEACON:
		return false
	var d: Vector2 = Vector2(j["cell"] as Vector2i) - Vector2(beacon_cell)
	return d.length() <= Balance.BEACON_RADIUS

## Расстояние — длина пути ПО ГРАФУ: агент на +6 и депозит на −8 могут быть
## рядом по X и в сорока тайлах по лестницам.
func _dist_tiles(a: SimAgent, j: Dictionary, w: SimWorld) -> float:
	if _dist_cache_gv != w.terrain.graph_version:
		_dist_cache.clear()
		_dist_cache_gv = w.terrain.graph_version
	var pid: int = int(j["platform"])
	var horizontal: float = absf(a.x - float((j["cell"] as Vector2i).x))
	if pid == a.platform_id:
		return horizontal
	var key: int = a.platform_id * 1000 + pid
	if _dist_cache.has(key):
		return float(_dist_cache[key]) + horizontal
	var d: float = w.terrain.path_length_tiles(w.terrain.find_path(a.platform_id, pid))
	_dist_cache[key] = d
	return d + horizontal

# --- Авто-возврат Осторожности --------------------------------------------

## Осторожность — не фильтр задач, а таймер. Только для тех, кто НИЖЕ нуля:
## иначе она загонит домой и тех, кто и так наверху (research/16 §6).
func _check_auto_recall(w: SimWorld) -> void:
	if w.clock.phase != SimTypes.Phase.SIGNAL:
		return
	var lead: int = Balance.CAUTION_LEAD_SEC[w.policies.get_value(SimTypes.Policy.CAUTION)]
	var left: int = w.clock.ticks_left_in_phase()
	for a: SimAgent in w.agents.agents:
		if not a.is_alive() or a.recalled:
			continue
		if w.agents.agent_mark_f(a, w) >= 0.0:
			continue
		var personal: int = lead
		if int(a.needs["mood"]) < Balance.NEED_LOW_ENTER_MILLI:
			personal += Balance.PANIC_RECALL_BONUS_SEC
		if left > personal * Balance.TICKS_PER_SEC:
			continue
		release(a)
		w.agents.force_return(a, w)

# --- Снаряжение -----------------------------------------------------------

## Снаряжение выдаётся автоматически тому, кто больше всех работал на глубине
## за цикл (docs/00 §7). При равенстве — больший id: тай-брейк обязан быть.
func _assign_gear(w: SimWorld) -> void:
	var total: int = 0
	for s: Dictionary in w.storage.storages:
		total += w.storage.count_in(int(s["id"]), "gear")
	if total <= 0:
		return
	var best: SimAgent = null
	for a: SimAgent in w.agents.agents:
		if not a.is_alive() or a.has_gear or a.bag_free_slots() <= 0:
			continue
		if best == null or a.deep_gathered > best.deep_gathered \
				or (a.deep_gathered == best.deep_gathered and a.id > best.id):
			best = a
	if best == null:
		return
	for s2: Dictionary in w.storage.storages:
		var got: Array[Dictionary] = w.storage.take(int(s2["id"]), "gear", 1)
		if got.is_empty():
			continue
		best.has_gear = true
		best.recompute_from_traits()
		_pending.append(SimEvent.make("agent_updated", {"id": best.id}))
		return

# --- Добыча ---------------------------------------------------------------

## Записывает добытое: и в отчёт цикла, и в «глубинную полезность» агента.
func note_gathered(a: SimAgent, item_id: String, n: int, mark: int) -> void:
	_gathered_cycle[item_id] = int(_gathered_cycle.get(item_id, 0)) + n
	if mark <= Balance.RELIC_MARK_MAX + 2:      # −5 и глубже
		a.deep_gathered += n

func on_cycle_started() -> void:
	_gathered_cycle.clear()
	mark_dirty()

func on_cycle_ended() -> Dictionary:
	return {"gathered": _gathered_cycle.duplicate()}

func queue_event(e: SimEvent) -> void:
	_pending.append(e)

func drain_events() -> Array[SimEvent]:
	var out: Array[SimEvent] = _pending
	_pending = []
	return out

# --- Интерфейс для этапов 07/08 -------------------------------------------

## Заказ переноски со стороны стройки/станции. Дедупликация обязательна:
## без неё BuildingSystem каждый тик видит «не хватает 4 утиля» и за десять
## тиков нагенерит десять задач (research/16 §9).
func request_haul(from: Dictionary, to: Dictionary, item_id: String, n: int,
		w: SimWorld) -> int:
	var key: int = _cell_key(to["cell"] as Vector2i) * 31 + item_id.hash() % 31
	if _has_job_for("haul_request", key):
		return -1
	var j: Dictionary = _make_job(SimTypes.JobClass.HAUL, "haul_request",
		from["cell"] as Vector2i, w)
	j["target_id"] = key
	j["item_id"] = item_id
	j["n"] = n
	j["to_id"] = int(to.get("id", -1))
	j["to_cell"] = to["cell"]
	_reorder()
	return int(j["id"])

func cancel_haul(job_id: int) -> void:
	if not jobs.has(job_id):
		return
	jobs.erase(job_id)
	_reorder()
	mark_dirty()

# --- Сериализация ---------------------------------------------------------
# Пул сериализуется целиком: сброс задач на загрузке был бы проще, но нарушил
# бы приёмку этапа 11 «симуляция продолжается детерминированно».

func to_dict() -> Dictionary:
	var list: Array = []
	for id: int in order:
		var j: Dictionary = jobs[id]
		list.append({
			"id": int(j["id"]), "class": int(j["class"]), "kind": str(j["kind"]),
			"cell": SimTypes.v2i_to_arr(j["cell"] as Vector2i),
			"platform": int(j["platform"]), "base": j["base"],
			"taken_by": int(j["taken_by"]), "item_id": str(j["item_id"]),
			"n": int(j["n"]), "target_id": int(j["target_id"]),
			"to_cell": SimTypes.v2i_to_arr(j["to_cell"] as Vector2i),
			"to_id": int(j["to_id"]), "shared": bool(j["shared"]),
		})
	var gathered: Dictionary = {}
	var keys: Array[String] = []
	keys.assign(_gathered_cycle.keys())
	keys.sort()
	for k: String in keys:
		gathered[k] = int(_gathered_cycle[k])
	return {
		"next_id": _next_id, "jobs": list, "gathered": gathered,
		"beacon": SimTypes.v2i_to_arr(beacon_cell), "dirty": _dirty,
	}

func from_dict(d: Dictionary) -> void:
	jobs.clear()
	for v: Variant in d.get("jobs", []) as Array:
		var s: Dictionary = v as Dictionary
		jobs[int(s["id"])] = {
			"id": int(s["id"]), "class": int(s["class"]), "kind": str(s["kind"]),
			"cell": SimTypes.arr_to_v2i(s["cell"] as Array),
			"platform": int(s["platform"]), "base": float(s["base"]),
			"taken_by": int(s["taken_by"]), "item_id": str(s["item_id"]),
			"n": int(s["n"]), "target_id": int(s["target_id"]),
			"to_cell": SimTypes.arr_to_v2i(s["to_cell"] as Array),
			"to_id": int(s["to_id"]), "shared": bool(s.get("shared", false)),
		}
	_next_id = int(d.get("next_id", 1))
	_gathered_cycle.clear()
	for k: Variant in d.get("gathered", {}) as Dictionary:
		_gathered_cycle[str(k)] = int((d["gathered"] as Dictionary)[k])
	beacon_cell = SimTypes.arr_to_v2i(d.get("beacon", [-9999, -9999]) as Array)
	_reorder()
	# ⚠️ НЕ ставить _dirty = true принудительно: пересборка выдала бы свободным
	# задачам новые id из _next_id, а в непрерывном прогоне они сохранили бы
	# старые — и продолжение после загрузки разошлось бы.
	_dirty = bool(d.get("dirty", false))
	_dist_cache.clear()
	_dist_cache_gv = -1
	_pending.clear()
