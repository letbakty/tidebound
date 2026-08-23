class_name BottomSheet
extends PixelPanel
## Лист снизу. Форма разведена по устройству, как и требует таблица docs/01 §3:
##
##   ПК   — нижняя ПАНЕЛЬ: треть высоты, фиксированная, не во всю ширину.
##   тач  — bottom sheet: тянется пальцем между четвертью и половиной экрана.
##
## ⚠️ Полэкрана во всю ширину — форма для пальца, и на ПК она давала карточку
## агента 1280×420 (58% высоты) поверх кнопки «Отзыв».
##
## Правый нижний угол не занимаем НИКОГДА и ни на каком устройстве: там живёт
## «Отзыв», и попап поверх него — прямой антипаттерн Fallout Shelter
## (docs/01 §2). Слева на ПК не закрываем колонку шкалы прилива — это «лицо»
## игры и единственный прибор планирования.
##
## Хват — только за шапку: если тянуть за всю панель, скролл содержимого
## начнёт таскать лист (research/21 §7).

const SNAP: Array[float] = [0.25, 0.5]
## Доля высоты окна под нижнюю панель на ПК.
const DESK_RATIO: float = 1.0 / 3.0

var _height_ratio: float = SNAP[1]
var _drag_from: float = INF
var _height_at_drag: float = 0.0
## Тянется пальцем только на таче: на ПК высота фиксированная.
var _draggable: bool = false

func _ready() -> void:
	super()
	_draggable = OS.has_feature("mobile")
	_height_ratio = SNAP[1] if _draggable else DESK_RATIO
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_layout()
	# Окно меняет размер — вместе с ним и доля высоты, и вырезы по краям.
	get_tree().root.size_changed.connect(_apply_layout)

## Горизонталь панели. offset_* поверх PRESET_BOTTOM_WIDE: якоря остаются
## растянутыми, а края отступают от мёртвой зоны и от шкалы прилива.
func _apply_layout() -> void:
	offset_right = -float(UITokens.DEADZONE_PX)
	offset_left = 0.0 if _draggable \
		else float(UITokens.TIDE_WIDTH + UITokens.SPACE_4)
	_apply_height(false)

func _on_header_input(event: InputEvent) -> void:
	if not _draggable:
		return                          # на ПК высота панели фиксированная
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			_drag_from = touch.position.y
			_height_at_drag = size.y
		else:
			_drag_from = INF
			_snap_to_nearest()
		return
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if drag != null and _drag_from != INF:
		var view_h: float = maxf(get_viewport_rect().size.y, 1.0)
		_height_ratio = clampf(
			(_height_at_drag + (_drag_from - drag.position.y)) / view_h,
			SNAP[0] * 0.6, SNAP[1] * 1.4)
		_apply_height(false)

func _snap_to_nearest() -> void:
	# Утащили ниже минимальной ступени — это «закрыть», а не «сжать в полоску».
	if _height_ratio < SNAP[0] * 0.75:
		_height_ratio = SNAP[0]
		_apply_height(false)
		closed.emit()
		return
	var best: float = SNAP[0]
	for s: float in SNAP:
		if absf(s - _height_ratio) < absf(best - _height_ratio):
			best = s
	_height_ratio = best
	_apply_height(true)

func _apply_height(animated: bool) -> void:
	var target: float = get_viewport_rect().size.y * _height_ratio
	if not animated or Settings.reduce_motion:
		custom_minimum_size = Vector2(0.0, target)
		return
	var tw: Tween = create_tween()
	tw.tween_property(self, "custom_minimum_size:y", target,
		UITokens.MOTION_PANEL_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
