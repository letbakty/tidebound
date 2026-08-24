class_name PolicyPanel
extends PixelPanel
## Шторка политик справа: шесть ползунков, изменение применяется мгновенно.
## Политики — единственный постоянный рычаг игрока (docs/00 §6.6).

const WIDTH: float = 360.0

## Ключи подписей значений: POLICY_<ИМЯ>_<0..3>. Словарь описаний живёт здесь,
## компонент своих текстов не сочиняет (docs/03 §5.1).
const NAME_KEYS: Dictionary[int, String] = {
	SimTypes.Policy.GREED: "POLICY_GREED",
	SimTypes.Policy.CAUTION: "POLICY_CAUTION",
	SimTypes.Policy.REPAIR: "POLICY_REPAIR",
	SimTypes.Policy.BUILD: "POLICY_BUILD",
	SimTypes.Policy.SUPPLY: "POLICY_SUPPLY",
	SimTypes.Policy.REST: "POLICY_REST",
}

var _sliders: Dictionary[int, PolicySlider] = {}
var _hint: Label = null

func _ready() -> void:
	super()
	set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	# Не во всю высоту окна: внизу справа мёртвая зона «Отзыва», и шторка
	# обязана над ней остановиться (docs/01 §2, антипаттерн Fallout Shelter).
	offset_bottom = -float(UITokens.DEADZONE_PX)
	custom_minimum_size = Vector2(WIDTH, 0.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	setup_ui()
	Events.policy_changed.connect(_on_policy_changed)

func setup_ui() -> void:
	if not _sliders.is_empty():
		return
	setup("PANEL_POLICIES", true)
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.theme_type_variation = &"LabelSmall"
	UILayout.wrap(_hint, WIDTH - float(UITokens.SPACE_5) * 2.0)
	_hint.text = "POLICY_HINT"
	add_content(_hint)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# ⚠️ ScrollContainer наследует минимальный размер содержимого: без явного
	# минимума панель вырастает на 1900 px и уезжает за экран.
	scroll.custom_minimum_size = Vector2(0.0, 240.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_content(scroll)
	var box: VBoxContainer = VBoxContainer.new()
	box.name = "List"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	for policy: int in SimTypes.POLICY_ORDER:
		var slider: PolicySlider = PolicySlider.new()
		slider.name = "Policy%d" % policy
		box.add_child(slider)
		slider.setup(policy, 0, NAME_KEYS[policy], _describe)
		slider.value_picked.connect(_on_picked)
		_sliders[policy] = slider

## Панель открывается уже настроенной: значения приносит policy_changed,
## но событие могло прийти до её создания — поэтому берём срез.
func open_with(_args: Dictionary) -> void:
	var values: Dictionary = Game.query_policies()
	for policy: int in _sliders:
		_sliders[policy].set_value(int(values.get(policy, 0)))

func grab_initial_focus() -> void:
	for policy: int in SimTypes.POLICY_ORDER:
		if _sliders.has(policy):
			_sliders[policy].grab_initial_focus()
			return

func _on_picked(policy: int, value: int) -> void:
	Game.cmd_set_policy(policy, value)

func _on_policy_changed(policy: int, value: int) -> void:
	if _sliders.has(policy):
		_sliders[policy].set_value(value)

## «Осторожность 2: возврат за 40 секунд до воды» — значение словами.
##
## У Жадности подпись обязана называть СЛЕДСТВИЕ числом: «не дальше восьми
## шагов от лестницы». Первый живой игрок увидел, что колонисты не спускаются,
## назвал это багом — и был прав в том, что игра нигде не сказала ему про
## предел (FIX-playtest-01 §1). Число берётся из Balance.GREED_LADDER_LIMIT,
## а не из литерала в строке: балансный проход правит шкалу, и подпись
## обязана поехать вместе с ней.
func _describe(policy: int, value: int) -> String:
	var text: String = tr("POLICY_%d_%d" % [policy, value])
	if policy == int(SimTypes.Policy.GREED):
		var limit: int = Balance.GREED_LADDER_LIMIT[
			clampi(value, 0, Balance.GREED_LADDER_LIMIT.size() - 1)]
		if limit >= 0:
			return text.format({"n": limit})
	return text
