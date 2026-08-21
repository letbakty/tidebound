class_name AgentChip
extends Button
## Мини-портрет агента в TopBar. Тап — камера к агенту, второй тап — карточка;
## решает это владелец, компонент только сообщает о нажатиях.

signal tapped(agent_id: int)
signal double_tapped(agent_id: int)

## Второй тап засчитывается, если пришёл раньше этого времени.
const DOUBLE_TAP_SEC: float = 0.35
const STRIPE_H: float = 4.0

var agent_id: int = -1

var _letter: String = "?"
var _need: float = 100.0
var _dead: bool = false
var _compact: bool = false
var _last_tap_ms: int = -100000
var _font: Font = null
var _font_size: int = UITokens.FONT_S

func _ready() -> void:
	_apply_defaults()
	_apply_theme()

## Настройка себя — и из _ready, и из setup: компонент должен быть корректным
## ещё до входа в дерево.
func _apply_defaults() -> void:
	focus_mode = Control.FOCUS_ALL
	toggle_mode = false
	custom_minimum_size = Vector2(float(UITokens.TOUCH_MIN), float(UITokens.TOUCH_MIN))
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)

## worst_need — худшая из потребностей 0..100: цвет нижней полоски.
func setup(id: int, initial: String, worst_need: float, dead: bool = false) -> void:
	_apply_defaults()
	agent_id = id
	_letter = initial.substr(0, 1).to_upper()
	_need = clampf(worst_need, 0.0, 100.0)
	_dead = dead
	disabled = dead
	queue_redraw()

## При >8 агентах чипы сжимаются до точек-статусов (docs/01 §2).
func set_compact(on: bool) -> void:
	_compact = on
	custom_minimum_size = Vector2(
		float(UITokens.TOUCH_MIN if not on else UITokens.SPACE_5),
		float(UITokens.TOUCH_MIN))
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_apply_theme()

func _apply_theme() -> void:
	_font = get_theme_font("font", "Label")
	_font_size = get_theme_font_size("font_size", "Label")
	queue_redraw()

func _on_pressed() -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_tap_ms <= int(DOUBLE_TAP_SEC * 1000.0):
		_last_tap_ms = -100000
		double_tapped.emit(agent_id)
		return
	_last_tap_ms = now
	tapped.emit(agent_id)

func _draw() -> void:
	var stripe: Rect2 = Rect2(Vector2(0.0, size.y - STRIPE_H), Vector2(size.x, STRIPE_H))
	var c: Color = UITokens.FAINT if _dead else UITokens.need_color(_need)
	draw_rect(stripe, c, true)
	if _compact or _font == null:
		return
	var text_size: Vector2 = _font.get_string_size(_letter,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size)
	var pos: Vector2 = Vector2(
		roundf((size.x - text_size.x) * 0.5),
		roundf((size.y + float(_font_size) * 0.6) * 0.5) - STRIPE_H)
	draw_string(_font, pos, _letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size,
		UITokens.FAINT if _dead else UITokens.INK)
