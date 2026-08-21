class_name RadialMenu
extends Control
## Радиальное меню: до шести слотов вокруг точки. Своя реализация — готовые
## аддоны писаны под 4.3 и на 4.7 не проверены (research/19 §6).
##
## Один жест: удержание открывает радиал, увод пальца в сторону и отпускание
## выбирают сектор; если палец не сдвинулся — радиал остаётся и ждёт тапа
## по слоту. Тап мимо закрывает.

signal slot_picked(index: int)
signal cancelled()

const MAX_SLOTS: int = 6
const RADIUS: float = 96.0
const SLOT_R: float = 30.0
## Мёртвая зона в центре обязательна: без неё дрожание пальца выбирает
## случайный сектор (research/19 §6).
const DEAD_ZONE: float = 28.0
const OUTER_LIMIT: float = 168.0

var _slots: Array[Dictionary] = []
var _center: Vector2 = Vector2.ZERO
var _press_pos: Vector2 = Vector2.INF
var _hover: int = -1
var _pad_focus: int = -1
var _font: Font = null
var _font_size: int = UITokens.FONT_S

func _ready() -> void:
	_apply_defaults()
	_apply_theme()

func _apply_defaults() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	visible = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_apply_theme()

func _apply_theme() -> void:
	_font = get_theme_font("font", "Label")
	_font_size = get_theme_font_size("font_size", "Label")
	queue_redraw()

## slots: [{"label": ключ локализации, "letter": String, "color": Color,
##          "enabled": bool}]. Недоступные слоты владелец сюда не кладёт вовсе.
## gesture_active — палец/ПКМ ещё удерживаются: отпускание сразу выберет сектор.
func setup(slots: Array[Dictionary]) -> void:
	_apply_defaults()
	_slots = slots.slice(0, MAX_SLOTS)
	queue_redraw()

func open_at(center: Vector2, slots: Array[Dictionary], gesture_active: bool = false) -> void:
	setup(slots)
	_center = center
	_press_pos = center if gesture_active else Vector2.INF
	_hover = -1
	_pad_focus = -1
	visible = true
	if is_inside_tree():
		grab_focus()
	queue_redraw()

func close() -> void:
	visible = false
	_slots.clear()
	_press_pos = Vector2.INF
	_hover = -1
	_pad_focus = -1

func is_open() -> bool:
	return visible

## Точка, вокруг которой раскрыт радиал — нужна владельцу при смене страницы.
func center() -> Vector2:
	return _center

# --- Геометрия ------------------------------------------------------------

## Угол считаем от верха по часовой; fposmod, а не fmod: для отрицательных
## fmod даёт отрицательное и верхний левый сектор отдаёт −1 (research/19 §6).
func _sector_at(pos: Vector2) -> int:
	if _slots.is_empty():
		return -1
	var v: Vector2 = pos - _center
	var d: float = v.length()
	if d < DEAD_ZONE or d > OUTER_LIMIT:
		return -1
	var a: float = fposmod(v.angle() + TAU * 0.25, TAU)
	return mini(int(a / (TAU / float(_slots.size()))), _slots.size() - 1)

func _slot_center(index: int) -> Vector2:
	var step: float = TAU / float(maxi(_slots.size(), 1))
	var a: float = -TAU * 0.25 + step * (float(index) + 0.5)
	return _center + Vector2(cos(a), sin(a)) * RADIUS

func _slot_at(pos: Vector2) -> int:
	for i: int in _slots.size():
		if pos.distance_to(_slot_center(i)) <= SLOT_R:
			return i
	return -1

# --- Ввод -----------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			_press_pos = touch.position
			_hover = -1
		else:
			_release(touch.position)
		accept_event()
		return
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if drag != null:
		_hover = _sector_at(drag.position)
		queue_redraw()
		accept_event()

## Один обработчик отпускания на оба случая — тап по слоту и увод в сектор
## (research/19 §6): два режима расходятся и ловят баги.
func _release(pos: Vector2) -> void:
	var moved: bool = _press_pos != Vector2.INF \
		and _press_pos.distance_to(pos) > DEAD_ZONE
	var index: int = _sector_at(pos) if moved else _slot_at(pos)
	_press_pos = Vector2.INF
	_hover = -1
	if index >= 0 and index < _slots.size():
		_pick(index)
		return
	if not moved:
		# Тап мимо слотов закрывает; движение «в никуда» — просто отмена выбора.
		close()
		cancelled.emit()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		cancelled.emit()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept") and _pad_focus >= 0:
		_pick(_pad_focus)
		get_viewport().set_input_as_handled()

## Геймпад: сектор выбирается стиком той же формулой, что и пальцем.
func _process(_delta: float) -> void:
	if not visible or _slots.is_empty():
		return
	var v: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if v.length() < 0.5:
		return
	var index: int = _sector_at(_center + v.normalized() * RADIUS)
	if index != _pad_focus:
		_pad_focus = index
		queue_redraw()

func _pick(index: int) -> void:
	var slot: Dictionary = _slots[index]
	if not bool(slot.get("enabled", true)):
		return
	close()
	slot_picked.emit(index)

# --- Отрисовка ------------------------------------------------------------

func _draw() -> void:
	if _slots.is_empty():
		return
	draw_circle(_center, DEAD_ZONE, Color(UITokens.PAPER.r, UITokens.PAPER.g,
		UITokens.PAPER.b, 0.75))
	draw_arc(_center, DEAD_ZONE, 0.0, TAU, 24, UITokens.BORDER, 1.0)
	for i: int in _slots.size():
		_draw_slot(i)

func _draw_slot(index: int) -> void:
	var slot: Dictionary = _slots[index]
	var c: Vector2 = _slot_center(index)
	var enabled: bool = bool(slot.get("enabled", true))
	var active: bool = index == _hover or index == _pad_focus
	var fill: Color = UITokens.panel_color()
	var border: Color = UITokens.ACCENT if active else UITokens.BORDER
	if not enabled:
		border = UITokens.DIVIDER
	var rect: Rect2 = Rect2(c - Vector2(SLOT_R, SLOT_R), Vector2(SLOT_R, SLOT_R) * 2.0)
	draw_rect(rect, fill, true)
	draw_rect(rect, border, false, float(UITokens.BORDER_W))
	if _font == null:
		return
	var tint: Color = slot.get("color", UITokens.INK) as Color
	if not enabled:
		tint = UITokens.FAINT
	var letter: String = str(slot.get("letter", "?"))
	var ls: Vector2 = _font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, _font_size)
	draw_string(_font, Vector2(roundf(c.x - ls.x * 0.5), roundf(c.y + float(_font_size) * 0.3)),
		letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size, tint)
	var label: String = tr(str(slot.get("label", "")))
	var lw: Vector2 = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, _font_size)
	draw_string(_font, Vector2(roundf(c.x - lw.x * 0.5), roundf(c.y + SLOT_R + float(_font_size))),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size,
		UITokens.INK if enabled else UITokens.FAINT)
