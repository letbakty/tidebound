class_name ButtonHints
extends PanelContainer
## Подсказки кнопок под активное устройство ввода (промпт 16 п.2).
## Переключаются по последнему вводу и не мигают от дрейфа стика — фильтр
## живёт в InputService (research/20 §5).

## Действие → как называется на клавиатуре и на геймпаде.
const HINTS: Array[Array] = [
	["ACT_RECALL", "HUD_KEY_SPACE", "HUD_PAD_B"],
	["ACT_BUILD", "HUD_KEY_B", "HUD_PAD_Y"],
	["ACT_POLICIES", "HUD_KEY_P", "HUD_PAD_LB"],
	["ACT_BEACON", "HUD_KEY_M", "HUD_PAD_X"],
	["ACT_PAUSE", "HUD_KEY_ESC", "HUD_PAD_START"],
]

var _rows: HBoxContainer = null
var _device: int = 0

func _ready() -> void:
	theme_type_variation = &"PanelHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows = HBoxContainer.new()
	_rows.name = "Rows"
	add_child(_rows)
	_refresh()

## device — InputService.Device.
func set_device(device: int) -> void:
	if device == _device:
		return
	_device = device
	_refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh()

func _refresh() -> void:
	if _rows == null:
		return
	for c: Node in _rows.get_children():
		c.queue_free()
	# На таче подсказок клавиш нет вовсе: там всё делается пальцем.
	visible = _device != int(InputService.Device.TOUCH)
	if not visible:
		return
	for row: Array in HINTS:
		var label: Label = Label.new()
		label.theme_type_variation = &"LabelSmall"
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var key_index: int = 2 if _device == int(InputService.Device.PAD) else 1
		label.text = "%s %s" % [tr(str(row[key_index])), tr(str(row[0]))]
		_rows.add_child(label)
