class_name BuildingPanel
extends PixelPanel
## Общая панель постройки без своей логики: лестница, помост, койка, очаг,
## фонарь, шлюз, дождесборник (docs/03 §5.5). Что это, в каком состоянии,
## сколько топлива осталось у очага и фонаря.

signal repair_requested(building_id: int)
signal demolish_requested(building_id: int)

var building_id: int = -1

var _title_label: Label = null
var _state: Label = null
var _fuel: Label = null
var _progress: ProgressBar = null
var _repair: PixelButton = null
var _demolish: PixelButton = null

func _ready() -> void:
	super()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	custom_minimum_size = Vector2(360.0, 0.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_panel()
	Events.building_state_changed.connect(_on_changed)

func _build_panel() -> void:
	if _state != null:
		return
	setup("PANEL_BUILDING", true)
	_title_label = Label.new()
	_title_label.theme_type_variation = &"LabelTitle"
	add_content(_title_label)
	_state = Label.new()
	UILayout.wrap(_state, 300.0)
	add_content(_state)
	_fuel = Label.new()
	_fuel.theme_type_variation = &"LabelSmall"
	_fuel.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_content(_fuel)
	_progress = ProgressBar.new()
	_progress.max_value = 1.0
	_progress.step = 0.01
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0.0, float(UITokens.SPACE_5))
	add_content(_progress)

	var buttons: HBoxContainer = HBoxContainer.new()
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

func open_with(args: Dictionary) -> void:
	building_id = int(args.get("id", -1))
	_refresh()

func grab_initial_focus() -> void:
	if _demolish != null:
		_demolish.grab_focus()

func _on_changed(id: int) -> void:
	if visible and id == building_id:
		_refresh()

func _refresh() -> void:
	var b: Dictionary = Game.query_building(building_id)
	if b.is_empty():
		return
	var def: BuildingDef = DB.building(str(b["def_id"]))
	_title_label.text = tr(def.display_key) if def != null else ""
	_state.text = _state_text(b, def)
	_progress.value = float(b["progress"])
	_progress.visible = int(b["state"]) != int(SimTypes.BuildState.ACTIVE)
	# Остаток топлива — только там, где оно есть: очаг и фонарь (docs/00 §8).
	var burns: bool = def != null and (def.special == "hearth" or def.special == "lantern")
	_fuel.visible = burns
	if burns:
		_fuel.text = tr("BUILDING_FUEL").format({
			"n": int(b["fuel_left"]),
			"state": tr("BUILDING_LIT" if bool(b["lit"]) else "BUILDING_UNLIT"),
		})
	_repair.disabled = not bool(b["damaged"])

func _state_text(b: Dictionary, def: BuildingDef) -> String:
	if int(b["state"]) != int(SimTypes.BuildState.ACTIVE):
		return tr("BUILDING_UNDER_CONSTRUCTION")
	if bool(b["damaged"]):
		return tr("BUILDING_DAMAGED")
	if bool(b["flooded"]):
		var disabled: bool = def != null \
			and def.flood_rule == SimTypes.FloodRule.DISABLED
		return tr("BUILDING_FLOODED_OFF" if disabled else "BUILDING_FLOODED_OK")
	return tr("BUILDING_OK")
