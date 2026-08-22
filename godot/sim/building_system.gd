class_name BuildingSystem
extends RefCounted
## Постройки: размещение, стройка, износ, затопление, шторм, снос (docs/00 §8).
##
## Состояние постройки — три состояния плюс два ОРТОГОНАЛЬНЫХ флага:
## ACTIVE + flooded + damaged бывает одновременно, и правила у каждой
## комбинации свои (затопленный горн не работает, но чинить его можно;
## сломанная лестница снимает ребро независимо от воды).

## id -> постройка. Поля: def_id, cell, mark, state, flooded, damaged, hp,
## progress_ticks, buffer, pending_jobs, edge_id, lit, fuel_left.
var buildings: Dictionary[int, Dictionary] = {}
## Детерминированный порядок обхода.
var order: Array[int] = []

var _next_id: int = 1
## cell -> building_id. Проверка размещения через словарь занятости, а не
## перебором всех построек: призрак размещения дёргает её каждый кадр.
var _occupied: Dictionary[Vector2i, int] = {}
var _last_level: float = Balance.HIGH_LEVEL
var _pending: Array[SimEvent] = []

# --- Забег ----------------------------------------------------------------

func new_run(w: SimWorld, cliff: CliffDef) -> void:
	buildings.clear()
	order.clear()
	_occupied.clear()
	_next_id = 1
	_last_level = Balance.HIGH_LEVEL
	_pending.clear()
	for b: Dictionary in cliff.start_buildings:
		var id: int = place(str(b["def_id"]), b["cell"] as Vector2i, w, true)
		if id < 0:
			push_warning("стартовая постройка %s не встала в %s"
				% [str(b["def_id"]), str(b["cell"])])
	_pending.clear()                     # старт — не «изменение» для UI

# --- Размещение -----------------------------------------------------------

## "" — можно ставить. Иначе ключ локализации с причиной: этап 14 получает
## подсказку «почему красный» бесплатно, вместо переписывания на 14-м.
func place_error(def_id: String, cell: Vector2i, w: SimWorld) -> String:
	var d: BuildingDef = DB.building(def_id)
	if d == null:
		return "ERR_OCCUPIED"
	if not d.buildable:
		return "ERR_NOT_BUILDABLE"
	if not d.unlock_id.is_empty() and not w.unlocked.has(d.unlock_id):
		return "ERR_LOCKED"
	# Лестница живёт не на сетке, а на ребре графа: у неё своя проверка.
	# Планы в графе ещё не лежат, поэтому колонку проверяем и по ним (R7):
	# иначе два плана в одну колонку проходят оба, второй достраивается
	# с edge_id = −1, и вложенные в него материалы уходят в никуда.
	if d.special == "ladder":
		if _planned_ladder_at(cell) >= 0:
			return "ERR_NO_LADDER_SPOT"
		return "" if w.terrain.can_place_ladder(cell) else "ERR_NO_LADDER_SPOT"
	var bottom: int = cell.y + d.size.y - 1
	var mark: int = Balance.cell_to_mark(Vector2i(cell.x, bottom))
	if mark < d.min_mark or mark > d.max_mark:
		return "ERR_MARK"
	# ⚠️ Шлюз перекрывает ЛЕСТНИЦУ и вне её колонки бессмыслен. Промах на одну
	# клетку давал молча не работающую постройку: игрок видел шлюз, существо
	# проходило мимо него, и понять причину было нельзя (SIM-05).
	if d.special == "sluice" and w.terrain.ladder_id_at(cell.x, mark) < 0:
		return "ERR_NO_LADDER"
	# «Кромка площадки» из docs/00 §8 у лебёдки в дефе не выражена, а корзина
	# живёт ярусом НИЖЕ механизма: без площадки под ней груз уезжает на клетку,
	# до которой не дойти, и носильщик встаёт там навсегда (R2).
	if d.special == "winch" and not w.terrain.is_solid_ground(
			Vector2i(cell.x, Balance.mark_to_floor_cell_y(mark - 1))):
		return "ERR_NO_BASKET_SPOT"
	for dx: int in d.size.x:
		for dy: int in d.size.y:
			if _occupied.has(cell + Vector2i(dx, dy)):
				return "ERR_OCCUPIED"
	# Опора проверяется под НИЖНИМ рядом. Классическая ошибка — проверить
	# под верхним углом и разрешить постройку, висящую в воздухе.
	for dx2: int in d.size.x:
		if not w.terrain.is_solid_ground(Vector2i(cell.x + dx2, bottom + 1)):
			return "ERR_NO_SUPPORT"
	return ""

## id ещё не достроенной лестницы в этой колонке, или −1.
func _planned_ladder_at(cell: Vector2i) -> int:
	for id: int in order:
		var b: Dictionary = buildings[id]
		if int(b["state"]) == int(SimTypes.BuildState.ACTIVE):
			continue
		var d: BuildingDef = DB.building(str(b["def_id"]))
		if d == null or d.special != "ladder":
			continue
		if (b["cell"] as Vector2i) == cell:
			return id
	return -1

func can_place(def_id: String, cell: Vector2i, w: SimWorld) -> bool:
	return place_error(def_id, cell, w).is_empty()

## Возвращает id постройки или −1. instant=true ставит сразу ACTIVE —
## так размещаются стартовые постройки забега и мизансцены тестов. Это же
## единственный путь для нестроящихся дефов (Дождесборник): игроку они
## недоступны, а на старте обязаны стоять (C2.4).
func place(def_id: String, cell: Vector2i, w: SimWorld, instant: bool = false) -> int:
	var err: String = place_error(def_id, cell, w)
	if not err.is_empty() and not (instant and err == "ERR_NOT_BUILDABLE"):
		return -1
	var d: BuildingDef = DB.building(def_id)
	var id: int = _next_id
	_next_id += 1
	var bottom: int = cell.y + d.size.y - 1
	var b: Dictionary = {
		"id": id, "def_id": def_id, "cell": cell,
		"mark": Balance.cell_to_mark(Vector2i(cell.x, bottom)),
		"state": int(SimTypes.BuildState.PLANNED),
		"flooded": false, "damaged": false, "hp": d.hp,
		"progress_ticks": 0, "buffer": {}, "pending_jobs": [] as Array[int],
		"edge_id": -1, "lit": false, "fuel_left": 0,
		# Игрок нажал «Починить»: ремонт этой постройки идёт вне очереди
		# (Balance.URGENCY_CRITICAL_REPAIR). Снимается по завершении ремонта.
		"repair_urgent": false,
		# Был ли затоплен хоть раз за фазу — нужно испарителю (этап 08):
		# соль не даёт цикл, в середине которого его накрыло.
		"flooded_in_phase": false,
	}
	buildings[id] = b
	_reorder()
	_occupy(b, true)
	# Флаг воды выставляем сразу: постройка, поставленная в уже затопленной
	# зоне, иначе считалась бы сухой до следующего ПЕРЕСЕЧЕНИЯ уровнем.
	if Balance.is_mark_flooded(int(b["mark"]), w.tide.level):
		b["flooded"] = true
		b["flooded_in_phase"] = true
		_on_flooded(b, w)
	if instant:
		_set_state(b, SimTypes.BuildState.ACTIVE, w)
	w.jobs.mark_dirty()
	_pending.append(SimEvent.make("building_placed", {"id": id}))
	return id

func _occupy(b: Dictionary, on: bool) -> void:
	var d: BuildingDef = DB.building(str(b["def_id"]))
	if d == null or d.special == "ladder":
		return                            # лестница занимает ребро, а не клетки
	var cell: Vector2i = b["cell"] as Vector2i
	for dx: int in d.size.x:
		for dy: int in d.size.y:
			var c: Vector2i = cell + Vector2i(dx, dy)
			if on:
				_occupied[c] = int(b["id"])
			else:
				_occupied.erase(c)

func _reorder() -> void:
	order.clear()
	order.assign(buildings.keys())
	order.sort()

## Клетка пола под постройкой — там стоит агент, который с ней работает.
static func storage_cell(b: Dictionary) -> Vector2i:
	var cell: Vector2i = b["cell"] as Vector2i
	return Vector2i(cell.x, Balance.mark_to_floor_cell_y(int(b["mark"])))

func building_at(cell: Vector2i) -> int:
	return int(_occupied.get(cell, -1))

## ЕДИНСТВЕННАЯ функция «работает ли постройка». Если каждая система выведет
## её сама, они рано или поздно разойдутся.
func is_working(b: Dictionary) -> bool:
	if int(b["state"]) != int(SimTypes.BuildState.ACTIVE):
		return false
	if bool(b["damaged"]):
		return false
	var d: BuildingDef = DB.building(str(b["def_id"]))
	if bool(b["flooded"]) and d.flood_rule == SimTypes.FloodRule.DISABLED:
		return false
	if d.special == "hearth" or d.special == "lantern":
		return bool(b["lit"])            # без топлива не горит
	return true

func with_special(special: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: int in order:
		var b: Dictionary = buildings[id]
		if DB.building(str(b["def_id"])).special == special:
			out.append(b)
	return out

# --- Тик ------------------------------------------------------------------

func tick(w: SimWorld) -> void:
	_update_flooding(w)
	for id: int in order:
		var b: Dictionary = buildings[id]
		if bool(b["damaged"]):
			_request_materials(b, w, repair_cost(DB.building(str(b["def_id"]))))
			continue
		if int(b["state"]) == int(SimTypes.BuildState.PLANNED):
			_request_materials(b, w, DB.building(str(b["def_id"])).cost)
			_try_start_construction(b, w)

## Затопление — событие ПЕРЕСЕЧЕНИЯ уровнем отметки, а не состояние: иначе
## правило применялось бы каждый тик, пока постройка под водой.
func _update_flooding(w: SimWorld) -> void:
	var level: float = w.tide.level
	if is_equal_approx(level, _last_level):
		return
	for id: int in order:
		var b: Dictionary = buildings[id]
		var mark: int = int(b["mark"])
		var was: bool = Balance.is_mark_flooded(mark, _last_level)
		var now: bool = Balance.is_mark_flooded(mark, level)
		if now == was:
			continue
		b["flooded"] = now
		if now:
			b["flooded_in_phase"] = true
			_on_flooded(b, w)
		_pending.append(SimEvent.make("building_state_changed", {"id": id}))
	_last_level = level

func _on_flooded(b: Dictionary, w: SimWorld) -> void:
	match DB.building(str(b["def_id"])).special:
		"evaporator":
			(b["buffer"] as Dictionary)["salt"] = 0     # соль смыло
		"hearth":
			b["lit"] = false                            # очаг залило
		"forge":
			# docs/00 §8: у горна затопление — «DISABLED + повреждение».
			# Он стоит на жилых ярусах, и накрыть его может только сизигия:
			# это и есть налог за станцию на низкой отметке (A1.3).
			apply_damage(int(b["id"]), w)
		_:
			pass                                        # лестницы, шлюз, фонарь — работают

func on_phase_started(_phase: int) -> void:
	for id: int in order:
		buildings[id]["flooded_in_phase"] = bool(buildings[id]["flooded"])

# --- Материалы и стройка --------------------------------------------------

## Заказ недостающего с учётом того, что УЖЕ едет. Без этого учёта постройка
## каждый тик просила бы полный комплект заново.
func _request_materials(b: Dictionary, w: SimWorld, cost: Dictionary) -> void:
	b["pending_jobs"] = MaterialRequester.prune(b["pending_jobs"] as Array[int], w)
	var have: Dictionary[String, int] = {}
	for k2: String in cost:
		have[k2] = buffer_count(b, k2, false)
	var need: Dictionary[String, int] = MaterialRequester.missing(
		cost, have, b["pending_jobs"] as Array[int], w)
	for k: String in need:
		if int(need[k]) <= 0:
			continue
		var src: Dictionary = MaterialRequester.source_for(k, w)
		if src.is_empty():
			continue                       # материала в колонии просто нет
		var jid: int = w.jobs.request_haul(src,
			{"kind": "building", "id": int(b["id"]), "cell": b["cell"]},
			k, int(need[k]), w)
		if jid != -1:
			(b["pending_jobs"] as Array[int]).append(jid)

## Принять материал (или вход станции) в буфер постройки.
func deliver(building_id: int, stack: Dictionary, w: SimWorld) -> int:
	var b: Dictionary = buildings.get(building_id, {})
	if b.is_empty():
		return int(stack["count"])
	var buf: Dictionary = b["buffer"] as Dictionary
	var key: String = StackUtil.buffer_key(str(stack["item_id"]), bool(stack["wet"]))
	buf[key] = int(buf.get(key, 0)) + int(stack["count"])
	w.jobs.mark_dirty()
	_pending.append(SimEvent.make("building_state_changed", {"id": building_id}))
	return 0

## Сколько нужного лежит в буфере. dry_only отсекает мокрое: горн его
## не принимает, а Сушила — наоборот, только его и ждут.
static func buffer_count(b: Dictionary, item_id: String, dry_only: bool) -> int:
	var buf: Dictionary = b["buffer"] as Dictionary
	var n: int = int(buf.get(item_id, 0))
	if not dry_only:
		n += int(buf.get(StackUtil.buffer_key(item_id, true), 0))
	return n

## Списывает из буфера, тратя сначала мокрое (если оно вообще годится):
## сухое ценнее, оно горит.
static func buffer_take(b: Dictionary, item_id: String, n: int, dry_only: bool) -> int:
	var buf: Dictionary = b["buffer"] as Dictionary
	var left: int = n
	# Тернарник вернул бы нетипизированный Array и уронил присваивание
	# в Array[String] (SCRIPT ERROR в рантайме). Обычный if типизацию сохраняет.
	var order: Array[String] = []
	if dry_only:
		order = [item_id]
	else:
		order = [StackUtil.buffer_key(item_id, true), item_id]
	for key: String in order:
		if left <= 0:
			break
		var have: int = int(buf.get(key, 0))
		var take_n: int = mini(have, left)
		if take_n <= 0:
			continue
		buf[key] = have - take_n
		if int(buf[key]) <= 0:
			buf.erase(key)
		left -= take_n
	return n - left

func _try_start_construction(b: Dictionary, w: SimWorld) -> void:
	var d: BuildingDef = DB.building(str(b["def_id"]))
	for k: String in d.cost:
		# Стройке всё равно, мокрое дерево или сухое: сушить его будет очаг.
		if buffer_count(b, k, false) < int(d.cost[k]):
			return
	_set_state(b, SimTypes.BuildState.UNDER_CONSTRUCTION, w)
	w.jobs.mark_dirty()

## Один тик работы строителя. Возвращает true, когда постройка готова.
func advance_construction(building_id: int, ticks: int, w: SimWorld) -> bool:
	var b: Dictionary = buildings.get(building_id, {})
	if b.is_empty():
		return true
	var d: BuildingDef = DB.building(str(b["def_id"]))
	if bool(b["damaged"]):
		# Ремонт стоит половину постройки — и эту половину надо привезти.
		# Пока её нет, работа не идёт: иначе шторм чинился из воздуха, а план
		# лестницы за ноль материалов превращался в рабочее ребро графа (C1.3).
		if not has_repair_materials(b):
			return false
		b["progress_ticks"] = int(b["progress_ticks"]) + ticks
		if int(b["progress_ticks"]) >= _repair_ticks(d):
			var cost: Dictionary[String, int] = repair_cost(d)
			for k: String in cost:
				buffer_take(b, k, int(cost[k]), false)
			b["damaged"] = false
			b["repair_urgent"] = false          # приказ выполнен
			b["hp"] = d.hp
			b["progress_ticks"] = 0
			# Только ACTIVE: починенный недострой остаётся недостроем.
			if int(b["state"]) == int(SimTypes.BuildState.ACTIVE):
				_on_became_active(b, w)
			w.jobs.mark_dirty()
			_pending.append(SimEvent.make("building_state_changed", {"id": building_id}))
			return true
		return false
	if int(b["state"]) != int(SimTypes.BuildState.UNDER_CONSTRUCTION):
		return true
	b["progress_ticks"] = int(b["progress_ticks"]) + ticks
	if int(b["progress_ticks"]) < _build_ticks(d):
		return false
	b["progress_ticks"] = 0
	# Тратим ровно стоимость: излишки остаются станции как вход рецепта.
	for k: String in d.cost:
		buffer_take(b, k, int(d.cost[k]), false)
	_set_state(b, SimTypes.BuildState.ACTIVE, w)
	return true

static func _build_ticks(d: BuildingDef) -> int:
	return maxi(1, int(float(d.cost_units()) * Balance.BUILD_SEC_PER_UNIT
		* float(Balance.TICKS_PER_SEC)))

static func _repair_ticks(d: BuildingDef) -> int:
	return maxi(1, _build_ticks(d) / Balance.REPAIR_COST_FRACTION)

func build_progress(b: Dictionary) -> float:
	var d: BuildingDef = DB.building(str(b["def_id"]))
	var total: int = _repair_ticks(d) if bool(b["damaged"]) else _build_ticks(d)
	return clampf(float(b["progress_ticks"]) / float(total), 0.0, 1.0)

## Лежит ли в буфере вся смета ремонта. По ней же JobSystem решает,
## объявлять ли задачу «починить»: звать агента к постройке, которую нечем
## чинить, значит занять его навсегда.
func has_repair_materials(b: Dictionary) -> bool:
	var cost: Dictionary[String, int] = repair_cost(DB.building(str(b["def_id"])))
	for k: String in cost:
		if buffer_count(b, k, false) < int(cost[k]):
			return false
	return true

## Стоимость ремонта — половина от постройки, округление вниз.
static func repair_cost(d: BuildingDef) -> Dictionary[String, int]:
	var out: Dictionary[String, int] = {}
	for k: String in d.cost:
		var n: int = int(d.cost[k]) / Balance.REPAIR_COST_FRACTION
		if n > 0:
			out[k] = n
	return out

# --- Смена состояния ------------------------------------------------------

func _set_state(b: Dictionary, s: SimTypes.BuildState, w: SimWorld) -> void:
	if int(b["state"]) == int(s):
		return
	b["state"] = int(s)
	if s == SimTypes.BuildState.ACTIVE:
		_on_became_active(b, w)
	# Событие — только при РЕАЛЬНОЙ смене: иначе HUD этапа 13 будет
	# перерисовывать точки построек десять раз в секунду.
	_pending.append(SimEvent.make("building_state_changed", {"id": int(b["id"])}))

func _on_became_active(b: Dictionary, w: SimWorld) -> void:
	var d: BuildingDef = DB.building(str(b["def_id"]))
	match d.special:
		"ladder":
			if int(b["edge_id"]) < 0:
				b["edge_id"] = w.terrain.add_ladder(b["cell"] as Vector2i)
		"platform":
			var cell: Vector2i = b["cell"] as Vector2i
			w.terrain.extend_platform(int(b["mark"]), cell.x, cell.x + d.size.x - 1)
		"storage":
			# Склад регистрируется на ПОЛУ под собой: агент стоит там, и именно
			# по этой клетке он ищет склад. Иначе разгрузка не найдёт цели.
			if w.storage.storage_at(storage_cell(b)) < 0:
				w.storage.add_storage(storage_cell(b))
		_:
			pass
	w.jobs.mark_dirty()

## Поломка: лестница снимает ребро, склад перестаёт быть складом.
func _on_became_broken(b: Dictionary, w: SimWorld) -> void:
	if int(b["edge_id"]) >= 0:
		w.terrain.remove_ladder(int(b["edge_id"]))
		b["edge_id"] = -1
	b["lit"] = false
	w.jobs.mark_dirty()

# --- Топливо --------------------------------------------------------------

## Стартовый очаг уже горит: docs/00 §11.1 задаёт стартовый запас ровно
## 6 плавника, и списывать полено за первый цикл значило бы разойтись
## со спекой на единицу. Первое полено считаем сгоревшим до высадки.
func light_start_fires() -> void:
	for id: int in order:
		var b: Dictionary = buildings[id]
		var d: BuildingDef = DB.building(str(b["def_id"]))
		if d.special != "hearth" and d.special != "lantern":
			continue
		if int(b["state"]) != int(SimTypes.BuildState.ACTIVE):
			continue
		b["lit"] = true
		b["fuel_left"] = Balance.HEARTH_FUEL_CYCLES if d.special == "hearth" \
			else Balance.LANTERN_FUEL_CYCLES

## Очаг жжёт сухой плавник раз в цикл, фонарь — раз в два (docs/00 §8).
func on_cycle_started(w: SimWorld) -> void:
	for id: int in order:
		var b: Dictionary = buildings[id]
		var d: BuildingDef = DB.building(str(b["def_id"]))
		if d.special != "hearth" and d.special != "lantern":
			continue
		if int(b["state"]) != int(SimTypes.BuildState.ACTIVE) or bool(b["damaged"]):
			continue
		b["fuel_left"] = int(b["fuel_left"]) - 1
		if int(b["fuel_left"]) > 0:
			continue
		var burn: int = Balance.HEARTH_FUEL_CYCLES if d.special == "hearth" \
			else Balance.LANTERN_FUEL_CYCLES
		if _take_fuel(w):
			b["lit"] = true
			b["fuel_left"] = burn
		else:
			b["lit"] = false
			b["fuel_left"] = 0
		_pending.append(SimEvent.make("building_state_changed", {"id": id}))

## Только СУХОЙ плавник: мокрый не горит (docs/00 §7).
func _take_fuel(w: SimWorld) -> bool:
	for s: Dictionary in w.storage.storages:
		var got: Array[Dictionary] = w.storage.take(int(s["id"]), "driftwood", 1, true)
		if got.is_empty():
			continue
		if bool(got[0]["wet"]):
			w.storage.store(int(s["id"]), got[0])      # вернуть, мокрый не годится
			continue
		return true
	return false

# --- Шторм ----------------------------------------------------------------

## Вызывается SimWorld по событию кризиса: сигналов в sim нет.
## Механика одна на всех, различия — в данных: склад переживает два шторма
## не спецкейсом, а потому что у него hp = 2.
func on_storm(w: SimWorld) -> void:
	for id: int in order.duplicate():
		var b: Dictionary = buildings.get(id, {})
		if b.is_empty():
			continue
		# Недострой шторму ломать нечего: там ещё ничего не стоит.
		if int(b["state"]) != int(SimTypes.BuildState.ACTIVE):
			continue
		var d: BuildingDef = DB.building(str(b["def_id"]))
		if not d.storm_breaks:
			continue
		if not d.storm_always and int(b["mark"]) >= Balance.STORM_SAFE_MARK:
			continue
		if d.storm_always:
			_destroy(b, w, 0)             # сушила срывает в ноль, без возврата
			continue
		b["hp"] = int(b["hp"]) - 1
		if int(b["hp"]) > 0:
			_pending.append(SimEvent.make("building_state_changed", {"id": id}))
			continue
		b["damaged"] = true
		b["progress_ticks"] = 0
		_on_became_broken(b, w)
		_pending.append(SimEvent.make("building_state_changed", {"id": id}))

## Одно повреждение (существо грызёт постройку). Возвращает true, если сломал.
func apply_damage(id: int, w: SimWorld) -> bool:
	var b: Dictionary = buildings.get(id, {})
	if b.is_empty() or bool(b["damaged"]):
		return false
	if int(b["state"]) != int(SimTypes.BuildState.ACTIVE):
		return false                      # грызть недострой нечего
	b["hp"] = int(b["hp"]) - 1
	if int(b["hp"]) > 0:
		_pending.append(SimEvent.make("building_state_changed", {"id": id}))
		return false
	b["damaged"] = true
	b["progress_ticks"] = 0
	_on_became_broken(b, w)
	_pending.append(SimEvent.make("building_state_changed", {"id": id}))
	return true

# --- Снос -----------------------------------------------------------------

func demolish(id: int, w: SimWorld) -> bool:
	var b: Dictionary = buildings.get(id, {})
	if b.is_empty():
		return false
	_destroy(b, w, Balance.DEMOLISH_REFUND_FRACTION)
	return true

## refund_fraction = 0 значит «без возврата».
##
## ⚠️ Долю стоимости возвращает только ДОСТРОЕННАЯ постройка. Стоимость
## списывается из буфера в момент завершения стройки (advance_construction),
## поэтому у PLANNED и UNDER_CONSTRUCTION она ещё не потрачена: возврат
## оттуда — чистое создание ресурсов из воздуха («поставить Горн за 6 утиля,
## сразу снести, получить 3» и так до бесконечности, SIM-02).
## Буфер возвращается всегда и во всех состояниях — он реально принесён.
func _destroy(b: Dictionary, w: SimWorld, refund_fraction: int) -> void:
	var d: BuildingDef = DB.building(str(b["def_id"]))
	var cost_was_paid: bool = int(b["state"]) == int(SimTypes.BuildState.ACTIVE)
	if refund_fraction > 0 and cost_was_paid:
		var keys: Array[String] = []
		keys.assign(d.cost.keys())
		keys.sort()
		for k: String in keys:
			var n: int = int(d.cost[k]) / refund_fraction
			if n > 0:
				w.storage.drop(_free_cell_near(b["cell"] as Vector2i, w),
					StackUtil.make(k, n, false))
	# Уже принесённые в буфер материалы тоже не пропадают.
	var buf: Dictionary = b["buffer"] as Dictionary
	var bk: Array[String] = []
	bk.assign(buf.keys())
	bk.sort()
	for k2: String in bk:
		var item: String = StackUtil.key_item(k2)
		if int(buf[k2]) > 0 and DB.has_item(item):
			w.storage.drop(_free_cell_near(b["cell"] as Vector2i, w),
				StackUtil.make(item, int(buf[k2]), StackUtil.key_is_wet(k2)))
	_on_became_broken(b, w)
	if d.special == "storage":
		w.storage.remove_storage(w.storage.storage_at(storage_cell(b)), w)
	_occupy(b, false)
	var id: int = int(b["id"])
	buildings.erase(id)
	_reorder()
	w.jobs.mark_dirty()
	_pending.append(SimEvent.make("building_removed", {"id": id}))

## Материалы не должны теряться молча: если рядом всё занято, кладём прямо
## на клетку постройки.
func _free_cell_near(cell: Vector2i, w: SimWorld) -> Vector2i:
	for dx: int in [0, 1, -1, 2, -2]:
		var c: Vector2i = Vector2i(cell.x + int(dx), cell.y)
		if w.terrain.platform_at(c) >= 0:
			return c
	return cell

# --- События и сериализация -----------------------------------------------

func queue_event(e: SimEvent) -> void:
	_pending.append(e)

func drain_events() -> Array[SimEvent]:
	var out: Array[SimEvent] = _pending
	_pending = []
	return out

func to_dict() -> Dictionary:
	var list: Array = []
	for id: int in order:
		var b: Dictionary = buildings[id]
		var buf: Dictionary = {}
		var keys: Array[String] = []
		keys.assign((b["buffer"] as Dictionary).keys())
		keys.sort()
		for k: String in keys:
			buf[k] = int((b["buffer"] as Dictionary)[k])
		list.append({
			"id": int(b["id"]), "def_id": str(b["def_id"]),
			"cell": SimTypes.v2i_to_arr(b["cell"] as Vector2i),
			"mark": int(b["mark"]), "state": int(b["state"]),
			"flooded": bool(b["flooded"]), "damaged": bool(b["damaged"]),
			"hp": int(b["hp"]), "progress": int(b["progress_ticks"]),
			"buffer": buf, "pending": (b["pending_jobs"] as Array[int]).duplicate(),
			"edge_id": int(b["edge_id"]), "lit": bool(b["lit"]),
			"fuel_left": int(b["fuel_left"]),
			"flooded_in_phase": bool(b["flooded_in_phase"]),
			"repair_urgent": bool(b["repair_urgent"]),
		})
	return {"next_id": _next_id, "last_level": _last_level, "buildings": list}

func from_dict(d: Dictionary) -> void:
	buildings.clear()
	_occupied.clear()
	for v: Variant in d.get("buildings", []) as Array:
		var s: Dictionary = v as Dictionary
		var buf: Dictionary = {}
		for k: Variant in s.get("buffer", {}) as Dictionary:
			buf[str(k)] = int((s["buffer"] as Dictionary)[k])
		var pend: Array[int] = []
		for pv: Variant in s.get("pending", []) as Array:
			pend.append(int(pv))
		var b: Dictionary = {
			"id": int(s["id"]), "def_id": str(s["def_id"]),
			"cell": SimTypes.arr_to_v2i(s["cell"] as Array),
			"mark": int(s["mark"]), "state": int(s["state"]),
			"flooded": bool(s["flooded"]), "damaged": bool(s["damaged"]),
			"hp": int(s["hp"]), "progress_ticks": int(s["progress"]),
			"buffer": buf, "pending_jobs": pend,
			"edge_id": int(s["edge_id"]), "lit": bool(s["lit"]),
			"fuel_left": int(s["fuel_left"]),
			"flooded_in_phase": bool(s.get("flooded_in_phase", false)),
			"repair_urgent": bool(s.get("repair_urgent", false)),
		}
		buildings[int(s["id"])] = b
		_occupy(b, true)
	_next_id = int(d.get("next_id", 1))
	_last_level = float(d.get("last_level", Balance.HIGH_LEVEL))
	_reorder()
	_pending.clear()
