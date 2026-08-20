class_name Terrain
extends RefCounted
## Мир как ГРАФ, а не как тайловая сетка (docs/00 §3.1): площадка = узел,
## лестница = ребро. Тайлмап в game/ только рисует это состояние.
##
## Строится из CliffDef (иммутабельный деф). Всё изменяемое — здесь:
## сколько осталось в депозите, какие лестницы стоят.

## Инкремент при любом изменении графа. Кэш путей агентов (этапы 05/06) и
## оверлей дебага (03) сравнивают её со своей, чтобы не искать путь каждый тик.
var graph_version: int = 0

## {"id": int, "mark": int, "x0": int, "x1": int} — по одной площадке на отметку,
## отсортированы по убыванию отметки. id == индекс в массиве.
var platforms: Array[Dictionary] = []
## {"id": int, "x": int, "mark_top": int} — связывает mark_top и mark_top−1.
var ladders: Array[Dictionary] = []
## {"id": int, "kind": String, "cell": Vector2i, "amount": int, "has_relic": bool}
var deposits: Array[Dictionary] = []

var _cliff: CliffDef = null
var _mark_to_platform: Dictionary[int, int] = {}
var _next_ladder_id: int = 0
var _next_deposit_id: int = 0
## Производное состояние: НЕ сериализуется, пересобирается из platforms/ladders.
var _astar: AStar2D = AStar2D.new()

# --- Построение -----------------------------------------------------------

## Карта без депозитов: площадки, стартовые лестницы, граф. RNG НЕ трогает —
## поэтому её же зовёт загрузка сейва, где депозиты придут из файла, а лишний
## бросок кубика сдвинул бы последовательность и сломал детерминизм.
func build_static(cliff: CliffDef) -> void:
	_cliff = cliff
	platforms.clear()
	ladders.clear()
	deposits.clear()
	_mark_to_platform.clear()
	_next_ladder_id = 0
	_next_deposit_id = 0

	# Порядок узлов фиксирован (по убыванию отметки): от него зависит и порядок
	# рёбер в AStar, и, значит, выбор пути при равной стоимости.
	var marks: Array[int] = []
	for p: Dictionary in cliff.platforms:
		marks.append(int(p["mark"]))
	marks.sort()
	marks.reverse()
	for mark: int in marks:
		var src: Dictionary = cliff.platform_for_mark(mark)
		var id: int = platforms.size()
		platforms.append({
			"id": id, "mark": mark,
			"x0": int(src["x0"]), "x1": int(src["x1"]),
		})
		_mark_to_platform[mark] = id

	for l: Dictionary in cliff.start_ladders:
		_add_ladder_raw(int(l["x"]), int(l["mark_top"]))
	graph_version = 0
	_rebuild_graph()

func build(cliff: CliffDef, rng: SimRNG) -> void:
	build_static(cliff)
	_spawn_slot_deposits(cliff, rng)

## Депозиты по слотам карты. Порядок обхода слотов = порядок обращений к rng,
## поэтому он обязан быть тем же, что в дефе.
func _spawn_slot_deposits(cliff: CliffDef, rng: SimRNG) -> void:
	for slot: Dictionary in cliff.deposit_slots:
		var kind: String = str(slot["kind"])
		var mark: int = int(slot["mark"])
		var cell: Vector2i = Vector2i(int(slot["x"]), Balance.mark_to_floor_cell_y(mark))
		var relic: bool = false
		if kind == "ruins_deep" and mark <= Balance.RELIC_MARK_MAX:
			relic = rng.chance(Balance.RELIC_CHANCE)
		_add_deposit(kind, cell, relic)

func _add_deposit(kind: String, cell: Vector2i, has_relic: bool) -> int:
	var def: Dictionary = Balance.DEPOSIT_KINDS.get(kind, {}) as Dictionary
	if def.is_empty():
		push_error("Terrain: неизвестный вид депозита '%s'" % kind)
		return -1
	var id: int = _next_deposit_id
	_next_deposit_id += 1
	deposits.append({
		"id": id, "kind": kind, "cell": cell,
		"amount": int(def["capacity"]), "has_relic": has_relic,
	})
	return id

# --- Граф -----------------------------------------------------------------

func _rebuild_graph() -> void:
	# Граф из ~15 узлов: полная перестройка дешевле и надёжнее инкремента,
	# и главное — гарантирует один и тот же порядок рёбер, а значит
	# одинаковый выбор при равной стоимости пути (research/12 §4).
	_astar.clear()
	for p: Dictionary in platforms:
		var mark: int = int(p["mark"])
		# Позиция в ТАЙЛАХ, не в пикселях: пиксели — забота презентации.
		_astar.add_point(int(p["id"]), Vector2(
			(float(int(p["x0"]) + int(p["x1"])) + 1.0) * 0.5,
			float(Balance.mark_to_floor_cell_y(mark))))
	for l: Dictionary in ladders:
		var top: int = int(l["mark_top"])
		var a: int = _mark_to_platform.get(top, -1)
		var b: int = _mark_to_platform.get(top - 1, -1)
		if a >= 0 and b >= 0:
			_astar.connect_points(a, b, true)
	graph_version += 1

## Путь по id площадок, включая обе конечные. Пустой массив = пути нет.
func find_path(from_platform: int, to_platform: int) -> Array[int]:
	var out: Array[int] = []
	if not _astar.has_point(from_platform) or not _astar.has_point(to_platform):
		return out
	for v: int in _astar.get_id_path(from_platform, to_platform):
		out.append(int(v))
	return out

# --- Запросы по клеткам ---------------------------------------------------

func mark_of_cell(cell: Vector2i) -> int:
	return Balance.cell_to_mark(cell)

## id площадки, которой принадлежит клетка, или −1. Отметка у клетки ровно
## одна, поэтому кандидат тоже один — перебора площадок не нужно.
func platform_at(cell: Vector2i) -> int:
	var id: int = _mark_to_platform.get(mark_of_cell(cell), -1)
	if id < 0:
		return -1
	var p: Dictionary = platforms[id]
	if cell.x < int(p["x0"]) or cell.x > int(p["x1"]):
		return -1
	return id

func platform_of_mark(mark: int) -> int:
	return _mark_to_platform.get(mark, -1)

func is_flooded(cell: Vector2i, water_level: float) -> bool:
	return float(mark_of_cell(cell)) < water_level - Balance.FLOOD_EPS

## Расстояние в тайлах до ближайшей лестницы (манхэттен: агент идёт по
## горизонтали, потом лезет). Ограничение политики Жадность считается по нему.
## INF, если лестниц нет вовсе.
func nearest_ladder_dist(cell: Vector2i) -> float:
	var best: float = INF
	var mark: int = mark_of_cell(cell)
	for l: Dictionary in ladders:
		var top: int = int(l["mark_top"])
		# Лестница «занимает» обе отметки, которые связывает.
		var m: int = clampi(mark, top - 1, top)
		var d: float = absf(float(cell.x - int(l["x"]))) \
			+ absf(float(mark - m)) * float(Balance.TILES_PER_MARK)
		best = minf(best, d)
	return best

# --- Лестницы -------------------------------------------------------------

## Ставит лестницу в колонке клетки: связывает отметку клетки с отметкой ниже.
## Возвращает id или −1, если поставить нельзя (нет площадки сверху или снизу,
## либо лестница здесь уже есть).
func add_ladder(cell: Vector2i) -> int:
	var id: int = _add_ladder_raw(cell.x, mark_of_cell(cell))
	if id >= 0:
		_rebuild_graph()
	return id

func _add_ladder_raw(x: int, mark_top: int) -> int:
	if not _can_place_ladder(x, mark_top):
		return -1
	var id: int = _next_ladder_id
	_next_ladder_id += 1
	ladders.append({"id": id, "x": x, "mark_top": mark_top})
	return id

func can_place_ladder(cell: Vector2i) -> bool:
	return _can_place_ladder(cell.x, mark_of_cell(cell))

func _can_place_ladder(x: int, mark_top: int) -> bool:
	var a: int = _mark_to_platform.get(mark_top, -1)
	var b: int = _mark_to_platform.get(mark_top - 1, -1)
	if a < 0 or b < 0:
		return false
	# Колонка обязана лежать в обеих площадках — иначе лестница висит в воздухе.
	if not _x_in_platform(a, x) or not _x_in_platform(b, x):
		return false
	for l: Dictionary in ladders:
		if int(l["x"]) == x and int(l["mark_top"]) == mark_top:
			return false
	return true

func _x_in_platform(id: int, x: int) -> bool:
	var p: Dictionary = platforms[id]
	return x >= int(p["x0"]) and x <= int(p["x1"])

func remove_ladder(id: int) -> bool:
	for i: int in ladders.size():
		if int(ladders[i]["id"]) == id:
			ladders.remove_at(i)
			_rebuild_graph()
			return true
	return false

func ladder_at(cell: Vector2i) -> int:
	var mark: int = mark_of_cell(cell)
	for l: Dictionary in ladders:
		if int(l["x"]) == cell.x and int(l["mark_top"]) == mark:
			return int(l["id"])
	return -1

# --- Депозиты -------------------------------------------------------------

func deposit_index(id: int) -> int:
	for i: int in deposits.size():
		if int(deposits[i]["id"]) == id:
			return i
	return -1

func deposit_at(cell: Vector2i) -> int:
	for d: Dictionary in deposits:
		if (d["cell"] as Vector2i) == cell:
			return int(d["id"])
	return -1

## Забирает не больше, чем есть. Возвращает сколько реально взято.
func take(deposit_id: int, n: int) -> int:
	var i: int = deposit_index(deposit_id)
	if i < 0 or n <= 0:
		return 0
	var have: int = int(deposits[i]["amount"])
	var got: int = mini(have, n)
	deposits[i]["amount"] = have - got
	return got

## Восполнение и плавник — раз в цикл, на cycle_started (docs/00 §3.2).
func on_cycle_started(rng: SimRNG) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for i: int in deposits.size():
		var kind: String = str(deposits[i]["kind"])
		var def: Dictionary = Balance.DEPOSIT_KINDS[kind] as Dictionary
		var refill: int = int(def["refill"])
		if refill <= 0:
			continue
		var was: int = int(deposits[i]["amount"])
		var now: int = mini(int(def["capacity"]), was + refill)
		if now != was:
			deposits[i]["amount"] = now
			out.append(SimEvent.make("deposit_changed", {"id": int(deposits[i]["id"])}))
	out.append_array(_spawn_driftwood(rng))
	return out

## Плавник, вынесенный водой: 3–6 штук вдоль отметок 0..+1.
## TODO(этап 04): это станут настоящие предметы на земле; депозит-одноразка —
## временная форма, чтобы уже сейчас было что подбирать.
func _spawn_driftwood(rng: SimRNG) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	# Старый плавник уносит обратно той же водой — иначе он копился бы весь забег.
	var kept: Array[Dictionary] = []
	for d: Dictionary in deposits:
		if str(d["kind"]) != "driftwood":
			kept.append(d)
	deposits = kept

	var n: int = rng.randi_range(Balance.DRIFTWOOD_MIN, Balance.DRIFTWOOD_MAX)
	for i: int in n:
		var mark: int = rng.randi_range(0, 1)
		var pid: int = _mark_to_platform.get(mark, -1)
		if pid < 0:
			continue
		var p: Dictionary = platforms[pid]
		var x: int = rng.randi_range(int(p["x0"]), int(p["x1"]))
		var cell: Vector2i = Vector2i(x, Balance.mark_to_floor_cell_y(mark))
		var id: int = _add_deposit("driftwood", cell, false)
		if id >= 0:
			out.append(SimEvent.make("deposit_changed", {"id": id}))
	return out

# --- Сериализация ---------------------------------------------------------
# Карта (площадки) — из дефа, её не сохраняем. Сохраняем только изменяемое:
# лестницы (их строят и смывает шторм) и депозиты. AStar — производное.

func to_dict() -> Dictionary:
	var lad: Array = []
	for l: Dictionary in ladders:
		lad.append({"id": int(l["id"]), "x": int(l["x"]), "mark_top": int(l["mark_top"])})
	var dep: Array = []
	for d: Dictionary in deposits:
		dep.append({
			"id": int(d["id"]), "kind": str(d["kind"]),
			"cell": SimTypes.v2i_to_arr(d["cell"] as Vector2i),
			"amount": int(d["amount"]), "has_relic": bool(d["has_relic"]),
		})
	return {
		"graph_version": graph_version,
		"next_ladder_id": _next_ladder_id,
		"next_deposit_id": _next_deposit_id,
		"ladders": lad,
		"deposits": dep,
	}

## Требует уже вызванного build(): площадки берутся из дефа, а не из сейва.
func from_dict(d: Dictionary) -> void:
	ladders.clear()
	for v: Variant in d.get("ladders", []) as Array:
		var l: Dictionary = v as Dictionary
		ladders.append({
			"id": int(l["id"]), "x": int(l["x"]), "mark_top": int(l["mark_top"]),
		})
	deposits.clear()
	for v: Variant in d.get("deposits", []) as Array:
		var dd: Dictionary = v as Dictionary
		deposits.append({
			"id": int(dd["id"]), "kind": str(dd["kind"]),
			"cell": SimTypes.arr_to_v2i(dd["cell"] as Array),
			"amount": int(dd["amount"]), "has_relic": bool(dd["has_relic"]),
		})
	_next_ladder_id = int(d.get("next_ladder_id", ladders.size()))
	_next_deposit_id = int(d.get("next_deposit_id", deposits.size()))
	_rebuild_graph()
	# _rebuild_graph сам инкрементировал счётчик — восстанавливаем сохранённый,
	# иначе кэши путей после загрузки посчитают граф изменившимся.
	graph_version = int(d.get("graph_version", graph_version))
