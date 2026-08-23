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
## Кому вернуть фокус после отмены: без этого геймпад теряет курсор и
## навигация по HUD обрывается (research/20 §6, аудит B4).
var _focus_before: Control = null
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

## Перехват — ТОЛЬКО в круге вокруг центра, хотя прямоугольник во весь экран.
## ⚠️ Полноэкранный STOP накрывал весь HUD, пока радиал открыт: «Отзыв» под ним
## не нажимался. Клик снаружи радиал не блокирует — он его закрывает (_input).
##
## Прямоугольник стоит в (0,0) во весь экран, поэтому локальная точка равна
## экранной, и _center из open_at сравнивается с ней напрямую.
func _has_point(point: Vector2) -> bool:
	return visible and point.distance_to(_center) <= OUTER_LIMIT

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_apply_theme()

func _apply_theme() -> void:
	_font = get_theme_font("font", "Label")
	_font_size = get_theme_font_size("font_size", "Label")
	queue_redraw()

## slots: [{"label": ключ локализации, "letter": String, "color": Color,
##          "enabled": bool, "icon": Texture2D}]. Недоступные слоты владелец
## сюда не кладёт вовсе. "icon" необязателен: есть — рисуем его вместо буквы,
## нет — остаётся буква. Готовую текстуру кладёт владелец, чтобы компонент не
## знал ни про постройки, ни про атласы (test_ui/components_are_pure).
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
		_focus_before = get_viewport().gui_get_focus_owner()
		grab_focus()
	queue_redraw()

func close() -> void:
	visible = false
	_slots.clear()
	_press_pos = Vector2.INF
	_hover = -1
	_pad_focus = -1
	if _focus_before != null and is_instance_valid(_focus_before) \
			and _focus_before.is_visible_in_tree():
		_focus_before.grab_focus()
	_focus_before = null

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
		return
	# Мышь ведём тем же путём, что и палец: без этого на ПК радиал не
	# подсвечивал слот под курсором вовсе (аудит B4).
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and click.button_index == MOUSE_BUTTON_LEFT:
		if click.pressed:
			_press_pos = click.position
			_hover = _slot_at(click.position)
		else:
			_release(click.position)
		queue_redraw()
		accept_event()
		return
	var move: InputEventMouseMotion = event as InputEventMouseMotion
	if move != null:
		# До нажатия подсвечиваем слот под курсором, при зажатой кнопке —
		# сектор: это те же два режима, что у пальца.
		var index: int = _sector_at(move.position) if _press_pos != Vector2.INF \
			else _slot_at(move.position)
		if index != _hover:
			_hover = index
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

## «Тап мимо закрывает» (docs/01 §3). Через _gui_input такие клики больше не
## приходят — круг их не ловит, — поэтому ловим здесь и событие НЕ поглощаем:
## кнопка HUD под курсором обязана отработать тем же кликом.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var pos: Vector2 = Vector2.INF
	var pressed: bool = false
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		pos = touch.position
		pressed = touch.pressed
	else:
		var click: InputEventMouseButton = event as InputEventMouseButton
		if click == null or click.button_index != MOUSE_BUTTON_LEFT:
			return
		pos = click.position
		pressed = click.pressed
	if _has_point(pos):
		return                              # это уже работа _gui_input
	if pressed:
		close()
		cancelled.emit()
		return
	# Отпускание за кругом — конец жеста «увёл палец в никуда»: разбирает его
	# тот же _release, что и внутри, иначе два режима разойдутся.
	_release(pos)

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
	var border: Color = UIPalette.accent() if active else UITokens.BORDER
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
	var icon: Texture2D = slot.get("icon", null) as Texture2D
	if icon != null:
		# Иконка в РОДНОМ размере и по целым координатам: дробный масштаб на
		# пиксель-арте даёт «то два, то три экранных пикселя».
		var half: Vector2 = (Vector2(icon.get_size()) * 0.5).floor()
		draw_texture(icon, (c - half).floor(),
			Color(1, 1, 1, 1) if enabled else Color(1, 1, 1, 0.35))
	else:
		var letter: String = str(slot.get("letter", "?"))
		var ls: Vector2 = _font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, _font_size)
		draw_string(_font, Vector2(roundf(c.x - ls.x * 0.5),
			roundf(c.y + float(_font_size) * 0.3)),
			letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size, tint)
	var label: String = tr(str(slot.get("label", "")))
	var lw: Vector2 = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, _font_size)
	draw_string(_font, Vector2(roundf(c.x - lw.x * 0.5), roundf(c.y + SLOT_R + float(_font_size))),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size,
		UITokens.INK if enabled else UITokens.FAINT)
