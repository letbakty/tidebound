class_name ScreenBase
extends Control
## Общий каркас экрана: фон, заголовок, колонка содержимого, кнопка «назад».
## Экран скрывает мир и занимает весь экран (docs/03 §1).

signal back_requested()

var content: VBoxContainer = null

var _title: Label = null
var _title_key: String = ""
var _back: PixelButton = null
var _first_focus: Control = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	build_base()

## Каркас экрана. Контейнеры — IGNORE, перехватывает только КОРЕНЬ экрана:
## иначе прозрачный полноэкранный Margin/Box/Content на самом верхнем слое (40)
## съедает клики у HUD, панелей и банеров под собой — весь интерфейс забега
## переставал нажиматься. Тот же приём уже применён в ui/hud/hud.gd.
## Дети контейнеров при IGNORE ввод получают как обычно.
func build_base() -> void:
	if content != null:
		return
	var bg: ColorRect = ColorRect.new()
	bg.name = "Bg"
	bg.color = UITokens.PAPER
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin: MarginContainer = MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", UITokens.SPACE_6)
	margin.add_theme_constant_override("margin_right", UITokens.SPACE_6)
	margin.add_theme_constant_override("margin_top", UITokens.SPACE_5)
	margin.add_theme_constant_override("margin_bottom", UITokens.SPACE_5)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var box: VBoxContainer = VBoxContainer.new()
	box.name = "Box"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	var header: HBoxContainer = HBoxContainer.new()
	header.name = "Header"
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(header)
	_title = Label.new()
	_title.name = "Title"
	_title.theme_type_variation = &"LabelTitle"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_back = PixelButton.new()
	_back.name = "Back"
	_back.setup("UI_BACK", PixelButton.Variant.GHOST)
	_back.pressed.connect(func() -> void: back_requested.emit())
	header.add_child(_back)

	content = VBoxContainer.new()
	content.name = "Content"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(content)

func set_title(key: String) -> void:
	build_base()
	_title_key = key
	_refresh_texts()

func show_back(on: bool) -> void:
	build_base()
	if _back != null:
		_back.visible = on

## Кто получает фокус при открытии — иначе геймпад «теряет» курсор
## (research/20 §6).
func set_first_focus(control: Control) -> void:
	_first_focus = control

func grab_initial_focus() -> void:
	if _first_focus != null and is_instance_valid(_first_focus):
		_first_focus.grab_focus()
	elif _back != null and _back.visible:
		_back.grab_focus()

## Зовётся роутером при открытии экрана.
func on_enter(_args: Dictionary = {}) -> void:
	pass

func on_exit() -> void:
	pass

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh_texts()

func _refresh_texts() -> void:
	if _title != null:
		_title.text = tr(_title_key)
