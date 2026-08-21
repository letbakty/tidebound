class_name GamepadCursor
extends Control
## Виртуальный курсор геймпада (docs/00 §13, промпт 16 п.2): правый стик водит
## его по экрану, A — тап в эту точку.
##
## Курсор появляется, только когда игрок взялся за геймпад: на мыши он был бы
## вторым указателем и мешал.

signal tapped(screen_pos: Vector2)

const SPEED_PX: float = 720.0
const DEAD_ZONE: float = 0.2
const SIZE_PX: float = 18.0

var active: bool = false

var _pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_pos = get_viewport_rect().size * 0.5
	set_process(true)

## Зовётся InputService'ом при смене устройства ввода.
func set_active(on: bool) -> void:
	active = on
	visible = on
	queue_redraw()

func position_on_screen() -> Vector2:
	return _pos

func _process(delta: float) -> void:
	if not active:
		return
	var v: Vector2 = Input.get_vector("cursor_left", "cursor_right",
		"cursor_up", "cursor_down")
	if v.length() < DEAD_ZONE:
		return
	_pos += v * SPEED_PX * delta
	# Целые пиксели: дробная позиция курсора в пиксель-арте «кипит».
	_pos = _pos.clamp(Vector2.ZERO, get_viewport_rect().size).round()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("cursor_tap"):
		tapped.emit(_pos)
		get_viewport().set_input_as_handled()

func _draw() -> void:
	if not active:
		return
	# Крест, а не точка: на пёстром фоне точка теряется.
	draw_line(_pos - Vector2(SIZE_PX, 0.0), _pos + Vector2(SIZE_PX, 0.0),
		UITokens.PAPER, 4.0)
	draw_line(_pos - Vector2(0.0, SIZE_PX), _pos + Vector2(0.0, SIZE_PX),
		UITokens.PAPER, 4.0)
	draw_line(_pos - Vector2(SIZE_PX, 0.0), _pos + Vector2(SIZE_PX, 0.0),
		UITokens.ACCENT, 2.0)
	draw_line(_pos - Vector2(0.0, SIZE_PX), _pos + Vector2(0.0, SIZE_PX),
		UITokens.ACCENT, 2.0)
