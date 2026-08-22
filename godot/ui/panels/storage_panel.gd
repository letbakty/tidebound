class_name StoragePanel
extends BottomSheet
## Склад: сетка стаков — иконка, число, капля «мокрое», пирог-таймер порчи.
## Только информация: перекладывать нельзя (docs/03 §5.3).

const COLUMNS: int = 6

var storage_id: int = -1

var _head: Label = null
var _warn: Label = null
var _grid: GridContainer = null

## Сигнатура отрисованной сетки стаков.
var _grid_sig: String = ""
## Объявлена ли сизигия: предупреждение про затопление склада имеет смысл
## только тогда (docs/00 §9).
var _spring_announced: bool = false

func _ready() -> void:
	super()
	_build_panel()
	Events.storage_changed.connect(_on_storage_changed)
	Events.crisis_announced.connect(_on_crisis)
	Events.crisis_started.connect(_on_crisis.bind(0))
	Events.run_started.connect(func(_seed_value: int) -> void:
		_spring_announced = false)

## Сизигию объявляют заранее (docs/00 §9) — до объявления пугать игрока нечем.
func _on_crisis(type: int, _cycle: int) -> void:
	if type == int(SimTypes.CrisisType.SPRING_TIDE):
		_spring_announced = true
		if visible:
			_refresh()

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
	_grid_sig = ""                  # другой склад — другая сетка
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
	# ближайшей сизигии (docs/00 §5). Показываем только когда сизигия УЖЕ
	# объявлена: постоянная строка про «может затопить» перестаёт читаться
	# уже к третьему циклу (аудит B5).
	var spring_risk: bool = float(int(s["mark"])) <= Balance.HIGH_LEVEL + Balance.SPRING_BONUS
	_warn.visible = spring_risk and _spring_announced
	_warn.text = tr("STORAGE_SPRING_WARN")
	# Сетка пересобирается только при реальном изменении: событие storage_changed
	# прилетает на каждый принесённый стак (аудит B3).
	var sig: String = JSON.stringify(stacks)
	if sig == _grid_sig:
		return
	_grid_sig = sig
	for c: Node in _grid.get_children():
		_grid.remove_child(c)
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
		wet.add_theme_color_override("font_color", UIPalette.water())
		# Label по умолчанию IGNORE — тултипа на нём не увидеть (аудит B2.9).
		wet.mouse_filter = Control.MOUSE_FILTER_PASS
		wet.tooltip_text = tr("STORAGE_WET")
		row.add_child(wet)
	if int(stack["spoil_cycles"]) > 0:
		var pie: SpoilPie = SpoilPie.new()
		pie.setup(int(stack["spoil_left"]), int(stack["spoil_cycles"]))
		row.add_child(pie)
	box.tooltip_text = StationPanel.item_key(item_id)
	return box
