class_name RunSummary
extends Control
## Итог забега (docs/03 §3.8). Три блока: исход, очки, люди.
##
## ⚠️ При проигрыше экран ОБЯЗАН показать, что игрок получил: сколько очков
## ушло в Журнал и что теперь по карману. Экран, показывающий только потери,
## гонит игрока из игры — на смягчении проигрыша держится весь жанр.

signal journal_requested()

const COUNT_SEC: float = 0.5

var _outcome: Label = null
var _outcome_note: Label = null
var _rows: VBoxContainer = null
var _total: Label = null
var _gain: Label = null
var _people: VBoxContainer = null
var _seed: Label = null
var _to_journal: PixelButton = null
var _tween: Tween = null
var _final: Dictionary[Label, int] = {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()

func _build() -> void:
	if _rows != null:
		return
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(UITokens.PAPER.r, UITokens.PAPER.g, UITokens.PAPER.b, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", UITokens.SPACE_6)
	margin.add_theme_constant_override("margin_right", UITokens.SPACE_6)
	add_child(margin)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	_outcome = Label.new()
	_outcome.theme_type_variation = &"LabelTitle"
	box.add_child(_outcome)
	_outcome_note = Label.new()
	UILayout.wrap(_outcome_note, 560.0)
	box.add_child(_outcome_note)

	_rows = VBoxContainer.new()
	_rows.name = "Score"
	box.add_child(_rows)
	_total = Label.new()
	_total.theme_type_variation = &"LabelTitle"
	_total.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	box.add_child(_total)
	_gain = Label.new()
	UILayout.wrap(_gain, 560.0)
	box.add_child(_gain)

	_people = VBoxContainer.new()
	_people.name = "People"
	box.add_child(_people)

	_seed = Label.new()
	_seed.theme_type_variation = &"LabelNum"
	_seed.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	# tr() вручную: у ноды выключен автоперевод, и тултип показал бы сам ключ.
	_seed.tooltip_text = tr("SUMMARY_SEED_TIP")
	_seed.mouse_filter = Control.MOUSE_FILTER_STOP
	_seed.gui_input.connect(_on_seed_input)
	box.add_child(_seed)

	_to_journal = PixelButton.new()
	_to_journal.setup("RUN_TO_JOURNAL", PixelButton.Variant.PRIMARY)
	# Первое нажатие досказывает числа, второе уводит в Журнал: так пропуск
	# анимации доступен и с геймпада, и с клавиатуры — тап по фону работает
	# только пальцем (аудит B4).
	_to_journal.pressed.connect(func() -> void:
		if _counting():
			_finish_numbers()
			return
		journal_requested.emit())
	box.add_child(_to_journal)

func open_with(args: Dictionary) -> void:
	_build()
	var report: Dictionary = args.get("report", {}) as Dictionary
	var end_kind: int = int(report.get("end", 0))
	_outcome.text = tr(_outcome_key(end_kind))
	_outcome.add_theme_color_override("font_color", _outcome_color(end_kind))
	_outcome_note.text = tr("RUN_CYCLES").format({
		"n": int(report.get("cycles", 0)), "total": Balance.CYCLES_PER_RUN})
	_fill_score(report)
	_fill_people(report)
	_seed.text = tr("SUMMARY_SEED").format({"seed": int(report.get("seed", 0))})

static func _outcome_key(end_kind: int) -> String:
	match end_kind:
		int(SimTypes.RunEnd.SHIP): return "RUN_END_SHIP"
		int(SimTypes.RunEnd.EARLY): return "RUN_END_EARLY"
	return "RUN_END_WIPE"

static func _outcome_color(end_kind: int) -> Color:
	match end_kind:
		int(SimTypes.RunEnd.SHIP): return UIPalette.success()
		int(SimTypes.RunEnd.EARLY): return UIPalette.warm()
	return UIPalette.danger()

## Очки построчно с «подъездом» чисел. Одна Tween на весь экран с chain():
## по твину на строку — и они пойдут вразнобой (research/22 §7).
func _fill_score(report: Dictionary) -> void:
	for c: Node in _rows.get_children():
		c.queue_free()
	_final.clear()
	_kill_tween()
	var breakdown: Dictionary = report.get("breakdown", {}) as Dictionary
	var keys: Array[String] = []
	keys.assign(breakdown.keys())
	keys.sort()
	_tween = create_tween()
	for key: String in keys:
		var row: HBoxContainer = HBoxContainer.new()
		_rows.add_child(row)
		var name_label: Label = Label.new()
		name_label.text = "SCORE_%s" % key.to_upper()
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var value: Label = Label.new()
		value.theme_type_variation = &"LabelNum"
		value.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		value.text = "0"
		row.add_child(value)
		var target: int = int(breakdown[key])
		_final[value] = target
		_tween.tween_method(func(v: float) -> void:
			value.text = "%d" % int(round(v)), 0.0, float(target), COUNT_SEC)
	var total: int = int(report.get("score", 0))
	_final[_total] = total
	_tween.tween_method(func(v: float) -> void:
		_total.text = tr("RUN_TOTAL").format({"n": int(round(v))}),
		0.0, float(total), COUNT_SEC)
	# Что игрок ПОЛУЧИЛ — отдельной строкой и всегда, даже при вайпе.
	_gain.text = tr("RUN_GAIN").format({
		"n": total, "points": Meta.points_total, "next": _affordable_count()})
	if Settings.reduce_motion:
		_finish_numbers()               # «меньше движения» (docs/03 §3.6)

## Сколько разблокировок теперь по карману: конкретная причина открыть Журнал.
static func _affordable_count() -> int:
	var n: int = 0
	for id: String in DB.unlock_ids():
		if Meta.has_unlock(id):
			continue
		if Meta.points_total >= DB.unlock(id).cost:
			n += 1
	return n

func _fill_people(report: Dictionary) -> void:
	for c: Node in _people.get_children():
		c.queue_free()
	var survivors: Array = Game.query_survivors()
	var head: Label = Label.new()
	head.text = "RUN_SURVIVORS"
	_people.add_child(head)
	if survivors.is_empty():
		_people.add_child(_small(tr("RUN_NOBODY")))
	for v: Variant in survivors:
		var a: Dictionary = v as Dictionary
		_people.add_child(_small("%s — %s" % [str(a["name"]), tr(str(a["bio"]))]))
	var dead_head: Label = Label.new()
	dead_head.text = "RUN_FALLEN"
	_people.add_child(dead_head)
	var deaths: Array = report.get("deaths", []) as Array
	if deaths.is_empty():
		_people.add_child(_small(tr("RUN_NO_DEATHS")))
	for d: Variant in deaths:
		var death: Dictionary = d as Dictionary
		_people.add_child(_small(tr("RUN_EPITAPH").format({
			"name": str(death.get("name", "?")),
			"cause": tr("CAUSE_%s" % str(death.get("cause", "")).to_upper()),
			"bio": tr(str(death.get("bio", ""))),
		})))

func _small(text: String) -> Label:
	var label: Label = Label.new()
	label.theme_type_variation = &"LabelSmall"
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	UILayout.wrap(label, 560.0)
	label.text = text
	return label

## Пропуск анимации тапом: на двадцатом забеге ждать подъезда чисел невыносимо.
func _gui_input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null and touch.pressed:
		_finish_numbers()
		return
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and click.pressed:
		_finish_numbers()

## Идёт ли ещё «подъезд» чисел.
func _counting() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()

func _finish_numbers() -> void:
	_kill_tween()
	for label: Label in _final:
		if not is_instance_valid(label):
			continue
		if label == _total:
			label.text = tr("RUN_TOTAL").format({"n": _final[label]})
		else:
			label.text = "%d" % _final[label]

func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null

func on_closed() -> void:
	_kill_tween()

func grab_initial_focus() -> void:
	if _to_journal != null:
		_to_journal.grab_focus()

func _on_seed_input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null and not touch.pressed:
		DisplayServer.clipboard_set(_seed.text)
