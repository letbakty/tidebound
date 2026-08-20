class_name DebugOverlay
extends Node2D
## Оверлеи мира: граф навигации, отметки ярусов, остатки депозитов, затопление.
##
## Живёт ВНУТРИ World (в мировом SubViewport), а не на DebugLayer: рисует
## мировые координаты и получает трансформацию камеры бесплатно. На CanvasLayer
## пришлось бы переводить мир→экран вручную каждый кадр (research/13 §2).

const COL_EDGE: Color = Color("7fd8a0", 0.85)
const COL_NODE: Color = Color("e8eff0", 0.9)
const COL_MARK: Color = Color("ffcc66", 0.55)
const COL_DEPOSIT: Color = Color("ffffff", 0.95)
const COL_FLOOD: Color = Color("3aa0d8", 0.22)

var show_graph: bool = false
var show_marks: bool = false
var show_deposits: bool = false
var show_flood: bool = false

var _dirty: bool = false
var _font: Font = ThemeDB.fallback_font
var _font_size: int = ThemeDB.fallback_font_size

func _ready() -> void:
	z_index = 100
	# unbind(n) отбрасывает лишние аргументы: подключить сигнал с аргументами
	# к методу без них напрямую нельзя — обработчик молча не вызовется.
	Events.water_level_changed.connect(_mark_dirty.unbind(1))
	Events.deposit_changed.connect(_mark_dirty.unbind(1))
	Events.phase_changed.connect(_mark_dirty.unbind(2))
	Events.building_placed.connect(_mark_dirty.unbind(1))
	Events.run_started.connect(_mark_dirty.unbind(1))

func set_flag(name: String, on: bool) -> void:
	match name:
		"graph": show_graph = on
		"marks": show_marks = on
		"deposits": show_deposits = on
		"flood": show_flood = on
		_: push_warning("DebugOverlay: неизвестный оверлей '%s'" % name)
	queue_redraw()

func _mark_dirty() -> void:
	_dirty = true

func _process(_delta: float) -> void:
	# Пачка событий одного кадра схлопывается в одну перерисовку. Здесь же
	# единственное место, куда добавить «не чаще 10 Гц», если станет тяжело.
	if _dirty:
		_dirty = false
		queue_redraw()

func _draw() -> void:
	# Ничего не включено — ноль работы, включая обход площадок.
	if not (show_graph or show_marks or show_deposits or show_flood):
		return
	if Game.world == null:
		return
	var t: Terrain = Game.world.terrain
	if show_flood:
		_draw_flood(t, Game.world.tide.level)
	if show_marks:
		_draw_marks(t)
	if show_graph:
		_draw_graph(t)
	if show_deposits:
		_draw_deposits(t)

func _platform_center(p: Dictionary) -> Vector2:
	return Vector2(
		float(int(p["x0"]) + int(p["x1"]) + 1) * 0.5 * float(WorldGeo.TILE),
		float(Balance.mark_to_floor_cell_y(int(p["mark"])) * WorldGeo.TILE))

func _draw_graph(t: Terrain) -> void:
	for l: Dictionary in t.ladders:
		var a: int = t.platform_of_mark(int(l["mark_top"]))
		var b: int = t.platform_of_mark(int(l["mark_top"]) - 1)
		if a < 0 or b < 0:
			continue
		draw_line(_platform_center(t.platforms[a]), _platform_center(t.platforms[b]),
			COL_EDGE, 2.0)
	for p: Dictionary in t.platforms:
		var c: Vector2 = _platform_center(p)
		draw_circle(c, 4.0, COL_EDGE, true)
		_text(c + Vector2(6.0, -6.0), "#%d" % int(p["id"]), COL_NODE)

func _draw_marks(t: Terrain) -> void:
	var right: float = float(Game.cliff_def().width * WorldGeo.TILE)
	for p: Dictionary in t.platforms:
		var mark: int = int(p["mark"])
		var y: float = WorldGeo.mark_to_world_y(float(mark))
		draw_line(Vector2(0.0, y), Vector2(right, y), COL_MARK, 1.0)
		_text(Vector2(2.0, y), "%+d" % mark, COL_MARK)

func _draw_deposits(t: Terrain) -> void:
	for d: Dictionary in t.deposits:
		var pos: Vector2 = WorldGeo.cell_to_world(d["cell"] as Vector2i)
		_text(pos + Vector2(2.0, float(WorldGeo.TILE)), str(int(d["amount"])), COL_DEPOSIT)

## Затопление зависит только от отметки, поэтому ярус тонет целиком —
## один прямоугольник на площадку вместо заливки по клеткам.
func _draw_flood(t: Terrain, level: float) -> void:
	for p: Dictionary in t.platforms:
		var mark: int = int(p["mark"])
		var cell: Vector2i = Vector2i(int(p["x0"]), Balance.mark_to_floor_cell_y(mark))
		if not t.is_flooded(cell, level):
			continue
		var x0: float = float(int(p["x0"]) * WorldGeo.TILE)
		var w: float = float((int(p["x1"]) - int(p["x0"]) + 1) * WorldGeo.TILE)
		var y0: float = float(Balance.mark_to_first_cell_y(mark) * WorldGeo.TILE)
		draw_rect(Rect2(x0, y0, w, float(WorldGeo.PX_PER_MARK)), COL_FLOOD, true)

## draw_string рисует по базовой линии, а не по верху текста: без сдвига
## подпись отметки окажется выше своей линии.
func _text(pos: Vector2, s: String, col: Color) -> void:
	draw_string(_font, pos + Vector2(0.0, float(_font_size) * 0.35), s,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size, col)
