class_name TooltipView
extends PanelContainer
## Тултип проекта. Подставляется компонентами через _make_custom_tooltip;
## на таче показывается по долгому нажатию (это делает владелец элемента).

## Обычный тултип узкий, но легенда шкалы — это десять строк, и на 180px она
## превращается в лапшу. Ширину задаёт вызывающий.
const WIDTH_PX: float = 180.0

var _label: Label = null

func _ready() -> void:
	_build()

func _build() -> void:
	if _label != null:
		return
	theme_type_variation = &"TooltipPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.name = "Text"
	_label.theme_type_variation = &"TooltipLabel"
	UILayout.wrap(_label, WIDTH_PX)
	add_child(_label)

## text — уже переведённая строка: тултип часто собирают из чисел.
func setup(text: String, width: float = WIDTH_PX) -> void:
	_build()
	UILayout.wrap(_label, width)
	_label.text = text
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED

static func make(text: String) -> TooltipView:
	var t: TooltipView = TooltipView.new()
	t.setup(text)
	return t
