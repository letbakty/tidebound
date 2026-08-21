class_name CycleSummary
extends Control
## Итог цикла: добыто / произведено / ПОТЕРЯНО (docs/03 §4.3).
##
## Колонка потерь — самая важная: это обратная связь на жадность игрока, ради
## которой существует вся игра. Она не должна теряться среди двух других.

signal closed()

var _columns: HBoxContainer = null
var _events: VBoxContainer = null
var _forecast: Label = null
var _next: PixelButton = null
var _title: Label = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()

func _build() -> void:
	if _columns != null:
		return
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(UITokens.PAPER.r, UITokens.PAPER.g, UITokens.PAPER.b, 0.9)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", UITokens.SPACE_6)
	margin.add_theme_constant_override("margin_right", UITokens.SPACE_6)
	add_child(margin)
	var box: VBoxContainer = VBoxContainer.new()
	margin.add_child(box)

	_title = Label.new()
	_title.theme_type_variation = &"LabelTitle"
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	box.add_child(_title)

	_columns = HBoxContainer.new()
	_columns.name = "Columns"
	box.add_child(_columns)

	_events = VBoxContainer.new()
	_events.name = "Events"
	box.add_child(_events)

	_forecast = Label.new()
	_forecast.theme_type_variation = &"LabelSmall"
	UILayout.wrap(_forecast, 520.0)
	box.add_child(_forecast)

	_next = PixelButton.new()
	_next.setup("SUMMARY_NEXT", PixelButton.Variant.PRIMARY)
	_next.pressed.connect(func() -> void: closed.emit())
	box.add_child(_next)

func open_with(args: Dictionary) -> void:
	_build()
	var report: Dictionary = args.get("report", {}) as Dictionary
	_title.text = tr("SUMMARY_TITLE").format({"n": int(report.get("cycle", 1))})
	for c: Node in _columns.get_children():
		c.queue_free()
	_add_column("SUMMARY_GATHERED", report.get("gathered", {}) as Dictionary,
		UITokens.INK)
	_add_column("SUMMARY_PRODUCED", report.get("produced", {}) as Dictionary,
		UITokens.SUCCESS)
	_add_column("SUMMARY_LOST", _losses(report), UITokens.DANGER)
	_fill_events(report)
	_fill_forecast()

## Потери собираются из трёх источников отчёта: порча, смытое и украденное.
static func _losses(report: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: String in ["spoiled", "stolen"]:
		var part: Dictionary = report.get(key, {}) as Dictionary
		for k: Variant in part:
			out[str(k)] = int(out.get(str(k), 0)) + int(part[k])
	return out

func _add_column(title_key: String, items: Dictionary, tint: Color) -> void:
	var column: PanelContainer = PanelContainer.new()
	column.theme_type_variation = &"PanelRaised"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_columns.add_child(column)
	var box: VBoxContainer = VBoxContainer.new()
	column.add_child(box)
	var head: Label = Label.new()
	head.text = title_key
	head.add_theme_color_override("font_color", tint)
	box.add_child(head)
	if items.is_empty():
		var empty: Label = Label.new()
		empty.theme_type_variation = &"LabelSmall"
		empty.text = "SUMMARY_NOTHING"
		box.add_child(empty)
		return
	for k: Variant in items:
		var chip: ResourceChip = ResourceChip.new()
		box.add_child(chip)
		chip.setup(str(k), int(items[k]), 0)

## События цикла строками: кто погиб, что смыло, что сломалось.
func _fill_events(report: Dictionary) -> void:
	for c: Node in _events.get_children():
		c.queue_free()
	var lines: Array[String] = []
	var washed: int = int(report.get("washed", 0))
	if washed > 0:
		lines.append(tr("TOAST_WASHED").format({"n": washed}))
	var damage: int = int(report.get("damage", 0))
	if damage > 0:
		lines.append(tr("SUMMARY_DAMAGE").format({"n": damage}))
	var storm_deaths: int = int(report.get("storm_deaths", 0))
	if storm_deaths > 0:
		lines.append(tr("SUMMARY_STORM_DEATHS").format({"n": storm_deaths}))
	var newcomer: int = int(report.get("newcomer", -1))
	if newcomer >= 0:
		lines.append(tr("SUMMARY_NEWCOMER"))
	var card: String = str(report.get("card", ""))
	if not card.is_empty() and DB.has_card(card):
		lines.append(tr("SUMMARY_CARD").format({"name": tr(DB.card(card).display_key)}))
	for line: String in lines:
		var label: Label = Label.new()
		label.theme_type_variation = &"LabelSmall"
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		label.text = line
		_events.add_child(label)

## Прогноз следующего цикла — из объявленных кризисов (сам календарь игроку
## заранее не открыт).
func _fill_forecast() -> void:
	var clock: Dictionary = Game.query_clock()
	var announced: Array = clock.get("announced", []) as Array
	if announced.is_empty():
		_forecast.text = tr("SUMMARY_FORECAST_CALM")
		return
	var names: Array[String] = []
	for v: Variant in announced:
		names.append(tr(Hud.crisis_key(int(v))))
	_forecast.text = tr("SUMMARY_FORECAST").format({"what": ", ".join(names)})

func grab_initial_focus() -> void:
	if _next != null:
		_next.grab_focus()
