class_name StoragePanel
extends BottomSheet
## Склад: сетка стаков — иконка, число, капля «мокрое», пирог-таймер порчи.
## Только информация: перекладывать нельзя (docs/03 §5.3).

const COLUMNS: int = 6

var storage_id: int = -1

var _head: Label = null
var _warn: Label = null
var _grid: GridContainer = null

func _ready() -> void:
	super()
	_build_panel()
	Events.storage_changed.connect(_on_storage_changed)

func _build_panel() -> void:
	if _grid != null:
		return
	setup("PANEL_STORAGE", true)
	_head = Label.new()
	_head.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_content(_head)
	_warn = Label.new()
	_warn.theme_type_variation = &"LabelSmall"
	UILayout.wrap(_warn, 300.0)
	add_content(_warn)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_content(scroll)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)

func open_with(args: Dictionary) -> void:
	storage_id = int(args.get("id", -1))
	_refresh()

func _on_storage_changed(id: int) -> void:
	if visible and id == storage_id:
		_refresh()

func _refresh() -> void:
	var s: Dictionary = Game.query_storage(storage_id)
	if s.is_empty():
		return
	var stacks: Array = s["stacks"] as Array
	_head.text = "%s  %d/%d" % [tr("STORAGE_MARK").format({"mark": int(s["mark"])}),
		stacks.size(), int(s["capacity"])]
	# Предупреждение о сизигии: склад ниже +2 уйдёт под воду в высокую воду
	# ближайшей сизигии (docs/00 §5).
	var spring_risk: bool = float(int(s["mark"])) <= Balance.HIGH_LEVEL + Balance.SPRING_BONUS
	_warn.visible = spring_risk
	_warn.text = tr("STORAGE_SPRING_WARN")
	for c: Node in _grid.get_children():
		c.queue_free()
	for v: Variant in stacks:
		_grid.add_child(_make_slot(v as Dictionary))

func _make_slot(stack: Dictionary) -> Control:
	var box: PanelContainer = PanelContainer.new()
	box.theme_type_variation = &"PanelRaised"
	var row: HBoxContainer = HBoxContainer.new()
	box.add_child(row)
	var icon: IconStub = IconStub.new()
	row.add_child(icon)
	var item_id: String = str(stack["item_id"])
	icon.setup(item_id.substr(0, 1), ResourceChip.color_for(item_id), UITokens.SPACE_5)
	var count: Label = Label.new()
	count.theme_type_variation = &"LabelNum"
	count.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	count.text = str(int(stack["count"]))
	row.add_child(count)
	# Мокрое и порча — отдельными значками: цвет не единственный канал.
	if bool(stack["wet"]):
		var wet: Label = Label.new()
		wet.text = "~"
		wet.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		wet.add_theme_color_override("font_color", UITokens.WATER_COLD)
		wet.tooltip_text = "STORAGE_WET"
		row.add_child(wet)
	if int(stack["spoil_cycles"]) > 0:
		var pie: SpoilPie = SpoilPie.new()
		pie.setup(int(stack["spoil_left"]), int(stack["spoil_cycles"]))
		row.add_child(pie)
	box.tooltip_text = StationPanel.item_key(item_id)
	return box
