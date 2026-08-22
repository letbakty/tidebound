class_name StorageSystem
extends RefCounted
## Склады, предметы на земле, порча, намокание и затопление (docs/00 §5, §7).
##
## Стак — словарь (см. StackUtil). Склад — словарь со списком стаков.
## Всё, что меняет состояние, кладёт события в _pending; SimWorld выгребает их
## раз в тик через drain_events(): так системы, вызванные вне тика (агенты
## этапа 05), не теряют событий.

## {"id": int, "cell": Vector2i, "capacity": int, "stacks": Array[Dictionary]}
var storages: Array[Dictionary] = []
## {"cell": Vector2i, "stack": Dictionary} — предметы на земле.
## Земля не защищает: при затоплении клетки предмет уносит водой.
var ground: Array[Dictionary] = []

var _next_storage_id: int = 0
## Уровень прошлого тика. Затопление — это ПЕРЕСЕЧЕНИЕ уровнем отметки, а не
## состояние: иначе правило применялось бы каждый тик, пока склад под водой
## (research/12 §5). Одно число вместо флага «уже затоплен» у каждого объекта.
var _last_level: float = Balance.HIGH_LEVEL
var _pending: Array[SimEvent] = []
var _totals: Dictionary[String, int] = {}
## Сколько единиц унесла вода с земли за текущий цикл — уходит в итог цикла.
var _washed_this_cycle: int = 0

# --- Склады ---------------------------------------------------------------

func add_storage(cell: Vector2i, capacity_slots: int = Balance.STORAGE_SLOTS) -> int:
	var id: int = _next_storage_id
	_next_storage_id += 1
	storages.append({
		"id": id, "cell": cell, "capacity": capacity_slots,
		"stacks": [] as Array[Dictionary],
	})
	return id

func storage_index(id: int) -> int:
	for i: int in storages.size():
		if int(storages[i]["id"]) == id:
			return i
	return -1

func storage_at(cell: Vector2i) -> int:
	for s: Dictionary in storages:
		if (s["cell"] as Vector2i) == cell:
			return int(s["id"])
	return -1

## Кладёт стак на склад. Возвращает ОСТАТОК, который не влез.
func store(storage_id: int, stack: Dictionary) -> int:
	var i: int = storage_index(storage_id)
	if i < 0:
		return int(stack.get("count", 0))
	# Владение переходит складу: без duplicate вызывающий продолжит держать
	# ссылку и сможет менять стак изнутри хранилища.
	var incoming: Dictionary = stack.duplicate()
	var left: int = int(incoming["count"])
	if left <= 0:
		return 0
	var def: ItemDef = DB.item(str(incoming["item_id"]))
	if def == null:
		return left
	var stacks: Array = storages[i]["stacks"] as Array

	# Сначала добиваем совместимые неполные стаки, потом занимаем слоты.
	for s: Variant in stacks:
		var cur: Dictionary = s as Dictionary
		if left <= 0:
			break
		if not StackUtil.can_merge(cur, incoming):
			continue
		var room: int = def.stack_size - int(cur["count"])
		if room <= 0:
			continue
		var moved: int = mini(room, left)
		cur["count"] = int(cur["count"]) + moved
		left -= moved
	while left > 0 and stacks.size() < int(storages[i]["capacity"]):
		var take_n: int = mini(def.stack_size, left)
		var fresh: Dictionary = incoming.duplicate()
		fresh["count"] = take_n
		stacks.append(fresh)
		left -= take_n

	if left != int(incoming["count"]):
		_changed(storage_id)
	return left

## Забирает до n единиц. prefer_dry ставит сухие стаки в начало очереди:
## мокрый плавник не горит, и брать его первым — значит гасить очаг.
func take(storage_id: int, item_id: String, n: int, prefer_dry: bool = true) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var i: int = storage_index(storage_id)
	if i < 0 or n <= 0:
		return out
	var stacks: Array = storages[i]["stacks"] as Array
	var order: Array[int] = _take_order(stacks, item_id, prefer_dry)
	var left: int = n
	for idx: int in order:
		if left <= 0:
			break
		var cur: Dictionary = stacks[idx] as Dictionary
		var moved: int = mini(int(cur["count"]), left)
		var piece: Dictionary = cur.duplicate()
		piece["count"] = moved
		out.append(piece)
		cur["count"] = int(cur["count"]) - moved
		left -= moved
	_compact(stacks)
	if not out.is_empty():
		_changed(storage_id)
	return out

## Порядок выдачи стаков. Тай-брейк по индексу обязателен: без него порядок
## при равных ключах не определён, и два одинаковых забега разойдутся.
func _take_order(stacks: Array, item_id: String, prefer_dry: bool) -> Array[int]:
	var dry: Array[int] = []
	var wet: Array[int] = []
	for i: int in stacks.size():
		var s: Dictionary = stacks[i] as Dictionary
		if str(s["item_id"]) != item_id or int(s["count"]) <= 0:
			continue
		if bool(s["wet"]):
			wet.append(i)
		else:
			dry.append(i)
	if not prefer_dry:
		return _concat(wet, dry)
	return _concat(dry, wet)

func _concat(a: Array[int], b: Array[int]) -> Array[int]:
	var out: Array[int] = []
	out.append_array(a)
	out.append_array(b)
	return out

func _compact(stacks: Array) -> void:
	var i: int = stacks.size() - 1
	while i >= 0:
		if int((stacks[i] as Dictionary)["count"]) <= 0:
			stacks.remove_at(i)
		i -= 1

func count_in(storage_id: int, item_id: String) -> int:
	var i: int = storage_index(storage_id)
	if i < 0:
		return 0
	var n: int = 0
	for s: Variant in storages[i]["stacks"] as Array:
		var cur: Dictionary = s as Dictionary
		if str(cur["item_id"]) == item_id:
			n += int(cur["count"])
	return n

## Сколько СУХОГО предмета на складе.
func count_dry(storage_id: int, item_id: String) -> int:
	var i: int = storage_index(storage_id)
	if i < 0:
		return 0
	var n: int = 0
	for s: Variant in storages[i]["stacks"] as Array:
		var cur: Dictionary = s as Dictionary
		if str(cur["item_id"]) == item_id and not bool(cur["wet"]):
			n += int(cur["count"])
	return n

## Агрегат по ВСЕМ складам (предметы на земле не считаются — они ещё не ресурс
## колонии). Ключи отсортированы: словарь уходит в сигнал и в сейв.
func totals() -> Dictionary[String, int]:
	var out: Dictionary[String, int] = {}
	var ids: Array[String] = DB.item_ids()
	for s: Dictionary in storages:
		for v: Variant in s["stacks"] as Array:
			var cur: Dictionary = v as Dictionary
			var id: String = str(cur["item_id"])
			out[id] = int(out.get(id, 0)) + int(cur["count"])
	var sorted: Dictionary[String, int] = {}
	for id2: String in ids:
		if out.has(id2):
			sorted[id2] = out[id2]
	return sorted

## Есть ли куда положить n единиц предмета: свободный слот или неполный стак.
## Нужна StationPanel, чтобы отличить «некуда класть готовое» от прочих
## причин простоя (docs/03 §5.4).
func has_space(item_id: String, n: int = 1) -> bool:
	var def: ItemDef = DB.item(item_id)
	if def == null:
		return false
	for s: Dictionary in storages:
		var stacks: Array = s["stacks"] as Array
		if stacks.size() < int(s["capacity"]):
			return true
		for v: Variant in stacks:
			var cur: Dictionary = v as Dictionary
			if str(cur["item_id"]) == item_id and not bool(cur["wet"]) \
					and int(cur["count"]) + n <= def.stack_size:
				return true
	return false

## То же, но только СУХОЕ. Нужен HUD'у: «топливо-сухое» — не то же, что
## «плавник вообще», мокрый в очаг не пойдёт (docs/00 §7).
func totals_dry() -> Dictionary[String, int]:
	var out: Dictionary[String, int] = {}
	var ids: Array[String] = DB.item_ids()
	for s: Dictionary in storages:
		for v: Variant in s["stacks"] as Array:
			var cur: Dictionary = v as Dictionary
			if bool(cur["wet"]):
				continue
			var id: String = str(cur["item_id"])
			out[id] = int(out.get(id, 0)) + int(cur["count"])
	var sorted: Dictionary[String, int] = {}
	for id2: String in ids:
		if out.has(id2):
			sorted[id2] = out[id2]
	return sorted

# --- Предметы на земле ----------------------------------------------------

func drop(cell: Vector2i, stack: Dictionary) -> void:
	if int(stack.get("count", 0)) <= 0:
		return
	var incoming: Dictionary = stack.duplicate()
	# Земля не отменяет размер стака (R4): без этого «стак 40 утиля» лежал
	# одной кучей и уносился одним слотом котомки — тихий обход вместимости.
	var def: ItemDef = DB.item(str(incoming["item_id"]))
	var cap: int = def.stack_size if def != null else 1
	for g: Dictionary in ground:
		if int(incoming["count"]) <= 0:
			break
		if (g["cell"] as Vector2i) != cell:
			continue
		if not StackUtil.can_merge(g["stack"] as Dictionary, incoming):
			continue
		var s: Dictionary = g["stack"] as Dictionary
		var room: int = cap - int(s["count"])
		if room <= 0:
			continue
		var moved: int = mini(room, int(incoming["count"]))
		s["count"] = int(s["count"]) + moved
		incoming["count"] = int(incoming["count"]) - moved
	while int(incoming["count"]) > 0:
		var piece: Dictionary = incoming.duplicate()
		piece["count"] = mini(cap, int(incoming["count"]))
		incoming["count"] = int(incoming["count"]) - int(piece["count"])
		ground.append({"cell": cell, "stack": piece})

## Забирает ВСЕ стаки с клетки и убирает их с земли.
func pickup_at(cell: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var kept: Array[Dictionary] = []
	for g: Dictionary in ground:
		if (g["cell"] as Vector2i) == cell:
			out.append(g["stack"] as Dictionary)
		else:
			kept.append(g)
	ground = kept
	return out

func ground_at(cell: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for g: Dictionary in ground:
		if (g["cell"] as Vector2i) == cell:
			out.append(g["stack"] as Dictionary)
	return out

# --- Старт забега ---------------------------------------------------------

func new_run(_cliff: CliffDef) -> void:
	storages.clear()
	ground.clear()
	_next_storage_id = 0
	_pending.clear()
	_totals.clear()
	_washed_this_cycle = 0
	_last_level = Balance.HIGH_LEVEL

## Стартовые запасы кладутся ПОСЛЕ того, как BuildingSystem поставит стартовый
## склад: сам склад теперь постройка, а не отдельная сущность (docs/00 §11.1).
func stock_start(cliff: CliffDef) -> void:
	var id: int = storage_at(cliff.start_storage_cell)
	if id < 0:
		id = add_storage(cliff.start_storage_cell)
	for pair: Array in Balance.START_ITEMS:
		store(id, StackUtil.make(str(pair[0]), int(pair[1]), false))
	_pending.clear()                  # старт — не «изменение» для UI
	_totals = totals()

## Снос склада: содержимое не пропадает, а падает на землю рядом.
func remove_storage(id: int, w: SimWorld) -> bool:
	var i: int = storage_index(id)
	if i < 0:
		return false
	var cell: Vector2i = storages[i]["cell"] as Vector2i
	for v: Variant in storages[i]["stacks"] as Array:
		drop(cell, v as Dictionary)
	storages.remove_at(i)
	w.jobs.mark_dirty()
	_pending.append(SimEvent.make("storage_changed", {"id": id}))
	return true

# --- Тик, циклы, вода -----------------------------------------------------

## Затопление: срабатывает на ПЕРЕСЕЧЕНИИ уровнем отметки объекта, ровно один
## раз, а не каждый тик под водой.
## Возвращает, сколько складов ушло под воду за этот тик: по docs/00 §6.3
## это −10 к Духу всем, а звать AgentSystem из склада нечем — SimWorld
## разносит удар сам.
func on_tick(level: float, protected: Array[Vector2i] = []) -> int:
	var flooded: int = 0
	# Склад «топит» ПЕРЕСЕЧЕНИЕ уровнем его отметки — ровно один раз, иначе
	# правило §7 применялось бы каждый тик, пока склад под водой.
	if not is_equal_approx(level, _last_level):
		for s: Dictionary in storages:
			var mark: int = Balance.cell_to_mark(s["cell"] as Vector2i)
			if _crossed_down(mark, level):
				flooded += 1
				_flood_storage(s)
		_last_level = level
	_wash_ground(level, protected)
	return flooded

## Смыв брошенного на землю — по «лежит под водой», а не по пересечению (R3).
## На пересечении брошенное в УЖЕ стоящую воду лежало бессмертно: жёсткий
## Отзыв на Высокой воде ронял котомку под воду, и «налог на жадность»
## обходился — груз спокойно дожидался отлива.
##
## Проход каждый тик, но БЕЗ аллокации, пока смывать нечего: массив
## пересобирается только в тот тик, когда что-то действительно уносит.
func _wash_ground(level: float, protected: Array[Vector2i]) -> void:
	var any: bool = false
	for g: Dictionary in ground:
		if _washes_away(g, level, protected):
			any = true
			break
	if not any:
		return
	var washed: int = 0
	var kept: Array[Dictionary] = []
	for g2: Dictionary in ground:
		if _washes_away(g2, level, protected):
			washed += int((g2["stack"] as Dictionary)["count"])
		else:
			kept.append(g2)
	ground = kept
	_washed_this_cycle += washed

static func _washes_away(g: Dictionary, level: float, protected: Array[Vector2i]) -> bool:
	var cell: Vector2i = g["cell"] as Vector2i
	return Balance.is_mark_flooded(Balance.cell_to_mark(cell), level) \
		and not protected.has(cell)

func _crossed_down(mark: int, level: float) -> bool:
	var was: bool = Balance.is_mark_flooded(mark, _last_level)
	var now: bool = Balance.is_mark_flooded(mark, level)
	return now and not was

## Правила затопления склада — docs/00 §7.
##
## РЕШЕНИЕ: −50% считается от ИТОГА по предмету на складе, а не по каждому
## стаку отдельно. Иначе результат зависит от того, как товар разложен по
## стакам: 16 добычи одним стаком дают 8, а стаками 10+6 — только 8→5+3, и
## следующее затопление уже 2+1 вместо 4. Игрок такой «налог на упаковку»
## объяснить себе не может.
func _flood_storage(s: Dictionary) -> void:
	var stacks: Array = s["stacks"] as Array
	# Бюджеты «сколько оставить» по предметам с правилом LOSE_HALF.
	var budget: Dictionary[String, int] = {}
	for v: Variant in stacks:
		var cur: Dictionary = v as Dictionary
		var def: ItemDef = DB.item(str(cur["item_id"]))
		if def == null or def.flood_rule != SimTypes.FloodRule.LOSE_HALF:
			continue
		var id: String = str(cur["item_id"])
		budget[id] = int(budget.get(id, 0)) + int(cur["count"])
	for id2: String in budget:
		budget[id2] = budget[id2] / 2

	var kept: Array[Dictionary] = []
	var changed: bool = false
	for v2: Variant in stacks:
		var cur2: Dictionary = v2 as Dictionary
		var def2: ItemDef = DB.item(str(cur2["item_id"]))
		if def2 == null:
			kept.append(cur2)
			continue
		match def2.flood_rule:
			SimTypes.FloodRule.DESTROY:
				changed = true                # соль растворилась
			SimTypes.FloodRule.LOSE_HALF:
				var id3: String = str(cur2["item_id"])
				var give: int = mini(int(budget[id3]), int(cur2["count"]))
				budget[id3] = int(budget[id3]) - give
				if give != int(cur2["count"]):
					changed = true
				cur2["count"] = give
				if give > 0:
					kept.append(cur2)
			SimTypes.FloodRule.WET:
				if not bool(cur2["wet"]):
					StackUtil.set_wet(cur2, true)
					changed = true
				kept.append(cur2)
			_:
				kept.append(cur2)             # OK / DISABLED — предмету всё равно
	if not changed:
		return
	s["stacks"] = kept
	_changed(int(s["id"]))

## Порча и сушка — раз в цикл (docs/00 §7). Возвращает сводку для итога цикла.
func on_cycle_ended() -> Dictionary:
	var spoiled: Dictionary[String, int] = {}
	for s: Dictionary in storages:
		var mark: int = Balance.cell_to_mark(s["cell"] as Vector2i)
		var dry_ok: bool = mark >= Balance.DRY_MIN_MARK
		var kept: Array[Dictionary] = []
		var changed: bool = false
		for v: Variant in s["stacks"] as Array:
			var cur: Dictionary = v as Dictionary
			if bool(cur["wet"]) and dry_ok:
				cur["dry_left"] = int(cur["dry_left"]) - 1
				changed = true
				if int(cur["dry_left"]) <= 0:
					StackUtil.set_wet(cur, false)
			if int(cur["spoil_left"]) > 0:
				cur["spoil_left"] = int(cur["spoil_left"]) - 1
				changed = true
				if int(cur["spoil_left"]) <= 0:
					var id: String = str(cur["item_id"])
					spoiled[id] = int(spoiled.get(id, 0)) + int(cur["count"])
					continue
			kept.append(cur)
		if changed:
			s["stacks"] = kept
			_changed(int(s["id"]))
	_spoil_ground(spoiled)
	var report: Dictionary = {"spoiled": spoiled, "washed": _washed_this_cycle}
	_washed_this_cycle = 0
	return report

## Порча брошенного на землю. Срок годности — свойство ПРЕДМЕТА (docs/00 §7),
## а не склада: пока порча тикала только в складах, сырую добычу можно было
## вечно хранить кучей на полу (R3). Сушка на земле не идёт — сушит очаг
## и Сушила, то есть постройки, а не пол.
func _spoil_ground(spoiled: Dictionary[String, int]) -> void:
	var kept: Array[Dictionary] = []
	for g: Dictionary in ground:
		var cur: Dictionary = g["stack"] as Dictionary
		if int(cur["spoil_left"]) > 0:
			cur["spoil_left"] = int(cur["spoil_left"]) - 1
			if int(cur["spoil_left"]) <= 0:
				var id: String = str(cur["item_id"])
				spoiled[id] = int(spoiled.get(id, 0)) + int(cur["count"])
				continue
		kept.append(g)
	ground = kept

## Плавник, вынесенный водой: 3–6 стаков вдоль отметок 0..+1, только на
## свободные клетки (docs/00 §3.2).
func spawn_driftwood(terrain: Terrain, rng: SimRNG) -> void:
	var n: int = rng.randi_range(Balance.DRIFTWOOD_MIN, Balance.DRIFTWOOD_MAX)
	for i: int in n:
		var mark: int = rng.randi_range(Balance.DRIFTWOOD_MARK_LO, Balance.DRIFTWOOD_MARK_HI)
		var span: Array[int] = terrain.platform_x_range(mark)
		if span.is_empty():
			continue
		var x: int = rng.randi_range(span[0], span[1])
		var cell: Vector2i = Vector2i(x, Balance.mark_to_floor_cell_y(mark))
		if not ground_at(cell).is_empty():
			continue                      # клетка занята — плавник туда не лёг
		drop(cell, StackUtil.make("driftwood", 1, false))

# --- События --------------------------------------------------------------

func _changed(storage_id: int) -> void:
	_pending.append(SimEvent.make("storage_changed", {"id": storage_id}))

## Выгребается SimWorld раз в тик. Сюда же добавляется resources_changed,
## если агрегат действительно изменился.
func drain_events() -> Array[SimEvent]:
	var t: Dictionary[String, int] = totals()
	if t != _totals:
		_totals = t
		_pending.append(SimEvent.make("resources_changed", {"totals": t}))
	var out: Array[SimEvent] = _pending
	_pending = []
	return out

# --- Сериализация ---------------------------------------------------------

func to_dict() -> Dictionary:
	var st: Array = []
	for s: Dictionary in storages:
		var stacks: Array = []
		for v: Variant in s["stacks"] as Array:
			stacks.append((v as Dictionary).duplicate())
		st.append({
			"id": int(s["id"]), "cell": SimTypes.v2i_to_arr(s["cell"] as Vector2i),
			"capacity": int(s["capacity"]), "stacks": stacks,
		})
	var gr: Array = []
	for g: Dictionary in ground:
		gr.append({
			"cell": SimTypes.v2i_to_arr(g["cell"] as Vector2i),
			"stack": (g["stack"] as Dictionary).duplicate(),
		})
	return {
		"next_storage_id": _next_storage_id,
		"last_level": _last_level,
		"washed": _washed_this_cycle,
		"storages": st,
		"ground": gr,
	}

func from_dict(d: Dictionary) -> void:
	storages.clear()
	for v: Variant in d.get("storages", []) as Array:
		var s: Dictionary = v as Dictionary
		var stacks: Array[Dictionary] = []
		for sv: Variant in s.get("stacks", []) as Array:
			stacks.append(StackUtil.from_json(sv as Dictionary))
		storages.append({
			"id": int(s["id"]), "cell": SimTypes.arr_to_v2i(s["cell"] as Array),
			"capacity": int(s["capacity"]), "stacks": stacks,
		})
	ground.clear()
	for gv: Variant in d.get("ground", []) as Array:
		var g: Dictionary = gv as Dictionary
		ground.append({
			"cell": SimTypes.arr_to_v2i(g["cell"] as Array),
			"stack": StackUtil.from_json(g["stack"] as Dictionary),
		})
	_next_storage_id = int(d.get("next_storage_id", storages.size()))
	_last_level = float(d.get("last_level", Balance.HIGH_LEVEL))
	_washed_this_cycle = int(d.get("washed", 0))
	_pending.clear()
	_totals = totals()
