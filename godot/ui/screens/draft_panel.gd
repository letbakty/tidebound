class_name DraftPanel
extends Control
## План вылазки: три карты (четыре с разблокировкой) во весь экран.
## Выбор двухшаговый — тап выделяет, кнопка подтверждает: на телефоне это
## защита от промаха (docs/03 §4.2).

signal card_confirmed(card_id: String)

var _cards: HBoxContainer = null
var _confirm: PixelButton = null
var _note: Label = null
var _selected: String = ""
var _views: Array[CardView] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()

func _build() -> void:
	if _cards != null:
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
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(box)

	var title: Label = Label.new()
	title.theme_type_variation = &"LabelTitle"
	title.text = "DRAFT_TITLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_cards = HBoxContainer.new()
	_cards.name = "Cards"
	_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_cards)

	_confirm = PixelButton.new()
	_confirm.setup("DRAFT_PICK", PixelButton.Variant.PRIMARY)
	_confirm.disabled = true
	_confirm.pressed.connect(_on_confirm)
	box.add_child(_confirm)

	_note = Label.new()
	_note.theme_type_variation = &"LabelSmall"
	_note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_note)

func open_with(args: Dictionary) -> void:
	_build()
	_selected = ""
	_confirm.disabled = true
	_views.clear()
	for c: Node in _cards.get_children():
		c.queue_free()
	var ids: Array = args.get("cards", []) as Array
	for v: Variant in ids:
		var id: String = str(v)
		var def: CardDef = DB.card(id)
		if def == null:
			continue
		var view: CardView = CardView.new()
		_cards.add_child(view)
		view.setup(id, def.display_key, def.desc_key, def.rarity == "rare")
		view.picked.connect(_on_card_picked)
		_views.append(view)
	var clock: Dictionary = Game.query_clock()
	_note.text = tr("DRAFT_NOTE").format({
		"n": int(clock.get("cycle", 1)), "total": Balance.CYCLES_PER_RUN})

func grab_initial_focus() -> void:
	if not _views.is_empty():
		_views[0].grab_focus()

func _on_card_picked(card_id: String) -> void:
	_selected = card_id
	for v: CardView in _views:
		v.set_selected(v.card_id == card_id)
	_confirm.disabled = false
	_confirm.grab_focus()

func _on_confirm() -> void:
	if _selected.is_empty():
		return
	card_confirmed.emit(_selected)
