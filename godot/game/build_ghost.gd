class_name BuildGhost
extends Node2D
## Призрак размещения: следует за курсором, зелёный/красный по can_place.
## Полноценный радиал стройки — этап 14; сюда его подключит InputService.

const OK_COLOR: Color = Color(0.45, 1.0, 0.5, 0.55)
const BAD_COLOR: Color = Color(1.0, 0.4, 0.4, 0.55)

var def_id: String = ""

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
	if visible:
		var d: BuildingDef = DB.building(id)
		if d != null:
			_rect.size = Vector2(d.size) * float(WorldGeo.TILE)

## Для тача (этап 16): позиция берётся от последнего касания, а не от мыши.
func set_cursor_world(pos: Vector2) -> void:
	_use_mouse = false
	_cursor_world = pos

func current_cell() -> Vector2i:
	return _last_cell

func _process(_delta: float) -> void:
	if def_id.is_empty():
		return
	var world_pos: Vector2 = get_global_mouse_position() if _use_mouse else _cursor_world
	var cell: Vector2i = WorldGeo.world_to_cell(world_pos)
	# Гейт по клетке: без него призрак дёргает sim шестьдесят раз в секунду
	# вместо одного раза на переход между клетками.
	if cell == _last_cell:
		return
	_last_cell = cell
	position = WorldGeo.cell_to_world(cell)
	_rect.color = OK_COLOR if Game.query_can_place(def_id, cell) else BAD_COLOR
