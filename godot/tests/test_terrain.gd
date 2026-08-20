extends RefCounted
## Приёмка этапа 02: отметки, граф площадок, лестницы, затопление, депозиты.

const CLIFF: String = "res://data/cliffs/cliff_01.tres"

static func _cliff() -> CliffDef:
	return load(CLIFF) as CliffDef

static func _world(seed_value: int) -> SimWorld:
	var w: SimWorld = SimWorld.new()
	w.new_run(seed_value, _cliff())
	w.events_out.clear()
	return w

# --- Геометрия ------------------------------------------------------------

## Пять контрольных клеток, включая границы ярусов и отрицательные отметки.
## floori vs int() ловится именно здесь: при int() отметка −1 стала бы 0.
static func test_mark_of_cell(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	t.check_eq(w.terrain.mark_of_cell(Vector2i(0, 0)), 6, "строка 0 — верх утёса, +6")
	t.check_eq(w.terrain.mark_of_cell(Vector2i(5, 2)), 6, "строка 2 — ещё ярус +6")
	t.check_eq(w.terrain.mark_of_cell(Vector2i(5, 3)), 5, "строка 3 — уже ярус +5")
	t.check_eq(w.terrain.mark_of_cell(Vector2i(9, 20)), 0, "строка 20 — отметка 0")
	t.check_eq(w.terrain.mark_of_cell(Vector2i(9, 21)), -1, "строка 21 — отметка −1")
	t.check_eq(w.terrain.mark_of_cell(Vector2i(40, 44)), -8, "последняя строка — дно −8")

## Одна формула на sim и презентацию: если они разойдутся, вода уедет на ярус.
static func test_geo_matches_sim(t: TestCtx) -> void:
	var bad: int = 0
	for y: int in 45:
		if WorldGeo.cell_to_mark(Vector2i(0, y)) != Balance.cell_to_mark(Vector2i(0, y)):
			bad += 1
	t.check_eq(bad, 0, "WorldGeo и Balance дают одинаковые отметки по всей карте")
	for mark: int in range(Balance.BOTTOM_MARK, Balance.TOP_MARK + 1):
		var y: int = Balance.mark_to_floor_cell_y(mark)
		t.check_eq(Balance.cell_to_mark(Vector2i(0, y)), mark,
			"пол отметки %d принадлежит своему ярусу" % mark)

static func test_platform_at(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	t.check_eq(w.terrain.platforms.size(), 15, "15 ярусов: от +6 до −8")
	var top: int = w.terrain.platform_of_mark(6)
	t.check(top >= 0, "площадка +6 есть")
	t.check_eq(w.terrain.platform_at(Vector2i(4, Balance.mark_to_floor_cell_y(6))), top,
		"клетка на площадке +6 принадлежит ей")
	t.check_eq(w.terrain.platform_at(Vector2i(40, Balance.mark_to_floor_cell_y(6))), -1,
		"клетка правее площадки +6 — пустота")

# --- Граф -----------------------------------------------------------------

static func test_path_top_to_bottom(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var from_id: int = w.terrain.platform_of_mark(6)
	var to_id: int = w.terrain.platform_of_mark(-2)
	var path: Array[int] = w.terrain.find_path(from_id, to_id)
	t.check(path.size() > 0, "путь от +6 до −2 существует")
	t.check_eq(path[0], from_id, "путь начинается с исходной площадки")
	t.check_eq(path[path.size() - 1], to_id, "путь кончается целевой площадкой")
	# Спуск возможен только по лестницам: каждое ребро пути обязано быть ею.
	var missing: int = 0
	for i: int in path.size() - 1:
		var m_a: int = int(w.terrain.platforms[path[i]]["mark"])
		var m_b: int = int(w.terrain.platforms[path[i + 1]]["mark"])
		if not _has_ladder_between(w.terrain, m_a, m_b):
			missing += 1
	t.check_eq(missing, 0, "каждый шаг пути проходит через лестницу")

static func _has_ladder_between(terrain: Terrain, mark_a: int, mark_b: int) -> bool:
	var top: int = maxi(mark_a, mark_b)
	for l: Dictionary in terrain.ladders:
		if int(l["mark_top"]) == top:
			return true
	return false

## Ниже −2 стартовых лестниц нет: спуск к руинам надо построить.
static func test_deep_unreachable_at_start(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var path: Array[int] = w.terrain.find_path(
		w.terrain.platform_of_mark(6), w.terrain.platform_of_mark(-8))
	t.check_eq(path.size(), 0, "на старте до −8 не дойти — нужны лестницы")

## Док AStar2D молчит о том, детерминирован ли выбор при равной стоимости.
## Проверяем сами: если тест покраснеет, откатываться на свой BFS.
static func test_path_is_stable(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var a: int = w.terrain.platform_of_mark(6)
	var b: int = w.terrain.platform_of_mark(-2)
	t.check_eq(w.terrain.find_path(a, b), w.terrain.find_path(a, b),
		"два вызова подряд дают один путь")
	var d: Dictionary = w.to_dict()
	var restored: SimWorld = SimWorld.new()
	restored.from_dict(d, _cliff())
	t.check_eq(restored.terrain.find_path(a, b), w.terrain.find_path(a, b),
		"путь не разошёлся после загрузки")

static func test_ladders(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var before: int = w.terrain.graph_version
	# −2 (18..27) и −3 (23..32) перекрываются на 23..27.
	var cell: Vector2i = Vector2i(25, Balance.mark_to_floor_cell_y(-2))
	var id: int = w.terrain.add_ladder(cell)
	t.check(id >= 0, "лестница ставится в перекрытии площадок −2 и −3")
	t.check(w.terrain.graph_version > before, "граф пометился изменившимся")
	var path: Array[int] = w.terrain.find_path(
		w.terrain.platform_of_mark(6), w.terrain.platform_of_mark(-3))
	t.check(path.size() > 0, "после постройки лестницы −3 достижима")

	t.check_eq(w.terrain.add_ladder(cell), -1, "две лестницы в одной клетке нельзя")
	# x=40 лежит в площадке −5 (30..40), но не в −6 (33..43)? лежит.
	# Берём заведомо невозможное: x=2 на отметке −2 (площадка −2 начинается с 18).
	t.check_eq(w.terrain.add_ladder(Vector2i(2, Balance.mark_to_floor_cell_y(-2))), -1,
		"лестница вне площадки не ставится")
	t.check_eq(w.terrain.add_ladder(Vector2i(40, Balance.mark_to_floor_cell_y(-8))), -1,
		"ниже дна лестнице некуда вести")

	t.check(w.terrain.remove_ladder(id), "лестница сносится")
	t.check_eq(w.terrain.find_path(
		w.terrain.platform_of_mark(6), w.terrain.platform_of_mark(-3)).size(), 0,
		"после сноса −3 снова недостижима")

static func test_nearest_ladder_dist(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	# Стартовая лестница x=20 связывает −1 и −2.
	var at_ladder: Vector2i = Vector2i(20, Balance.mark_to_floor_cell_y(-2))
	t.check_approx(w.terrain.nearest_ladder_dist(at_ladder), 0.0, 0.001,
		"в клетке лестницы расстояние 0")
	var away: Vector2i = Vector2i(26, Balance.mark_to_floor_cell_y(-2))
	t.check_approx(w.terrain.nearest_ladder_dist(away), 6.0, 0.001,
		"6 клеток вправо по той же отметке = 6")
	t.check(w.terrain.nearest_ladder_dist(Vector2i(46, Balance.mark_to_floor_cell_y(-8)))
		> w.terrain.nearest_ladder_dist(away),
		"глубокие руины дальше от лестниц, чем ближние")

# --- Затопление -----------------------------------------------------------

static func test_is_flooded(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var deep: Vector2i = Vector2i(40, Balance.mark_to_floor_cell_y(-8))
	var high: Vector2i = Vector2i(4, Balance.mark_to_floor_cell_y(3))
	t.check(w.terrain.is_flooded(deep, 0.0), "при высокой воде дно затоплено")
	t.check(not w.terrain.is_flooded(high, 0.0), "утёс при высокой воде сухой")
	t.check(not w.terrain.is_flooded(deep, -8.0), "на плато отлива дно сухое")
	t.check(w.terrain.is_flooded(deep, -7.5), "вода выше −8 — дно снова под водой")

## Эпсилон в is_flooded: без него нижняя ступень мигала бы от float-шума
## smoothstep, и склад на −8 «затапливался» бы по нескольку раз за цикл.
static func test_flood_does_not_flicker(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var deep: Vector2i = Vector2i(40, Balance.mark_to_floor_cell_y(-8))
	var switches: int = 0
	var prev: bool = w.terrain.is_flooded(deep, w.tide.level)
	for i: int in Balance.TICKS_PER_CYCLE:
		t.run_ticks(w, 1)
		var now: bool = w.terrain.is_flooded(deep, w.tide.level)
		if now != prev:
			switches += 1
		prev = now
	t.check_eq(switches, 2, "за цикл дно осушается и затапливается ровно по разу")

# --- Депозиты -------------------------------------------------------------

static func test_deposits_placed(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var by_kind: Dictionary = {}
	for d: Dictionary in w.terrain.deposits:
		var k: String = str(d["kind"])
		by_kind[k] = int(by_kind.get(k, 0)) + 1
		t.check(w.terrain.platform_at(d["cell"] as Vector2i) >= 0,
			"депозит %s стоит на площадке" % k)
	t.check_eq(int(by_kind.get("ruins_near", 0)), 3, "ближних руин 3")
	t.check_eq(int(by_kind.get("ruins_deep", 0)), 3, "глубоких руин 3")
	t.check_eq(int(by_kind.get("shallow", 0)), 2, "отмелей 2")
	t.check_eq(int(by_kind.get("kelp", 0)), 2, "полей водорослей 2")

static func test_take_never_goes_negative(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var id: int = int(w.terrain.deposits[0]["id"])
	var cap: int = int(w.terrain.deposits[0]["amount"])
	t.check_eq(w.terrain.take(id, 3), 3, "берём сколько просили, пока есть")
	t.check_eq(w.terrain.take(id, 9999), cap - 3, "остаток отдаётся целиком")
	t.check_eq(w.terrain.take(id, 5), 0, "из пустого депозита берётся 0")
	t.check_eq(int(w.terrain.deposits[0]["amount"]), 0, "в минус не уходит")
	t.check_eq(w.terrain.take(id, -1), 0, "отрицательный запрос ничего не меняет")
	t.check_eq(w.terrain.take(9999, 1), 0, "несуществующий депозит безопасен")

static func test_shallow_refills(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var id: int = -1
	for d: Dictionary in w.terrain.deposits:
		if str(d["kind"]) == "shallow":
			id = int(d["id"])
			break
	t.check(id >= 0, "отмель найдена")
	w.terrain.take(id, 8)
	t.run_ticks(w, Balance.TICKS_PER_CYCLE)
	var i: int = w.terrain.deposit_index(id)
	t.check_eq(int(w.terrain.deposits[i]["amount"]), 4, "отмель восполнилась на +4 за отлив")
	t.run_ticks(w, Balance.TICKS_PER_CYCLE)
	i = w.terrain.deposit_index(id)
	t.check_eq(int(w.terrain.deposits[i]["amount"]), 8, "и не выше ёмкости 8")

## Ближние руины не восполняются — на этом держится давление забега.
static func test_ruins_do_not_refill(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var id: int = -1
	for d: Dictionary in w.terrain.deposits:
		if str(d["kind"]) == "ruins_near":
			id = int(d["id"])
			break
	w.terrain.take(id, 12)
	t.run_ticks(w, Balance.TICKS_PER_CYCLE * 2)
	t.check_eq(int(w.terrain.deposits[w.terrain.deposit_index(id)]["amount"]), 0,
		"руины остаются пустыми")

# Плавник переехал в StorageSystem (этап 04) — его тесты в test_storage.gd.

# --- Сериализация ---------------------------------------------------------

static func test_terrain_survives_save(t: TestCtx) -> void:
	var w: SimWorld = _world(31337)
	t.run_ticks(w, 4000)
	w.terrain.add_ladder(Vector2i(25, Balance.mark_to_floor_cell_y(-2)))
	w.terrain.take(int(w.terrain.deposits[0]["id"]), 5)

	var text: String = JSON.stringify(w.to_dict(), "", true, true)
	var restored: SimWorld = SimWorld.new()
	restored.from_dict(JSON.parse_string(text) as Dictionary, _cliff())
	t.check_eq(restored.terrain.ladders.size(), w.terrain.ladders.size(),
		"лестницы восстановлены")
	t.check_eq(restored.terrain.deposits.size(), w.terrain.deposits.size(),
		"депозиты восстановлены")
	t.check_eq(restored.terrain.graph_version, w.terrain.graph_version,
		"версия графа не «скакнула» после загрузки")
	t.check_eq(JSON.stringify(restored.to_dict(), "", true, true), text,
		"состояние мира с рельефом переживает JSON")

	for i: int in 3000:
		t.run_ticks(w, 1)
		t.run_ticks(restored, 1)
	t.check_eq(TestCtx.state_hash(w), TestCtx.state_hash(restored),
		"после загрузки мир с рельефом продолжается идентично")
