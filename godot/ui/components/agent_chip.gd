class_name AgentChip
extends Button
## Мини-портрет агента в TopBar. Тап — камера к агенту, второй тап — карточка;
## решает это владелец, компонент только сообщает о нажатиях.

signal tapped(agent_id: int)
signal double_tapped(agent_id: int)

## Второй тап засчитывается, если пришёл раньше этого времени.
const DOUBLE_TAP_SEC: float = 0.35
const STRIPE_H: float = 4.0
## Поля вокруг слова статуса: чип растёт под самое длинное из них.
const LABEL_PAD_PX: float = 8.0

var agent_id: int = -1

var _letter: String = "?"
var _need: float = 100.0
var _dead: bool = false
var _compact: bool = false
## Чем человек занят прямо сейчас, одним словом. Оверлей «кто чем занят»
## (F4) знал это и раньше — но новичок про него не знает, а «люди странно
## ведут» была второй претензией первого живого игрока (FIX-playtest-01 §2).
var _state: int = int(SimTypes.AgentState.IDLE)
var _status: String = ""
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
func setup(id: int, initial: String, worst_need: float, dead: bool = false,
		state: int = -1) -> void:
	_apply_defaults()
	agent_id = id
	_letter = initial.substr(0, 1).to_upper()
	_need = clampf(worst_need, 0.0, 100.0)
	_dead = dead
	disabled = dead
	if state >= 0:
		_state = state
	_refresh_status()
	queue_redraw()

## Слово статуса и ширина под него. Перевод берётся здесь, а не в _draw:
## _draw зовётся на каждый кадр перерисовки, tr() — нет.
func _refresh_status() -> void:
	_status = tr("STATE_SHORT_%d" % _state)
	custom_minimum_size = Vector2(
		float(UITokens.SPACE_5) if _compact else full_width(),
		float(UITokens.TOUCH_MIN))

## Ширина чипа СО СЛОВОМ — независимо от того, сжат он сейчас или нет.
## По ней TopBar решает, влезает ли строка: мерить текущую ширину нельзя,
## сжатый чип влезает всегда, и решение начало бы дребезжать каждый кадр.
func full_width() -> float:
	if _font == null:
		return float(UITokens.TOUCH_MIN)
	return maxf(float(UITokens.TOUCH_MIN),
		_font.get_string_size(_status, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			_font_size).x + LABEL_PAD_PX * 2.0)

## Сжатый чип — точка-статус без слова (docs/01 §2). Включается и по числу
## людей, и когда строка перестала помещаться в окно (TopBar._apply_compact).
func set_compact(on: bool) -> void:
	_compact = on
	_refresh_status()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_apply_theme()
	elif what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh_status()
		queue_redraw()

func _apply_theme() -> void:
	_font = get_theme_font("font", "Label")
	_font_size = get_theme_font_size("font_size", "Label")
	_refresh_status()
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
	var letter_size: Vector2 = _font.get_string_size(_letter,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size)
	# Буква вверху, слово статуса под ней: две строки в высоте цели касания.
	var top: float = roundf(float(_font_size) * 0.9)
	draw_string(_font, Vector2(roundf((size.x - letter_size.x) * 0.5), top),
		_letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size,
		UITokens.FAINT if _dead else UITokens.INK)
	var status_size: Vector2 = _font.get_string_size(_status,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size)
	draw_string(_font, Vector2(roundf((size.x - status_size.x) * 0.5),
		roundf(size.y - STRIPE_H - 2.0)), _status, HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, _font_size, _status_color())

## Стоящий человек обязан выглядеть иначе, чем работающий: «ждёт» — это
## вопрос к игроку, а не фон (FIX-playtest-01 §2).
func _status_color() -> Color:
	if _dead:
		return UITokens.FAINT
	match _state:
		int(SimTypes.AgentState.IDLE):
			return UIPalette.accent()
		int(SimTypes.AgentState.PANIC), int(SimTypes.AgentState.DROWNING):
			return UIPalette.danger()
	return UITokens.MUTED
