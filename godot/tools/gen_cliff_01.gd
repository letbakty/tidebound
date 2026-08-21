extends SceneTree
## Генератор карты утёса №1 (docs/00 §3.1, §3.2).
##   godot --headless -s res://tools/gen_cliff_01.gd
##
## Карта задана таблицей в коде, а не кликами в инспекторе: так её видно
## целиком, легко перегенерировать и понятен git-дифф (research/25 §5).
##
## Геометрия: 48×45 = 15 ярусов по 3 тайла, отметки +6..−8.
## Слева жилой утёс (+6..+1) узкими площадками, дальше кромка 0 и ступени дна
## вправо-вниз. Соседние отметки ПЕРЕКРЫВАЮТСЯ по x — только в перекрытии
## можно поставить лестницу.
const PLATFORMS: Array = [
	{"mark": 6, "x0": 0, "x1": 8},
	{"mark": 5, "x0": 0, "x1": 9},
	{"mark": 4, "x0": 0, "x1": 10},
	{"mark": 3, "x0": 0, "x1": 11},
	{"mark": 2, "x0": 0, "x1": 12},
	{"mark": 1, "x0": 0, "x1": 13},
	{"mark": 0, "x0": 0, "x1": 16},      # кромка: сюда выносит плавник
	# x0 = 0 у ярусов утёса не случайность: под площадкой рисуется сплошная
	# порода, и без колонок 0..1 утёс «висит» в воздухе у левого края экрана.
	{"mark": -1, "x0": 13, "x1": 22},    # пляж
	{"mark": -2, "x0": 18, "x1": 27},    # пляж
	{"mark": -3, "x0": 23, "x1": 32},    # отмель
	{"mark": -4, "x0": 27, "x1": 36},    # отмель
	{"mark": -5, "x0": 30, "x1": 40},    # отмель / кромка руин
	{"mark": -6, "x0": 33, "x1": 43},    # руины
	{"mark": -7, "x0": 36, "x1": 45},    # руины
	{"mark": -8, "x0": 38, "x1": 47},    # глубокие руины
]

## РЕШЕНИЕ: лестница-«ступени утёса» в колонке x=4 идёт от +6 до 0 и считается
## частью карты. docs/00 §11.1 перечисляет как стартовую постройку только
## «деревянную лестницу до −2», но без связности утёса колония на тике 0
## распадается на 7 изолированных площадок. Стройка/шторм этапа 07 отличат
## их по отметке: ниже 0 — постройки игрока, выше — рельеф.
const LADDERS: Array = [
	{"x": 4, "mark_top": 6}, {"x": 4, "mark_top": 5}, {"x": 4, "mark_top": 4},
	{"x": 4, "mark_top": 3}, {"x": 4, "mark_top": 2}, {"x": 4, "mark_top": 1},
	{"x": 14, "mark_top": 0},     # стартовая деревянная лестница...
	{"x": 20, "mark_top": -1},    # ...до отметки −2
]

## Чем глубже депозит, тем дальше он от лестниц: спуск за глубоким утилем
## должен стоить времени, иначе давление отлива не работает.
const DEPOSITS: Array = [
	{"kind": "shallow", "mark": -1, "x": 21},
	{"kind": "kelp", "mark": -2, "x": 22},
	{"kind": "ruins_near", "mark": -2, "x": 26},
	{"kind": "shallow", "mark": -3, "x": 24},
	{"kind": "ruins_near", "mark": -3, "x": 31},
	{"kind": "ruins_near", "mark": -4, "x": 35},
	{"kind": "kelp", "mark": -5, "x": 39},
	{"kind": "ruins_deep", "mark": -6, "x": 42},
	{"kind": "ruins_deep", "mark": -7, "x": 44},
	{"kind": "ruins_deep", "mark": -8, "x": 46},
]

const OUT_PATH: String = "res://data/cliffs/cliff_01.tres"

func _initialize() -> void:
	var def: CliffDef = CliffDef.new()
	def.id = "cliff_01"
	def.width = 48
	def.height = 45
	def.spawn_cell = Vector2i(6, Balance.mark_to_floor_cell_y(2))
	def.start_storage_cell = Vector2i(9, Balance.mark_to_floor_cell_y(2))
	# Стартовые постройки (docs/00 §11.1). Клетка — ВЕРХНИЙ левый угол:
	# постройка опирается нижним рядом на пол яруса.
	def.start_buildings = [
		{"def_id": "storage", "cell": Vector2i(9, Balance.mark_to_floor_cell_y(2) - 2)},
		{"def_id": "hearth", "cell": Vector2i(4, Balance.mark_to_floor_cell_y(2) - 1)},
		{"def_id": "raincatcher", "cell": Vector2i(2, Balance.mark_to_floor_cell_y(4) - 1)},
	]

	var ok: bool = true
	for p: Variant in PLATFORMS:
		def.platforms.append((p as Dictionary).duplicate())
	for l: Variant in LADDERS:
		def.start_ladders.append((l as Dictionary).duplicate())
	for d: Variant in DEPOSITS:
		def.deposit_slots.append((d as Dictionary).duplicate())

	ok = _validate(def) and ok
	if not ok:
		push_error("карта не прошла проверку, файл не записан")
		quit(1)
		return

	var err: int = ResourceSaver.save(def, OUT_PATH)
	if err != OK:
		push_error("ResourceSaver.save: код %d" % err)
		quit(1)
		return
	print("карта записана: ", OUT_PATH)
	quit(0)

## Проверки, которые дешевле сделать здесь, чем ловить как «агент проваливается
## сквозь площадку» на этапе 05.
func _validate(def: CliffDef) -> bool:
	var ok: bool = true
	var by_mark: Dictionary = {}
	for p: Dictionary in def.platforms:
		var m: int = int(p["mark"])
		if by_mark.has(m):
			push_error("две площадки на отметке %d" % m)
			ok = false
		by_mark[m] = p
		if int(p["x0"]) < 0 or int(p["x1"]) >= def.width or int(p["x0"]) > int(p["x1"]):
			push_error("площадка %d выходит за карту" % m)
			ok = false
	for m: int in range(Balance.BOTTOM_MARK, Balance.TOP_MARK + 1):
		if not by_mark.has(m):
			push_error("нет площадки на отметке %d" % m)
			ok = false

	for l: Dictionary in def.start_ladders:
		var top: int = int(l["mark_top"])
		var x: int = int(l["x"])
		for m2: int in [top, top - 1]:
			if not by_mark.has(m2):
				push_error("лестница x=%d ведёт в никуда (отметка %d)" % [x, m2])
				ok = false
				continue
			var p2: Dictionary = by_mark[m2]
			if x < int(p2["x0"]) or x > int(p2["x1"]):
				push_error("лестница x=%d висит в воздухе на отметке %d" % [x, m2])
				ok = false

	var seen_cells: Dictionary = {}
	for d: Dictionary in def.deposit_slots:
		var kind: String = str(d["kind"])
		var m3: int = int(d["mark"])
		var x3: int = int(d["x"])
		if not Balance.DEPOSIT_KINDS.has(kind):
			push_error("неизвестный вид депозита '%s'" % kind)
			ok = false
			continue
		var kd: Dictionary = Balance.DEPOSIT_KINDS[kind]
		if m3 > int(kd["mark_hi"]) or m3 < int(kd["mark_lo"]):
			push_error("депозит %s на отметке %d вне диапазона %d..%d" % [
				kind, m3, int(kd["mark_lo"]), int(kd["mark_hi"])])
			ok = false
		if not by_mark.has(m3):
			push_error("депозит %s на отметке %d без площадки" % [kind, m3])
			ok = false
			continue
		var p3: Dictionary = by_mark[m3]
		if x3 < int(p3["x0"]) or x3 > int(p3["x1"]):
			push_error("депозит %s вне площадки: x=%d, отметка %d" % [kind, x3, m3])
			ok = false
		var key: String = "%d:%d" % [m3, x3]
		if seen_cells.has(key):
			push_error("два депозита в одной клетке: %s" % key)
			ok = false
		seen_cells[key] = true
	return ok
