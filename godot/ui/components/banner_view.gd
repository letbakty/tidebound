class_name BannerView
extends PanelContainer
## Широкая плашка события по центру сверху (объявление кризиса).
## Автопаузу ставит владелец (HUD этапа 13) — компонент о симуляции не знает.

signal dismissed()

enum Tone { INFO, WARN, DANGER }

var _title: Label = null
var _text: Label = null
var _button: PixelButton = null
var _title_key: String = ""
var _text_key: String = ""

func _ready() -> void:
	_build()

func _build() -> void:
	if _title != null:
		return
	theme_type_variation = &"PanelDark"
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Row"
	add_child(row)
	var box: VBoxContainer = VBoxContainer.new()
	box.name = "Box"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	_title = Label.new()
	_title.name = "Title"
	_title.theme_type_variation = &"LabelTitle"
	box.add_child(_title)
	_text = Label.new()
	_text.name = "Text"
	UILayout.wrap(_text, 420.0)
	box.add_child(_text)
	_button = PixelButton.new()
	_button.name = "Ok"
	_button.setup("UI_OK", PixelButton.Variant.PRIMARY)
	_button.pressed.connect(func() -> void: dismissed.emit())
	row.add_child(_button)

func setup(title_key: String, text_key: String, tone: Tone) -> void:
	_build()
	_title_key = title_key
	_text_key = text_key
	var border: Color = UITokens.BORDER
	if tone == Tone.WARN:
		border = UITokens.WARM
	elif tone == Tone.DANGER:
		border = UITokens.DANGER
	add_theme_stylebox_override("panel",
		UIThemeFactory.flat(UITokens.PAPER, border, UITokens.BORDER_W, UITokens.SPACE_3))
	_refresh_texts()

func show_banner(title_key: String, text_key: String, tone: Tone) -> void:
	setup(title_key, text_key, tone)
	visible = true

func hide_banner() -> void:
	visible = false

func grab_initial_focus() -> void:
	if _button != null:
		_button.grab_focus()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh_texts()

func _refresh_texts() -> void:
	if _title == null:
		return
	_title.text = tr(_title_key)
	_text.text = tr(_text_key)
