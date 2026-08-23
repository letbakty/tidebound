class_name BuildGhost
extends Node2D
## Призрак размещения: следует за курсором, зелёный/красный по can_place.
## Полноценный радиал стройки — этап 14; сюда его подключит InputService.

const OK_COLOR: Color = Color(0.45, 1.0, 0.5, 0.55)
const BAD_COLOR: Color = Color(1.0, 0.4, 0.4, 0.55)
## Пунктир до складов с материалами — паттерн Against the Storm: игрок сразу
## видит, откуда понесут (промпт 14 п.2).
const LINE_COLOR: Color = Color(0.91, 0.76, 0.44, 0.5)
const DASH_PX: float = 6.0

var def_id: String = ""
## Клетки складов, где лежит нужное. Считаются при смене постройки, а не
## каждый кадр: запрос в sim дорог, а склады за кадр не переезжают.
var _sources: Array[Vector2i] = []
var _error_key: String = ""
var _font: Font = ThemeDB.fallback_font

var _rect: ColorRect = null
var _last_cell: Vector2i = Vector2i(-9999, -9999)
var _cursor_world: Vector2 = Vector2.ZERO
var _use_mouse: bool = true

func _ready() -> void:
	z_index = 90
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	visible = false

func set_def(id: String) -> void:
	def_id = id
	visible = not id.is_empty()
	_last_cell = Vector2i(-9999, -9999)
	_sources = Game.query_material_sources(id) if visible else ([] as Array[Vector2i])
	_error_key = ""
	queue_redraw()
	if visible:
		var d: BuildingDef = DB.building(id)
		if d != null:
			_rect.size = Vector2(d.size) * float(WorldGeo.TILE)

## Для тача и курсора геймпада (этап 16): позиция берётся от последнего
## касания, а не от мыши — ховера у них нет.
##
## Клетка пересчитывается СРАЗУ, не ожидая кадра: тап по миру и ставит
## постройку, и показывает её валидность, и обе вещи обязаны говорить об одной
## и той же клетке (docs/01 §3).
func set_cursor_world(pos: Vector2) -> void:
	_use_mouse = false
	_cursor_world = pos
	_refresh(pos)

## Обратно к мыши. ⚠️ Без этого переключения призрак после первого же выбора
## постройки замирал в точке, где открыли радиал, до конца забега: мышью
## поставить что-либо туда, куда смотришь, было нельзя.
func follow_mouse() -> void:
	_use_mouse = true

## Клетка, которую игрок ВИДИТ подсвеченной. Единственный источник правды при
## размещении: клетка клика может отличаться округлением (docs/01 §3).
func current_cell() -> Vector2i:
	return _last_cell

## Причина отказа для текущей клетки; "" — можно ставить.
func error_key() -> String:
	return _error_key

func _process(_delta: float) -> void:
	if def_id.is_empty():
		return
	_refresh(get_global_mouse_position() if _use_mouse else _cursor_world)

func _refresh(world_pos: Vector2) -> void:
	if def_id.is_empty():
		return
	var cell: Vector2i = WorldGeo.world_to_cell(world_pos)
	# Гейт по клетке: без него призрак дёргает sim шестьдесят раз в секунду
	# вместо одного раза на переход между клетками.
	if cell == _last_cell:
		return
	_last_cell = cell
	position = WorldGeo.cell_to_world(cell)
	_error_key = Game.query_place_error(def_id, cell)
	_rect.color = OK_COLOR if _error_key.is_empty() else BAD_COLOR
	# Пунктир до складов считается в _draw через to_local, поэтому после
	# переезда призрака он сам пересчитывается от новой точки; _sources от
	# позиции не зависит вовсе (Game.query_material_sources берёт def_id).
	queue_redraw()

## Пунктирные линии до складов с материалами и причина отказа текстом.
func _draw() -> void:
	if def_id.is_empty():
		return
	var from: Vector2 = _rect.size * 0.5
	for cell: Vector2i in _sources:
		var to: Vector2 = to_local(WorldGeo.cell_center_world(cell))
		var total: float = from.distance_to(to)
		var dir: Vector2 = (to - from).normalized()
		var t: float = 0.0
		while t < total:
			var seg: float = minf(DASH_PX, total - t)
			draw_line(from + dir * t, from + dir * (t + seg), LINE_COLOR, 1.0)
			t += DASH_PX * 2.0
	if _error_key.is_empty():
		return
	draw_string(_font, Vector2(0.0, -4.0), tr(_error_key),
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, ThemeDB.fallback_font_size, BAD_COLOR)
