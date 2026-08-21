class_name RecallButton
extends Control
## Единственная командная кнопка игры: Отзыв. Правый низ, «мёртвая зона» —
## её не перекрывает ничто (docs/01 §2).
##
## Два нажатия подряд = жёсткий отзыв: люди бросают груз и бегут (docs/00 §6.7).

const HARD_WINDOW_SEC: float = 2.0
const PULSE_SCALE: float = 1.08
const PULSE_SEC: float = 0.4

var _button: PixelButton = null
var _below_label: Label = null
var _tween: Tween = null
var _last_press_ms: int = -100000
var _phase: int = int(SimTypes.Phase.EBB)
## id -> отметка агента: считаем «сколько внизу осталось» по кэшу событий.
var _marks: Dictionary[int, float] = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(float(UITokens.DEADZONE_PX), float(UITokens.DEADZONE_PX))
	_build()
	Events.run_started.connect(_on_run_started)
	Events.phase_changed.connect(_on_phase_changed)
	Events.agent_updated.connect(_on_agent_updated)
	Events.agent_spawned.connect(_on_agent_updated)
	Events.agent_died.connect(_on_agent_died)
	Events.water_level_changed.connect(_on_level.unbind(1))

func _build() -> void:
	var box: VBoxContainer = VBoxContainer.new()
	box.name = "Box"
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.alignment = BoxContainer.ALIGNMENT_END
	add_child(box)

	_below_label = Label.new()
	_below_label.name = "Below"
	_below_label.theme_type_variation = &"LabelSmall"
	_below_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_below_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_below_label.visible = false
	box.add_child(_below_label)

	_button = PixelButton.new()
	_button.name = "Button"
	_button.setup("HUD_RECALL", PixelButton.Variant.PRIMARY)
	_button.tooltip_text = "HUD_RECALL_TIP"
	# Цель заведомо крупнее минимума: это главная кнопка на телефоне.
	_button.custom_minimum_size = Vector2(96.0, 64.0)
	_button.pressed.connect(_on_pressed)
	box.add_child(_button)

func _on_pressed() -> void:
	var now: int = Time.get_ticks_msec()
	var hard: bool = now - _last_press_ms <= int(HARD_WINDOW_SEC * 1000.0)
	_last_press_ms = now
	Game.cmd_recall(hard)
	# Жёсткий отзыв виден глазом: кнопка краснеет до конца фазы.
	_button.variant = PixelButton.Variant.DANGER if hard else PixelButton.Variant.PRIMARY

func _on_run_started(_seed_value: int) -> void:
	_marks.clear()
	_refresh_below()

func _on_phase_changed(phase: int, _cycle: int) -> void:
	_phase = phase
	_button.variant = PixelButton.Variant.PRIMARY
	_apply_pulse()
	_refresh_below()

## Пульсация только на Сигнале: это момент, когда кнопка нужна (docs/01 §2).
## Хранить ссылку и убивать перед новым — иначе два твина спорят за scale
## и кнопка дёргается (research/21 §3).
func _apply_pulse() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	_button.pivot_offset = _button.size * 0.5
	_button.scale = Vector2.ONE
	if _phase != int(SimTypes.Phase.SIGNAL):
		return
	_tween = create_tween().set_loops()
	_tween.tween_property(_button, "scale", Vector2.ONE * PULSE_SCALE, PULSE_SEC) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_button, "scale", Vector2.ONE, PULSE_SEC) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _on_agent_updated(id: int) -> void:
	var a: Dictionary = Game.query_agent(id)
	if a.is_empty():
		return
	_marks[id] = float(a["mark"])
	_refresh_below()

func _on_agent_died(id: int, _cause: String) -> void:
	_marks.erase(id)
	_refresh_below()

func _on_level() -> void:
	_refresh_below()

## «Внизу осталось: N» — только в Сигнале и Высокой воде: в отлив внизу быть
## нормально, и постоянный счётчик превратился бы в шум.
func _refresh_below() -> void:
	if _below_label == null:
		return
	var danger: bool = _phase == int(SimTypes.Phase.SIGNAL) \
		or _phase == int(SimTypes.Phase.HIGH)
	var n: int = 0
	for id: int in _marks:
		if _marks[id] < 0.0:
			n += 1
	_below_label.visible = danger and n > 0
	if _below_label.visible:
		_below_label.text = tr("HUD_BELOW_LEFT").format({"n": n})

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh_below()
