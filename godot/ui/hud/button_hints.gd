class_name ButtonHints
extends PanelContainer
## Подсказки кнопок под активное устройство ввода (промпт 16 п.2).
## Переключаются по последнему вводу и не мигают от дрейфа стика — фильтр
## живёт в InputService (research/20 §5).

## Какие действия показываем и как они называются словами. САМА клавиша здесь
## не хранится: подпись берётся из InputMap через общий хелпер
## (ui/input_bindings.gd), тот же, которым пользуется вкладка настроек.
##
## ⚠️ Раньше подписи были константами (HUD_KEY_SPACE, HUD_PAD_B), и после
## ремапа полоса внизу экрана продолжала показывать старые клавиши. Это ещё и
## прямое требование Steam Deck Verified: экранные глифы обязаны соответствовать
## активному устройству и текущей раскладке (research/32 §4.1).
const HINTS: Array[Array] = [
	["recall", "ACT_RECALL"],
	["build_radial", "ACT_BUILD"],
	["policies", "ACT_POLICIES"],
	["beacon", "ACT_BEACON"],
	["pause_menu", "ACT_PAUSE"],
]

var _rows: HBoxContainer = null
var _device: int = 0

func _ready() -> void:
	theme_type_variation = &"PanelHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows = HBoxContainer.new()
	_rows.name = "Rows"
	add_child(_rows)
	# Ремап обязан быть виден сразу же, а не после перезапуска.
	Settings.bindings_changed.connect(_refresh)
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
	var pad: bool = _device == int(InputService.Device.PAD)
	for row: Array in HINTS:
		var label: Label = Label.new()
		label.theme_type_variation = &"LabelSmall"
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		# Подпись клавиши не переводится — это глиф на железе; переводится
		# только название действия.
		label.text = "%s %s" % [InputBindings.action_label(str(row[0]), pad),
			tr(str(row[1]))]
		_rows.add_child(label)
