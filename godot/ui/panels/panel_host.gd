class_name PanelHost
extends Control
## Реестр панелей поверх живой игры. Одновременно открыта максимум одна:
## открытие новой закрывает старую (docs/03 §1).
##
## Панели НЕмодальные: мир виден и тикает, ввод в мир разрешён. Поэтому у
## хоста mouse_filter = IGNORE — полноэкранный STOP съел бы все тапы по миру.

var _panels: Dictionary[String, Control] = {}
var _current: String = ""
## Кому вернуть фокус при закрытии: без этого геймпад «теряет» курсор
## и приёмка «проходима только геймпадом» падает (research/20 §6).
var _focus_before: Control = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## panel обязан иметь open_with(args: Dictionary) и сигнал closed.
##
## РЕШЕНИЕ: не setup(), как в research/21 §6 — это имя у PixelPanel уже занято
## заголовком, и одинаковое имя с разной сигнатурой ломается молча.
func register(panel_name: String, panel: Control) -> void:
	_panels[panel_name] = panel
	panel.visible = false
	add_child(panel)
	if panel.has_signal("closed"):
		panel.connect("closed", func() -> void: close())

func open(panel_name: String, args: Dictionary = {}) -> void:
	if _current == panel_name:
		close()                      # повторный вызов той же панели — тумблер
		return
	close()
	var p: Control = _panels.get(panel_name, null)
	if p == null:
		push_warning("PanelHost: нет панели '%s'" % panel_name)
		return
	_focus_before = get_viewport().gui_get_focus_owner()
	if p.has_method("open_with"):
		p.call("open_with", args)
	p.visible = true
	if p.has_method("grab_initial_focus"):
		p.call("grab_initial_focus")
	_current = panel_name
	Events.ui_panel_opened.emit(panel_name)

func close() -> void:
	if _current.is_empty():
		return
	var p: Control = _panels[_current]
	p.visible = false
	if p.has_method("on_closed"):
		p.call("on_closed")
	var was: String = _current
	_current = ""
	Events.ui_panel_closed.emit(was)
	if _focus_before != null and is_instance_valid(_focus_before):
		_focus_before.grab_focus()
	_focus_before = null

func current() -> String:
	return _current

func is_open(panel_name: String = "") -> bool:
	return not _current.is_empty() if panel_name.is_empty() else _current == panel_name

## Esc в _unhandled_input, а не в _input: LineEdit внутри панели должен
## сначала снять свой фокус (research/21 §6).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_menu") and not _current.is_empty():
		close()
		get_viewport().set_input_as_handled()
