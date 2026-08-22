class_name CardView
extends PanelContainer
## Карта Плана вылазки. Выбор двухшаговый (тап выделяет, кнопка подтверждает) —
## защита от промаха на телефоне (docs/03 §4.2), поэтому компонент отдельно
## сообщает о выделении и не «выбирает» сам.

signal picked(card_id: String)

var card_id: String = ""
var rare: bool = false

var _title: Label = null
var _desc: Label = null
var _tag: Label = null
var _title_key: String = ""
var _desc_key: String = ""
var _selected: bool = false
var _accent: StyleBoxFlat = null

func _ready() -> void:
	_build()

func _build() -> void:
	if _title != null:
		return
	theme_type_variation = &"CardPanel"
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(220.0, 180.0)
	if not gui_input.is_connected(_on_gui_input):
		gui_input.connect(_on_gui_input)
	var box: VBoxContainer = VBoxContainer.new()
	box.name = "Box"
	add_child(box)
	_title = Label.new()
	_title.name = "Title"
	_title.theme_type_variation = &"LabelTitle"
	UILayout.wrap(_title, 190.0)
	box.add_child(_title)
	_desc = Label.new()
	_desc.name = "Desc"
	UILayout.wrap(_desc, 190.0)
	_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_desc)
	_tag = Label.new()
	_tag.name = "Tag"
	_tag.theme_type_variation = &"LabelSmall"
	box.add_child(_tag)

func setup(id: String, title_key: String, desc_key: String, is_rare: bool) -> void:
	_build()
	card_id = id
	_title_key = title_key
	_desc_key = desc_key
	rare = is_rare
	_apply_style()
	_refresh_texts()

func set_selected(on: bool) -> void:
	_selected = on
	_apply_style()

func is_selected() -> bool:
	return _selected

## Редкая карта — своя рамка (docs/03 §4.2). Стиль собирается из токенов,
## а не задаётся в сцене.
func _apply_style() -> void:
	var border: Color = UITokens.BORDER
	if rare:
		border = UIPalette.warm()
	if _selected:
		border = UIPalette.accent()
	_accent = UIThemeFactory.flat(UITokens.RAISE, border,
		UITokens.BORDER_FOCUS if _selected else UITokens.BORDER_W, UITokens.SPACE_4)
	add_theme_stylebox_override("panel", _accent)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh_texts()

func _refresh_texts() -> void:
	if _title == null:
		return
	_title.text = tr(_title_key)
	_desc.text = tr(_desc_key)
	_tag.text = tr("UI_CARD_RARE") if rare else ""

func _on_gui_input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null and touch.pressed:
		picked.emit(card_id)
		accept_event()
		return
	if event.is_action_pressed("ui_accept"):
		picked.emit(card_id)
		accept_event()
