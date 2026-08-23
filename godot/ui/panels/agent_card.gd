class_name AgentCard
extends BottomSheet
## Карточка агента: кто это, чем занят, чего ему не хватает (docs/03 §5.2).
##
## Данные берутся синхронным срезом Game.query_agent — единственный
## разрешённый «pull» (docs/02 §3.3). Обновляется раз в секунду, пока открыта:
## _process тут был бы шестьюдесятью запросами в секунду ради трёх полосок.

signal focus_requested(agent_id: int)

const PORTRAITS: String = "res://assets/sprites/portraits.png"
const PORTRAIT: int = 32
## Портрет закреплён за агентом его номером: карточка одного и того же агента
## обязана открываться с тем же лицом, иначе колония расползается.
static var _portrait_cache: Dictionary[int, Texture2D] = {}

const NEEDS: Array[String] = ["satiety", "warmth", "mood"]
const NEED_KEYS: Dictionary[String, String] = {
	"satiety": "NEED_SATIETY", "warmth": "NEED_WARMTH", "mood": "NEED_MOOD",
}
const BAG_SLOTS: int = Balance.BAG_SLOTS

var agent_id: int = -1

var _name: Label = null
var _portrait: TextureRect = null
var _bio: Label = null
var _state: Label = null
var _traits: HBoxContainer = null
var _bars: Dictionary[String, ProgressBar] = {}
var _bar_labels: Dictionary[String, Label] = {}
var _bag: HBoxContainer = null
var _gear: IconStub = null
var _timer: Timer = null
var _focus_button: PixelButton = null

## Сигнатуры последнего отрисованного состояния рядов: пересобираем только
## когда содержимое реально изменилось.
var _traits_sig: String = ""
var _bag_sig: String = ""

func _ready() -> void:
	super()
	_build_card()

static func portrait_for(id: int) -> Texture2D:
	var atlas: Texture2D = load(PORTRAITS) as Texture2D
	if atlas == null:
		return null
	var count: int = maxi(1, atlas.get_width() / PORTRAIT)
	var idx: int = posmod(id, count)
	if _portrait_cache.has(idx):
		return _portrait_cache[idx]
	var t: AtlasTexture = AtlasTexture.new()
	t.atlas = atlas
	t.region = Rect2(float(idx * PORTRAIT), 0.0, float(PORTRAIT), float(PORTRAIT))
	_portrait_cache[idx] = t
	return t

func _build_card() -> void:
	if _name != null:
		return
	setup("PANEL_AGENT", true)

	# Портрет рядом с именем: восемь силуэтов на колонию из двенадцати —
	# лица на 32 px всё равно не читаются, различает силуэт и поза.
	var head: HBoxContainer = HBoxContainer.new()
	head.name = "Head"
	add_content(head)
	_portrait = TextureRect.new()
	_portrait.name = "Portrait"
	_portrait.custom_minimum_size = Vector2(float(PORTRAIT), float(PORTRAIT))
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_portrait)
	_name = Label.new()
	_name.name = "Name"
	_name.theme_type_variation = &"LabelTitle"
	_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_name)

	_bio = Label.new()
	_bio.name = "Bio"
	_bio.theme_type_variation = &"LabelSmall"
	UILayout.wrap(_bio, 320.0)
	add_content(_bio)

	_traits = HBoxContainer.new()
	_traits.name = "Traits"
	add_content(_traits)

	for need: String in NEEDS:
		var row: HBoxContainer = HBoxContainer.new()
		row.name = "Need_%s" % need
		add_content(row)
		var label: Label = Label.new()
		label.theme_type_variation = &"LabelSmall"
		label.custom_minimum_size = Vector2(120.0, 0.0)
		label.text = NEED_KEYS[need]
		row.add_child(label)
		var bar: ProgressBar = ProgressBar.new()
		bar.custom_minimum_size = Vector2(160.0, float(UITokens.SPACE_5))
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.max_value = 100.0
		bar.show_percentage = false
		row.add_child(bar)
		var value: Label = Label.new()
		value.theme_type_variation = &"LabelNum"
		value.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		row.add_child(value)
		_bars[need] = bar
		_bar_labels[need] = value

	_state = Label.new()
	_state.name = "State"
	add_content(_state)

	var bag_row: HBoxContainer = HBoxContainer.new()
	bag_row.name = "BagRow"
	add_content(bag_row)
	var bag_label: Label = Label.new()
	bag_label.theme_type_variation = &"LabelSmall"
	bag_label.text = "AGENT_BAG"
	bag_row.add_child(bag_label)
	_bag = HBoxContainer.new()
	_bag.name = "Bag"
	bag_row.add_child(_bag)
	_gear = IconStub.new()
	_gear.name = "Gear"
	bag_row.add_child(_gear)

	_focus_button = PixelButton.new()
	_focus_button.name = "Focus"
	_focus_button.setup("AGENT_SHOW", PixelButton.Variant.PRIMARY)
	_focus_button.pressed.connect(func() -> void: focus_requested.emit(agent_id))
	add_content(_focus_button)

	_timer = Timer.new()
	_timer.name = "Refresh"
	_timer.wait_time = 1.0
	_timer.timeout.connect(_refresh)
	add_child(_timer)

func open_with(args: Dictionary) -> void:
	agent_id = int(args.get("id", -1))
	_traits_sig = ""                # другой агент — другие черты и котомка
	_bag_sig = ""
	_refresh()
	_timer.start()

## Таймер обязан останавливаться: закрытая карточка не должна дёргать sim.
func on_closed() -> void:
	_timer.stop()

func grab_initial_focus() -> void:
	if _focus_button != null:
		_focus_button.grab_focus()

func _refresh() -> void:
	var a: Dictionary = Game.query_agent(agent_id)
	if a.is_empty():
		return
	_name.text = str(a["name"])
	_portrait.texture = portrait_for(agent_id)
	_bio.text = tr(str(a["bio"]))
	_state.text = tr("STATE_%d" % int(a["state"]))
	for need: String in NEEDS:
		var v: float = float(a[need])
		_bars[need].value = v
		_bar_labels[need].text = "%d" % int(round(v))
		# Цвет полосы — по порогам потребности; рядом всегда число.
		var fill: StyleBoxFlat = UIThemeFactory.flat(UITokens.need_color(v),
			UITokens.need_color(v), 0, 0)
		_bars[need].add_theme_stylebox_override("fill", fill)
	_refresh_traits(a["traits"] as Array)
	_refresh_bag(a["bag"] as Array, bool(a["has_gear"]))

## Черты за забег не меняются, котомка — редко, а карточка обновляется раз в
## секунду: без сравнения сигнатуры оба ряда пересоздавались вхолостую вместе
## со всеми их тултипами (аудит B3).
static func _sig(items: Array) -> String:
	return JSON.stringify(items)

func _refresh_traits(ids: Array) -> void:
	var sig: String = _sig(ids)
	if sig == _traits_sig:
		return
	_traits_sig = sig
	for c: Node in _traits.get_children():
		_traits.remove_child(c)
		c.queue_free()
	for v: Variant in ids:
		var trait_id: String = str(v)
		var def: TraitDef = DB.trait_def(trait_id)
		if def == null:
			continue
		var chip: PixelButton = PixelButton.new()
		chip.setup(def.display_key, PixelButton.Variant.GHOST)
		# Тап по черте — что она делает (docs/03 §5.2).
		chip.tooltip_text = def.desc_key
		_traits.add_child(chip)

func _refresh_bag(bag: Array, has_gear: bool) -> void:
	var sig: String = "%s|%s" % [_sig(bag), has_gear]
	if sig == _bag_sig:
		return
	_bag_sig = sig
	for c: Node in _bag.get_children():
		_bag.remove_child(c)
		c.queue_free()
	for i: int in BAG_SLOTS:
		var slot: IconStub = IconStub.new()
		_bag.add_child(slot)
		if i < bag.size():
			var stack: Dictionary = bag[i] as Dictionary
			var item_id: String = str(stack["item_id"])
			slot.setup_item(item_id,
				UIPalette.warm() if bool(stack.get("wet", false)) else UITokens.INK,
				UITokens.SPACE_5)
			# IconStub по умолчанию IGNORE — на нём тултипа не увидеть; и имя
			# предмета берём из дефа, а не сырым id (аудит B2.9, B4).
			slot.mouse_filter = Control.MOUSE_FILTER_PASS
			slot.tooltip_text = "%s ×%d" % [
				tr(StationPanel.item_key(item_id)), int(stack["count"])]
		else:
			slot.setup(".", UITokens.FAINT, UITokens.SPACE_5)
	_gear.visible = has_gear
	if has_gear:
		_gear.setup_item("gear", UIPalette.accent(), UITokens.SPACE_5)
