class_name PausePanel
extends Control
## Окно паузы (docs/03 §4.1). «Покинуть забег» ведёт себя по-разному, и это
## написано прямо на кнопке: с 8-го цикла — уход досрочно (−25% очков),
## раньше — сдача (забег засчитан как погибший). Оба — через подтверждение.

signal resume_requested()
signal settings_requested()
signal menu_requested()
signal leave_requested(early: bool)

var _panel: PixelPanel = null
var _leave: PixelButton = null
var _seed: Label = null
var _resume: PixelButton = null
var _confirm: ConfirmDialog = null
var _early: bool = false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()

func _build() -> void:
	if _panel != null:
		return
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(UITokens.PAPER.r, UITokens.PAPER.g, UITokens.PAPER.b, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PixelPanel.new()
	_panel.custom_minimum_size = Vector2(400.0, 0.0)
	center.add_child(_panel)
	_panel.setup("PAUSE_TITLE", true)
	_panel.closed.connect(func() -> void: resume_requested.emit())

	_resume = PixelButton.new()
	_resume.setup("PAUSE_RESUME", PixelButton.Variant.PRIMARY)
	_resume.pressed.connect(func() -> void: resume_requested.emit())
	_panel.add_content(_resume)

	var settings: PixelButton = PixelButton.new()
	settings.setup("MENU_SETTINGS", PixelButton.Variant.NORMAL)
	settings.pressed.connect(func() -> void: settings_requested.emit())
	_panel.add_content(settings)

	_leave = PixelButton.new()
	_leave.setup("PAUSE_LEAVE_EARLY", PixelButton.Variant.DANGER)
	_leave.pressed.connect(_on_leave)
	_panel.add_content(_leave)

	var menu: PixelButton = PixelButton.new()
	menu.setup("PAUSE_TO_MENU", PixelButton.Variant.NORMAL)
	menu.tooltip_text = "PAUSE_TO_MENU_TIP"
	menu.pressed.connect(func() -> void: menu_requested.emit())
	_panel.add_content(menu)

	_seed = Label.new()
	_seed.theme_type_variation = &"LabelNum"
	_seed.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_seed.tooltip_text = "SUMMARY_SEED_TIP"
	_seed.mouse_filter = Control.MOUSE_FILTER_STOP
	_seed.gui_input.connect(_on_seed_input)
	_panel.add_content(_seed)

	_confirm = ConfirmDialog.new()
	_confirm.name = "Confirm"
	add_child(_confirm)
	_confirm.confirmed.connect(func() -> void: leave_requested.emit(_early))

func open_with(_args: Dictionary = {}) -> void:
	_build()
	var clock: Dictionary = Game.query_clock()
	var cycle: int = int(clock.get("cycle", 1))
	_early = cycle >= Balance.EARLY_LEAVE_MIN_CYCLE
	_leave.setup("PAUSE_LEAVE_EARLY" if _early else "PAUSE_SURRENDER",
		PixelButton.Variant.DANGER)
	var seed_value: int = 0 if Game.world == null else Game.world.rng.seed_value
	_seed.text = "%s   %s" % [
		tr("SUMMARY_SEED").format({"seed": seed_value}),
		tr("HUD_CYCLE_OF").format({"n": cycle, "total": Balance.CYCLES_PER_RUN})]

func grab_initial_focus() -> void:
	if _resume != null:
		_resume.grab_focus()

func _on_leave() -> void:
	_confirm.setup("PAUSE_TITLE",
		"PAUSE_LEAVE_EARLY_CONFIRM" if _early else "PAUSE_SURRENDER_CONFIRM",
		"PAUSE_LEAVE_EARLY" if _early else "PAUSE_SURRENDER", true, "")
	_confirm.open()

func _on_seed_input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null and not touch.pressed:
		DisplayServer.clipboard_set(_seed.text)
