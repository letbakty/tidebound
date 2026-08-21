extends Control
## Витрина компонентов: «страница стилей» проекта.
##   godot --path . res://ui/components/_gallery.tscn
##
## Правишь ui/theme/tokens.gd -> перегенерируешь тему (tools/gen_theme.gd) ->
## смотришь сюда. Витрина показывает каждый компонент во всех состояниях,
## обе локали и масштаб UI 75–150% — три вещи, которые ломаются чаще всего
## (research/19 §8).

const SCALE_MIN: float = 0.75
const SCALE_MAX: float = 1.5

var _backdrop: ColorRect = null
var _dark: bool = true
var _radial: RadialMenu = null
var _confirm: ConfirmDialog = null
var _toast_box: VBoxContainer = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = load("res://ui/theme/main_theme.tres") as Theme
	_build()

func _build() -> void:
	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.color = UITokens.PAPER
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)

	var root: VBoxContainer = VBoxContainer.new()
	root.name = "Root"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	_build_controls(root)
	_build_buttons(root)
	_build_chips(root)
	_build_policies(root)
	_build_cards(root)
	_build_panels(root)
	_build_toasts(root)

	_radial = RadialMenu.new()
	_radial.name = "Radial"
	add_child(_radial)
	_confirm = ConfirmDialog.new()
	_confirm.name = "Confirm"
	add_child(_confirm)

func _head(root: VBoxContainer, key: String) -> void:
	var l: Label = Label.new()
	l.theme_type_variation = &"LabelTitle"
	l.text = key
	root.add_child(l)

func _row(root: VBoxContainer) -> HBoxContainer:
	var r: HBoxContainer = HBoxContainer.new()
	root.add_child(r)
	return r

# --- Переключатели витрины ------------------------------------------------

func _build_controls(root: VBoxContainer) -> void:
	_head(root, "GALLERY_TITLE")
	var row: HBoxContainer = _row(root)

	var loc: PixelButton = PixelButton.new()
	loc.setup("GALLERY_LOCALE", PixelButton.Variant.GHOST)
	loc.pressed.connect(func() -> void:
		TranslationServer.set_locale("en" if TranslationServer.get_locale().begins_with("ru") else "ru"))
	row.add_child(loc)

	var bg: PixelButton = PixelButton.new()
	bg.setup("GALLERY_BACKDROP", PixelButton.Variant.GHOST)
	bg.pressed.connect(func() -> void:
		_dark = not _dark
		_backdrop.color = UITokens.PAPER if _dark else UITokens.INK)
	row.add_child(bg)

	var scale_label: Label = Label.new()
	scale_label.theme_type_variation = &"LabelSmall"
	scale_label.text = "GALLERY_UI_SCALE"
	row.add_child(scale_label)

	var slider: HSlider = HSlider.new()
	slider.min_value = SCALE_MIN
	slider.max_value = SCALE_MAX
	slider.step = 0.25
	slider.value = 1.0
	slider.custom_minimum_size = Vector2(200.0, float(UITokens.TOUCH_MIN))
	slider.value_changed.connect(func(v: float) -> void:
		get_tree().root.content_scale_factor = v)
	row.add_child(slider)

# --- Атомы ----------------------------------------------------------------

func _build_buttons(root: VBoxContainer) -> void:
	_head(root, "GALLERY_BUTTONS")
	for v: int in [PixelButton.Variant.NORMAL, PixelButton.Variant.PRIMARY,
			PixelButton.Variant.DANGER, PixelButton.Variant.GHOST]:
		var row: HBoxContainer = _row(root)
		for state: String in ["normal", "disabled", "focus"]:
			var b: PixelButton = PixelButton.new()
			b.setup("GALLERY_BTN_%s" % state.to_upper(), v as PixelButton.Variant)
			b.disabled = state == "disabled"
			row.add_child(b)
			if state == "focus":
				b.call_deferred("grab_focus")

func _build_chips(root: VBoxContainer) -> void:
	_head(root, "GALLERY_CHIPS")
	var row: HBoxContainer = _row(root)
	var data: Array[Array] = [["rations", 12, 1], ["freshwater", 8, -1],
		["driftwood", 0, 0], ["part", 148, 1]]
	for d: Array in data:
		var chip: ResourceChip = ResourceChip.new()
		row.add_child(chip)
		chip.setup(str(d[0]), int(d[1]), int(d[2]))
	var agents: HBoxContainer = _row(root)
	var needs: Array[float] = [92.0, 61.0, 44.0, 21.0, 0.0]
	for i: int in needs.size():
		var chip: AgentChip = AgentChip.new()
		agents.add_child(chip)
		chip.setup(i, "АБВГД".substr(i, 1), needs[i], needs[i] <= 0.0)

func _build_policies(root: VBoxContainer) -> void:
	_head(root, "GALLERY_POLICIES")
	var row: HBoxContainer = _row(root)
	for i: int in 2:
		var ps: PolicySlider = PolicySlider.new()
		ps.custom_minimum_size = Vector2(280.0, 0.0)
		row.add_child(ps)
		ps.setup(i, i + 1, "POLICY_GREED" if i == 0 else "POLICY_CAUTION",
			func(_p: int, v: int) -> String: return "%s %d" % [tr("GALLERY_VALUE"), v])

func _build_cards(root: VBoxContainer) -> void:
	_head(root, "GALLERY_CARDS")
	var row: HBoxContainer = _row(root)
	var card_a: CardView = CardView.new()
	row.add_child(card_a)
	card_a.setup("deep_dive", "CARD_DEEP_DIVE", "CARD_DEEP_DIVE_D", false)
	var card_b: CardView = CardView.new()
	row.add_child(card_b)
	card_b.setup("great_ebb", "CARD_GREAT_EBB", "CARD_GREAT_EBB_D", true)
	card_b.set_selected(true)

func _build_panels(root: VBoxContainer) -> void:
	_head(root, "GALLERY_PANELS")
	var row: HBoxContainer = _row(root)

	var panel: PixelPanel = PixelPanel.new()
	panel.custom_minimum_size = Vector2(320.0, 160.0)
	row.add_child(panel)
	panel.setup("GALLERY_PANEL_TITLE", true)
	var inner: Label = Label.new()
	inner.text = "GALLERY_PANEL_BODY"
	UILayout.wrap(inner, 280.0)
	panel.add_content(inner)

	var tip: TooltipView = TooltipView.new()
	row.add_child(tip)
	tip.setup(tr("GALLERY_TOOLTIP"))

	var banner: BannerView = BannerView.new()
	root.add_child(banner)
	banner.show_banner("CRISIS_STORM", "CRISIS_STORM_D", BannerView.Tone.DANGER)

	var open_row: HBoxContainer = _row(root)
	var radial_btn: PixelButton = PixelButton.new()
	radial_btn.setup("GALLERY_OPEN_RADIAL", PixelButton.Variant.NORMAL)
	radial_btn.pressed.connect(_open_radial)
	open_row.add_child(radial_btn)
	var confirm_btn: PixelButton = PixelButton.new()
	confirm_btn.setup("GALLERY_OPEN_CONFIRM", PixelButton.Variant.DANGER)
	confirm_btn.pressed.connect(_open_confirm)
	open_row.add_child(confirm_btn)

func _build_toasts(root: VBoxContainer) -> void:
	_head(root, "GALLERY_TOASTS")
	_toast_box = VBoxContainer.new()
	root.add_child(_toast_box)
	var tones: Array[Toast.Tone] = [Toast.Tone.INFO, Toast.Tone.WARN, Toast.Tone.DANGER]
	for i: int in tones.size():
		var t: Toast = Toast.new()
		_toast_box.add_child(t)
		t.setup("%s %d" % [tr("GALLERY_TOAST"), i], tones[i], Vector2i.ZERO, 0.0)
		if i == 2:
			t.set_count(3)

func _open_radial() -> void:
	var slots: Array[Dictionary] = []
	for i: int in 6:
		slots.append({"label": "GALLERY_SLOT", "letter": str(i + 1),
			"color": UITokens.ACCENT, "enabled": i != 4})
	_radial.open_at(size * 0.5, slots, false)

func _open_confirm() -> void:
	_confirm.setup("UI_CONFIRM_TITLE", "GALLERY_CONFIRM_BODY", "UI_DELETE", true, "")
	_confirm.open()
