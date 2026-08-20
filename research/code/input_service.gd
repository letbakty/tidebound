class_name InputService
extends Node
## Распознавание жестов поверх мира. Переносить в res://ui/input_service.gd (этап 12).
##
## НОДА в Main, а НЕ автолоад: автолоад висел бы на /root и получал _input раньше
## всего GUI, съедая события у панелей. Ставить ПЕРВЫМ ребёнком Main (тогда среди
## детей обрабатывается последним — панели имеют приоритет).
##
## Сервис ничего не вызывает напрямую: только эмитит свои сигналы.

signal world_tapped(pos: Vector2)
signal world_double_tapped(pos: Vector2)
signal world_long_pressed(pos: Vector2)
signal long_press_progress(pos: Vector2, t: float)      # 0..1 — индикатор у пальца
signal world_dragged(delta: Vector2)
signal zoom_step(delta: int)                            # +1 / -1, ступенями
signal edge_swipe_right()
signal device_changed(device: int)

enum Device { KEYBOARD, TOUCH, PAD }

const LONG_PRESS_SEC: float = 0.5
const MOVE_TOLERANCE_PX: float = 12.0        # палец всегда немного ползёт
const PINCH_STEP_PX: float = 60.0
const EDGE_ZONE_PX: float = 24.0
const EDGE_SWIPE_PX: float = 80.0

var device: Device = Device.KEYBOARD

var _touches: Dictionary[int, Vector2] = {}  # index -> позиция; erase по index,
                                             # счётчик инкрементами залипает
var _lp_index: int = -1
var _lp_start: Vector2 = Vector2.ZERO
var _lp_time: float = 0.0
var _pinch_ref: float = -1.0
var _edge_start: Vector2 = Vector2.INF

func _process(delta: float) -> void:
	if _lp_index == -1:
		return
	_lp_time += delta
	long_press_progress.emit(_lp_start, minf(_lp_time / LONG_PRESS_SEC, 1.0))
	if _lp_time >= LONG_PRESS_SEC:
		world_long_pressed.emit(_lp_start)
		_lp_index = -1                       # срабатывает один раз

func _input(event: InputEvent) -> void:
	_track_device(event)

## _unhandled_input, а не _input: жест по миру не должен срабатывать сквозь панель
## и не должен перехватывать ввод у LineEdit под фокусом.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)
	elif event is InputEventMagnifyGesture:
		# macOS-трекпад. На Android требует ProjectSettings
		# input_devices/pointing/android/enable_pan_and_scale_gestures,
		# на iOS/Windows не приходит вовсе -> пинч всё равно считаем вручную.
		var f: float = (event as InputEventMagnifyGesture).factor
		if absf(f - 1.0) > 0.15:
			zoom_step.emit(1 if f > 1.0 else -1)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_step.emit(1)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_step.emit(-1)

# --- Тач -----------------------------------------------------------------

func _on_touch(t: InputEventScreenTouch) -> void:
	if t.pressed:
		_touches[t.index] = t.position
		if _touches.size() == 1:
			_lp_index = t.index
			_lp_start = t.position
			_lp_time = 0.0
			_edge_start = t.position if _is_right_edge(t.position) else Vector2.INF
		else:
			_cancel_long_press()              # второй палец отменяет долгое нажатие
		return

	# Отпускание (или отмена системой)
	_touches.erase(t.index)
	if _touches.size() < 2:
		_pinch_ref = -1.0
	if t.canceled:                            # система забрала касание
		_cancel_long_press()
		return
	if t.index == _lp_index and _lp_index != -1:
		_cancel_long_press()
		if t.double_tap:
			world_double_tapped.emit(t.position)
		else:
			world_tapped.emit(t.position)
		get_viewport().set_input_as_handled()
	_edge_start = Vector2.INF

func _on_drag(d: InputEventScreenDrag) -> void:
	_touches[d.index] = d.position

	# Пинч имеет приоритет: пока два пальца, панорама выключена (иначе камера уедет)
	if _touches.size() >= 2:
		_cancel_long_press()
		_update_pinch()
		return

	if _lp_index == d.index and _lp_start.distance_to(d.position) > MOVE_TOLERANCE_PX:
		_cancel_long_press()                  # это уже драг, а не долгое нажатие

	if _edge_start != Vector2.INF and _edge_start.x - d.position.x > EDGE_SWIPE_PX:
		_edge_start = Vector2.INF
		edge_swipe_right.emit()
		return

	world_dragged.emit(d.relative)

func _update_pinch() -> void:
	var keys: Array = _touches.keys()
	keys.sort()                               # стабильный порядок пальцев
	var dist: float = (_touches[keys[0]] as Vector2).distance_to(_touches[keys[1]])
	if _pinch_ref < 0.0:
		_pinch_ref = dist
		return
	var delta: float = dist - _pinch_ref
	if absf(delta) >= PINCH_STEP_PX:
		zoom_step.emit(1 if delta > 0.0 else -1)
		_pinch_ref = dist                     # новый опорный => ступени, не непрерывность

func _cancel_long_press() -> void:
	if _lp_index != -1:
		_lp_index = -1
		long_press_progress.emit(_lp_start, 0.0)

func _is_right_edge(p: Vector2) -> bool:
	return p.x >= get_viewport().get_visible_rect().size.x - EDGE_ZONE_PX

# --- Активное устройство ввода (для подсказок кнопок в HUD) ----------------

func _track_device(e: InputEvent) -> void:
	var d: Device = device
	if e is InputEventJoypadButton:
		d = Device.PAD
	elif e is InputEventJoypadMotion:
		# Дрейф стика летит постоянно — без порога иконки будут мигать
		if absf((e as InputEventJoypadMotion).axis_value) > 0.5:
			d = Device.PAD
	elif e is InputEventScreenTouch or e is InputEventScreenDrag:
		d = Device.TOUCH
	elif e is InputEventKey or e is InputEventMouse:
		d = Device.KEYBOARD
	if d != device:
		device = d
		device_changed.emit(int(d))
