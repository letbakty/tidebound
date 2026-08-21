class_name StationPanel
extends PixelPanel
## Станция: что делает, что в буфере, чего не хватает и — главное — ПОЧЕМУ
## стоит (docs/03 §5.4). Без явной причины простоя игрок не понимает, почему
## цепочка встала; это главный источник фрустрации в жанре.

signal repair_requested(building_id: int)
signal demolish_requested(building_id: int)

## Коды простоя из sim → ключи локализации. Sim об интерфейсе не знает.
const REASON_KEYS: Dictionary[String, String] = {
	"under_construction": "STATION_BUILDING",
	"damaged": "STATION_DAMAGED",
	"flooded": "STATION_FLOODED",
	"no_recipe": "STATION_NO_RECIPE",
	"no_materials": "STATION_NO_MATERIALS",
	"no_fuel": "STATION_NO_FUEL",
	"no_worker": "STATION_NO_WORKER",
	"no_space": "STATION_NO_SPACE",
}

var building_id: int = -1

var _title_label: Label = null
var _recipe: HBoxContainer = null
var _buffer: VBoxContainer = null
var _progress: ProgressBar = null
var _reason: Label = null
var _repair: PixelButton = null
var _demolish: PixelButton = null
var _timer: Timer = null

func _ready() -> void:
	super()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	custom_minimum_size = Vector2(400.0, 0.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_panel()

func _build_panel() -> void:
	if _reason != null:
		return
	setup("PANEL_STATION", true)

	_title_label = Label.new()
	_title_label.theme_type_variation = &"LabelTitle"
	add_content(_title_label)

	_recipe = HBoxContainer.new()
	_recipe.name = "Recipe"
	add_content(_recipe)

	_buffer = VBoxContainer.new()
	_buffer.name = "Buffer"
	add_content(_buffer)

	_progress = ProgressBar.new()
	_progress.name = "Progress"
	_progress.max_value = 1.0
	_progress.step = 0.01
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0.0, float(UITokens.SPACE_5))
	add_content(_progress)

	_reason = Label.new()
	_reason.name = "Reason"
	UILayout.wrap(_reason, 340.0)
	add_content(_reason)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.name = "Buttons"
	add_content(buttons)
	_repair = PixelButton.new()
	_repair.setup("ACT_REPAIR", PixelButton.Variant.NORMAL)
	_repair.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_repair.pressed.connect(func() -> void: repair_requested.emit(building_id))
	buttons.add_child(_repair)
	_demolish = PixelButton.new()
	_demolish.setup("ACT_DEMOLISH", PixelButton.Variant.DANGER)
	_demolish.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_demolish.pressed.connect(func() -> void: demolish_requested.emit(building_id))
	buttons.add_child(_demolish)

	_timer = Timer.new()
	_timer.name = "Refresh"
	_timer.wait_time = 0.5
	_timer.timeout.connect(_refresh)
	add_child(_timer)

func open_with(args: Dictionary) -> void:
	building_id = int(args.get("id", -1))
	_refresh()
	_timer.start()

func on_closed() -> void:
	_timer.stop()

func grab_initial_focus() -> void:
	if _repair != null:
		_repair.grab_focus()

func _refresh() -> void:
	var s: Dictionary = Game.query_station(building_id)
	if s.is_empty():
		return
	var def: BuildingDef = DB.building(str(s["def_id"]))
	_title_label.text = tr(def.display_key) if def != null else ""
	_fill_recipe(s)
	_fill_buffer(s)
	_progress.value = float(s["progress"])
	_fill_reason(str(s["reason"]))
	_repair.disabled = not bool(s["damaged"])

## Рецепт наглядно: входы → выход.
func _fill_recipe(s: Dictionary) -> void:
	for c: Node in _recipe.get_children():
		c.queue_free()
	var inputs: Dictionary = s["inputs"] as Dictionary
	var outputs: Dictionary = s["outputs"] as Dictionary
	if inputs.is_empty() and outputs.is_empty():
		return
	for k: Variant in inputs:
		_add_item_chip(_recipe, str(k), int(inputs[k]))
	var arrow: Label = Label.new()
	arrow.text = "->"
	arrow.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_recipe.add_child(arrow)
	for k2: Variant in outputs:
		_add_item_chip(_recipe, str(k2), int(outputs[k2]))

func _add_item_chip(parent: Control, item_id: String, count: int) -> void:
	var chip: ResourceChip = ResourceChip.new()
	parent.add_child(chip)
	chip.setup(item_id, count, 0)

## Буфер: что принесено и чего не хватает — по строке на вход.
func _fill_buffer(s: Dictionary) -> void:
	for c: Node in _buffer.get_children():
		c.queue_free()
	var inputs: Dictionary = s["inputs"] as Dictionary
	var have: Dictionary = s["have"] as Dictionary
	for k: Variant in inputs:
		var item_id: String = str(k)
		var need: int = int(inputs[k])
		var got: int = int(have.get(item_id, 0))
		var row: Label = Label.new()
		row.theme_type_variation = &"LabelSmall"
		row.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		row.text = "%s  %d/%d" % [tr(item_key(item_id)), got, need]
		row.add_theme_color_override("font_color",
			UITokens.SUCCESS if got >= need else UITokens.DANGER)
		_buffer.add_child(row)

## Ключ названия предмета: нужен и складу.
static func item_key(item_id: String) -> String:
	var def: ItemDef = DB.item(item_id)
	return "ITEM_%s" % item_id.to_upper() if def == null else def.display_key

func _fill_reason(reason: String) -> void:
	if reason.is_empty():
		_reason.text = tr("STATION_WORKING")
		_reason.add_theme_color_override("font_color", UITokens.SUCCESS)
		return
	_reason.text = tr(REASON_KEYS.get(reason, "STATION_NO_RECIPE"))
	_reason.add_theme_color_override("font_color", UITokens.DANGER)
