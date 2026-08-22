class_name SpoilPie
extends Control
## Пирог-таймер порчи: сколько циклов у стака осталось. Форма несёт смысл
## наравне с цветом — доля круга видна и в оттенках серого (docs/01 §6).

const SIZE_PX: int = 16

var _left: int = 0
var _total: int = 0

## ⚠️ PASS, а не IGNORE: на IGNORE нода не попадает в хит-тест, и тултип
## «сколько циклов осталось» не показывался вовсе (аудит B2.9). PASS оставляет
## тап проходить дальше — слот склада по-прежнему кликается.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(float(SIZE_PX), float(SIZE_PX))

func setup(left: int, total: int) -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(float(SIZE_PX), float(SIZE_PX))
	_left = left
	_total = maxi(total, 1)
	tooltip_text = "STORAGE_SPOIL"
	queue_redraw()

func _draw() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.5 - 1.0
	var t: float = clampf(float(_left) / float(_total), 0.0, 1.0)
	draw_arc(center, radius, 0.0, TAU, 24, UITokens.BORDER, 1.0)
	if t <= 0.0:
		return
	var points: PackedVector2Array = PackedVector2Array([center])
	var steps: int = maxi(int(24.0 * t), 2)
	for i: int in steps + 1:
		var a: float = -TAU * 0.25 + TAU * t * (float(i) / float(steps))
		points.append(center + Vector2(cos(a), sin(a)) * radius)
	draw_colored_polygon(points, UIPalette.warm() if t > 0.34 else UIPalette.danger())
