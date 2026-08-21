class_name PixelPanel
extends PanelContainer
## Панель с заголовком и крестиком. Закрывается крестиком, Esc (снаружи —
## PanelHost этапа 14) и свайпом вниз по шапке.
##
## Компонент не знает ни об игре, ни о шине событий: наружу — только `closed`.

signal closed()

const SWIPE_CLOSE_PX: float = 64.0

var content: VBoxContainer = null

var _title: Label = null
var _close: PixelButton = null
var _header: HBoxContainer = null
var _title_key: String = ""
var _swipe_start: float = INF

func _ready() -> void:
	_build()

func _build() -> void:
	if content != null:
		return
	theme_type_variation = &"PanelDark"
	var box: VBoxContainer = VBoxContainer.new()
	box.name = "Box"
	add_child(box)

	_header = HBoxContainer.new()
	_header.name = "Header"
	# Шапка ловит свайп-вниз, поэтому STOP: иначе жест уйдёт в мир панорамой.
	_header.mouse_filter = Control.MOUSE_FILTER_STOP
	_header.gui_input.connect(_on_header_input)
	box.add_child(_header)

	_title = Label.new()
	_title.name = "Title"
	_title.theme_type_variation = &"LabelTitle"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_header.add_child(_title)

	_close = PixelButton.new()
	_close.name = "Close"
	_close.setup("UI_CLOSE_X", PixelButton.Variant.GHOST)
	_close.tooltip_text = "UI_CLOSE"
	_close.pressed.connect(func() -> void: closed.emit())
	_header.add_child(_close)

	var sep: HSeparator = HSeparator.new()
	box.add_child(sep)

	content = VBoxContainer.new()
	content.name = "Content"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(content)

func setup(title_key: String, closable: bool = true) -> void:
	_build()
	_title_key = title_key
	_close.visible = closable
	_refresh_texts()

func add_content(node: Control) -> void:
	_build()
	content.add_child(node)

func clear_content() -> void:
	_build()
	for c: Node in content.get_children():
		c.queue_free()

func grab_initial_focus() -> void:
	if _close != null and _close.visible:
		_close.grab_focus()

## Строки, собранные в коде, сами не перепереводятся (research/22 §3.2).
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh_texts()

func _refresh_texts() -> void:
	if _title != null:
		_title.text = tr(_title_key) if not _title_key.is_empty() else ""

func _on_header_input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		_swipe_start = touch.position.y if touch.pressed else INF
		return
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if drag != null and _swipe_start != INF and drag.position.y - _swipe_start > SWIPE_CLOSE_PX:
		_swipe_start = INF
		closed.emit()
