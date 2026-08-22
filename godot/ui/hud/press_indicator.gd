class_name PressIndicator
extends Control
## Прогресс долгого нажатия у пальца (docs/01 §5, промпт 16 п.1): без него
## игрок не понимает, сработает жест или нет, и отпускает раньше времени.

const RADIUS: float = 22.0

var _pos: Vector2 = Vector2.ZERO
var _t: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

## Подключается к InputService.long_press_progress.
func show_progress(at: Vector2, t: float) -> void:
	_pos = at
	_t = clampf(t, 0.0, 1.0)
	visible = _t > 0.05
	queue_redraw()

func _draw() -> void:
	if _t <= 0.0:
		return
	draw_arc(_pos, RADIUS, 0.0, TAU, 32, UITokens.BORDER, 2.0)
	draw_arc(_pos, RADIUS, -TAU * 0.25, -TAU * 0.25 + TAU * _t, 32,
		UIPalette.accent(), 3.0)
