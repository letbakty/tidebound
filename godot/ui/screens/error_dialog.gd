class_name ErrorDialog
extends Control
## Что случилось, что игра сделала, что можно сделать (docs/03 §4.5).
## Кнопка «Скопировать детали» кладёт техинформацию в буфер для баг-репорта.

signal closed()

var _panel: PixelPanel = null
var _what: Label = null
var _did: Label = null
var _details: String = ""
var _menu: PixelButton = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()

func _build() -> void:
	if _panel != null:
		return
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(UITokens.PAPER.r, UITokens.PAPER.g, UITokens.PAPER.b, 0.85)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PixelPanel.new()
	_panel.custom_minimum_size = Vector2(520.0, 0.0)
	center.add_child(_panel)
	_panel.setup("ERROR_TITLE", false)
	_what = Label.new()
	UILayout.wrap(_what, 460.0)
	_panel.add_content(_what)
	_did = Label.new()
	_did.theme_type_variation = &"LabelSmall"
	UILayout.wrap(_did, 460.0)
	_panel.add_content(_did)
	var row: HBoxContainer = HBoxContainer.new()
	_panel.add_content(row)
	var copy: PixelButton = PixelButton.new()
	copy.setup("ERROR_COPY", PixelButton.Variant.GHOST)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.pressed.connect(func() -> void: DisplayServer.clipboard_set(_details))
	row.add_child(copy)
	_menu = PixelButton.new()
	_menu.setup("ERROR_TO_MENU", PixelButton.Variant.PRIMARY)
	_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	row.add_child(_menu)

## what/did — ключи локализации, details — техническая строка для буфера.
func open_with(args: Dictionary) -> void:
	_build()
	_what.text = tr(str(args.get("what", "ERROR_SAVE_BROKEN")))
	_did.text = tr(str(args.get("did", "ERROR_SAVE_BROKEN_DID")))
	_details = str(args.get("details", ""))
	visible = true

func grab_initial_focus() -> void:
	if _menu != null:
		_menu.grab_focus()
