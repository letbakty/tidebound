class_name Toast
extends PanelContainer
## Тост: иконка, текст, счётчик группировки. Тап — к месту события,
## свайп вправо — скрыть, само гаснет через UITokens.TOAST_LIFE_SEC.

signal tapped()
signal dismissed()

enum Tone { INFO, WARN, DANGER }

const SWIPE_HIDE_PX: float = 40.0

var cell: Vector2i = Vector2i.ZERO
var tone: Tone = Tone.INFO

var _icon: IconStub = null
var _text: Label = null
var _count: Label = null
var _timer: Timer = null
var _count_value: int = 1
var _life_sec: float = UITokens.TOAST_LIFE_SEC

func _ready() -> void:
	_build()

func _build() -> void:
	if _text != null:
		return
	theme_type_variation = &"PanelRaised"
	# STOP обязателен: иначе свайп по тосту уедет в мир панорамой (research/21 §4).
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not gui_input.is_connected(_on_gui_input):
		gui_input.connect(_on_gui_input)
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Row"
	add_child(row)
	_icon = IconStub.new()
	_icon.name = "Icon"
	row.add_child(_icon)
	_text = Label.new()
	_text.name = "Text"
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_text.custom_minimum_size = Vector2(200.0, 0.0)
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_text)
	_count = Label.new()
	_count.name = "Count"
	_count.theme_type_variation = &"LabelNum"
	_count.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_count.visible = false
	row.add_child(_count)
	_timer = Timer.new()
	_timer.name = "Life"
	_timer.one_shot = true
	_timer.timeout.connect(_on_timeout)
	add_child(_timer)

## text — уже переведённая строка. life_sec = 0 — «не закрывать сам»
## (настройка доступности, docs/03 §3.6).
func setup(text: String, t: Tone, at_cell: Vector2i, life_sec: float = -1.0) -> void:
	_build()
	tone = t
	cell = at_cell
	_text.text = text
	_life_sec = _life_sec if life_sec < 0.0 else life_sec
	_icon.setup(_letter_for(t), _color_for(t), 16)
	_count_value = 1
	_count.visible = false
	restart_timer()

func set_count(n: int) -> void:
	_build()
	_count_value = n
	_count.text = "x%d" % n
	_count.visible = n > 1

func count() -> int:
	return _count_value

func restart_timer() -> void:
	_build()
	# Timer вне дерева ругается: тост может быть собран заранее и добавлен позже.
	if not is_inside_tree():
		return
	if _life_sec <= 0.0:
		_timer.stop()
		return
	_timer.start(_life_sec)

static func _letter_for(t: Tone) -> String:
	match t:
		Tone.WARN: return "!"
		Tone.DANGER: return "X"
	return "i"

static func _color_for(t: Tone) -> Color:
	match t:
		Tone.WARN: return UITokens.WARM
		Tone.DANGER: return UITokens.DANGER
	return UITokens.WATER_COLD

func _on_timeout() -> void:
	dismissed.emit()

func _on_gui_input(event: InputEvent) -> void:
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if drag != null and drag.relative.x > SWIPE_HIDE_PX:
		dismissed.emit()
		accept_event()
		return
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null and not touch.pressed:
		tapped.emit()
		accept_event()
