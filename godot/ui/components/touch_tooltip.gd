class_name TouchTooltip
extends Node
## Тултип по долгому нажатию для одного Control. На ПК тултип показывает сам
## движок по наведению, на таче наведения нет — нужен жест (docs/01 §5).
##
## Использование: add_child(TouchTooltip.new()) внутри компонента и setup(self).

const HOLD_SEC: float = 0.5
const LIFE_SEC: float = 3.0
const MOVE_TOLERANCE_PX: float = 12.0

var _target: Control = null
## Callable() -> String: уже переведённый текст. Пусто — берём tooltip_text.
var _provider: Callable = Callable()
var _press_pos: Vector2 = Vector2.INF
var _held: float = 0.0
var _tip: TooltipView = null

func setup(target: Control, text_provider: Callable = Callable()) -> void:
	_target = target
	_provider = text_provider
	if not _target.gui_input.is_connected(_on_gui_input):
		_target.gui_input.connect(_on_gui_input)

func _process(delta: float) -> void:
	if _press_pos == Vector2.INF or _target == null:
		return
	_held += delta
	if _held < HOLD_SEC:
		return
	_press_pos = Vector2.INF
	_show()

func _on_gui_input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			_press_pos = touch.position
			_held = 0.0
		else:
			_press_pos = Vector2.INF
		return
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if drag != null and _press_pos != Vector2.INF \
			and _press_pos.distance_to(drag.position) > MOVE_TOLERANCE_PX:
		_press_pos = Vector2.INF        # это драг, а не удержание

func _text() -> String:
	if _provider.is_valid():
		return str(_provider.call())
	return tr(_target.tooltip_text)

func _show() -> void:
	if _target == null or not _target.is_inside_tree():
		return
	var text: String = _text()
	if text.is_empty():
		return
	_hide()
	_tip = TooltipView.make(text)
	_target.get_viewport().add_child(_tip)
	_tip.global_position = _target.global_position + Vector2(0.0, _target.size.y)
	var timer: SceneTreeTimer = _target.get_tree().create_timer(LIFE_SEC)
	timer.timeout.connect(_hide)

func _hide() -> void:
	if _tip != null and is_instance_valid(_tip):
		_tip.queue_free()
	_tip = null
