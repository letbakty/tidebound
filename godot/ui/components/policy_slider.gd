class_name PolicySlider
extends VBoxContainer
## Политика: четыре крупные ступени 0..3 и подпись выбранного значения словами.
##
## Ступени сделаны кнопками, а не HSlider: на таче попасть в ступень пальцем
## надёжнее, чем тащить ручку, а цель 48 dp получается сама собой.

signal value_picked(policy: int, value: int)

const STEPS: int = 4

var policy: int = 0
var value: int = 0

var _name: Label = null
var _desc: Label = null
var _steps: Array[Button] = []
var _name_key: String = ""
## Callable(policy: int, value: int) -> String: словарь описаний живёт в панели,
## компонент своих текстов не сочиняет.
var _describer: Callable = Callable()

func _ready() -> void:
	_build()

func _build() -> void:
	if _name != null:
		return
	_name = Label.new()
	_name.name = "Name"
	add_child(_name)

	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Steps"
	add_child(row)
	for i: int in STEPS:
		var b: Button = Button.new()
		b.name = "Step%d" % i
		b.text = str(i)
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.custom_minimum_size = Vector2(float(UITokens.TOUCH_MIN),
			float(UITokens.TOUCH_MIN))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_ALL
		var idx: int = i
		b.pressed.connect(func() -> void: _pick(idx))
		row.add_child(b)
		_steps.append(b)

	_desc = Label.new()
	_desc.name = "Desc"
	_desc.theme_type_variation = &"LabelSmall"
	UILayout.wrap(_desc, 240.0)
	add_child(_desc)

func setup(policy_id: int, current: int, name_key: String,
		describer: Callable = Callable()) -> void:
	_build()
	policy = policy_id
	_name_key = name_key
	_describer = describer
	set_value(current)
	_refresh_texts()

## Внешнее обновление (пришло policy_changed) — без эмита сигнала обратно.
func set_value(v: int) -> void:
	_build()
	value = clampi(v, 0, STEPS - 1)
	for i: int in _steps.size():
		_steps[i].theme_type_variation = &"ButtonPrimary" if i == value else &""
		_steps[i].button_pressed = false
	_refresh_texts()

func grab_initial_focus() -> void:
	if not _steps.is_empty():
		_steps[value].grab_focus()

func _pick(v: int) -> void:
	set_value(v)
	value_picked.emit(policy, value)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh_texts()

func _refresh_texts() -> void:
	if _name == null:
		return
	_name.text = tr(_name_key) if not _name_key.is_empty() else ""
	var text: String = ""
	if _describer.is_valid():
		text = str(_describer.call(policy, value))
	_desc.text = text
