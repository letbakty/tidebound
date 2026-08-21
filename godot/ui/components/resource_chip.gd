class_name ResourceChip
extends PanelContainer
## Чип ресурса: иконка + число + стрелка тренда (паттерн Against the Storm).
## Цвет — не единственный канал: направление читается формой стрелки (docs/01 §6).

const ICON_PX: int = 16
const ARROW_PX: int = 12

var item_id: String = ""

var _icon: IconStub = null
var _count: Label = null
var _arrow: Control = null
var _trend: int = 0

func _ready() -> void:
	_build()

func _build() -> void:
	if _icon != null:
		return
	theme_type_variation = &"PanelRaised"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Row"
	add_child(row)

	_icon = IconStub.new()
	_icon.name = "Icon"
	row.add_child(_icon)

	_count = Label.new()
	_count.name = "Count"
	_count.theme_type_variation = &"LabelNum"
	# Число — не ключ перевода: иначе в логах шум о ненайденных ключах.
	_count.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	row.add_child(_count)

	_arrow = Control.new()
	_arrow.name = "Trend"
	_arrow.custom_minimum_size = Vector2(float(ARROW_PX), float(ARROW_PX))
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.draw.connect(_draw_trend)
	row.add_child(_arrow)

	var hold: TouchTooltip = TouchTooltip.new()
	hold.name = "Hold"
	add_child(hold)
	hold.setup(self)

## Свой тултип вместо системного: тёмная подложка из темы (docs/03 §6).
func _make_custom_tooltip(for_text: String) -> Object:
	return TooltipView.make(for_text)

## trend: −1 / 0 / +1 — считает владелец (кэш событий), компонент только рисует.
func setup(id: String, count: int, trend: int) -> void:
	_build()
	item_id = id
	_trend = signi(trend)
	_icon.setup(_letter_for(id), _color_for(id), ICON_PX)
	_count.text = str(count)
	# Ноль показывается нулём, а не исчезает (docs/03 §8).
	tooltip_text = "ITEM_%s" % id.to_upper()
	_arrow.queue_redraw()

static func _letter_for(id: String) -> String:
	return id.substr(0, 1)

static func _color_for(id: String) -> Color:
	match id:
		"rations", "catch": return UITokens.SUCCESS
		"freshwater": return UITokens.WATER_COLD
		"driftwood", "fiber": return UITokens.WARM
		"part", "ingot", "rope", "gear": return UITokens.MUTED
		"relic": return UITokens.ACCENT
	return UITokens.MUTED

## Треугольник вверх/вниз и черта для «без изменений» — форма несёт смысл
## наравне с цветом.
func _draw_trend() -> void:
	var c: Color = UITokens.trend_color(_trend)
	var w: float = _arrow.size.x
	var h: float = _arrow.size.y
	if _trend == 0:
		_arrow.draw_line(Vector2(1.0, roundf(h * 0.5)),
			Vector2(w - 1.0, roundf(h * 0.5)), c, 2.0)
		return
	var pts: PackedVector2Array = PackedVector2Array()
	if _trend > 0:
		pts.append(Vector2(roundf(w * 0.5), 1.0))
		pts.append(Vector2(w - 1.0, h - 1.0))
		pts.append(Vector2(1.0, h - 1.0))
	else:
		pts.append(Vector2(roundf(w * 0.5), h - 1.0))
		pts.append(Vector2(w - 1.0, 1.0))
		pts.append(Vector2(1.0, 1.0))
	_arrow.draw_colored_polygon(pts, c)
