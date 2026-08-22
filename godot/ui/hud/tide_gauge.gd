class_name TideGauge
extends Control
## Шкала прилива: «лицо» игры. Вертикаль = безопасность (кит, артборд F).
##
## Единственный сложный _draw в проекте. Три правила, без которых он ломается:
##   1) ширина линий задаётся ЯВНО — в 4.7 CanvasItem больше не добавляет
##      AA-feather, при -1.0 риски почти не видны (research/06 §9);
##   2) цвета и шрифт кэшируются в _apply_theme — get_theme_* в _draw дорог;
##   3) перерисовка по событиям, а не каждый кадр; таймер фазы — отдельным
##      Timer раз в секунду, иначе шкала перерисуется 60 раз ради двух цифр.
##
## Данные о постройках берутся из событий и кэшируются здесь. HUD sim не читает.

signal legend_requested()
signal beacon_mode_requested()

const MARK_TOP: int = Balance.TOP_MARK          # +6
const MARK_BOTTOM: int = -12                    # низ шкалы (кит, артборд F)
## Ниже дна карты ярусы нарисованы, но выключены: −9…−12 в MVP не открываются
## (кит, исправление №7).
const MARK_FLOOR: int = Balance.BOTTOM_MARK     # −8

const W_TICK: float = 1.0                       # мелкая риска
const W_MARK: float = 2.0                       # подписанная риска (каждые 2 яруса)
const W_PLATEAU: float = 2.0                    # линия плато LOW
const W_ARROW: float = 2.0

const FORECAST_CYCLES: int = 3
const FORECAST_H: float = 22.0
const HEADER_H: float = 48.0

## id -> {mark, flooded, damaged}. Кэш живёт здесь и чистится на run_started:
## забыть — значит после Continue видеть постройки прошлого забега (research/21 §1).
var _buildings: Dictionary[int, Dictionary] = {}
## цикл -> тип кризиса; наполняется crisis_announced, чистится на run_started.
var _announced: Dictionary[int, int] = {}

var _level: float = Balance.HIGH_LEVEL
var _phase: int = int(SimTypes.Phase.EBB)
var _cycle: int = 1
var _low_plateau: float = Balance.LOW_LEVEL
var _high_plateau: float = Balance.HIGH_LEVEL
var _ticks_left: int = 0

var _font: Font = null
var _font_size: int = UITokens.FONT_S
var _timer: Timer = null
var _phase_label: Label = null
var _time_label: Label = null
var _beacon_button: PixelButton = null

func _ready() -> void:
	custom_minimum_size = Vector2(float(UITokens.TIDE_WIDTH), 0.0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	tooltip_text = "HUD_TIDE_TOOLTIP"
	_build()
	_apply_theme()
	resized.connect(queue_redraw)

	Events.run_started.connect(_on_run_started)
	Events.water_level_changed.connect(_on_level)
	Events.phase_changed.connect(_on_phase)
	Events.crisis_announced.connect(_on_crisis_announced)
	Events.building_placed.connect(_on_building_changed)
	Events.building_state_changed.connect(_on_building_changed)
	Events.building_removed.connect(_on_building_removed)

func _build() -> void:
	var box: VBoxContainer = VBoxContainer.new()
	box.name = "Header"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	add_child(box)
	_phase_label = Label.new()
	_phase_label.name = "Phase"
	_phase_label.theme_type_variation = &"LabelSmall"
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_phase_label)
	_time_label = Label.new()
	_time_label.name = "Time"
	_time_label.theme_type_variation = &"LabelNum"
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_time_label)

	# Таймер фазы отдельным Timer: завязать mm:ss на queue_redraw всей шкалы
	# значит перерисовывать её 60 Гц ради двух цифр (research/21 §2).
	_timer = Timer.new()
	_timer.name = "Second"
	_timer.wait_time = 1.0
	_timer.autostart = true
	_timer.timeout.connect(_tick_second)
	add_child(_timer)

	# Маяк живёт на шкале: это единственная кнопка, кроме Отзыва, которая
	# что-то делает с миром (docs/00 §13).
	_beacon_button = PixelButton.new()
	_beacon_button.name = "Beacon"
	_beacon_button.setup("HUD_BEACON", PixelButton.Variant.GHOST)
	_beacon_button.tooltip_text = "HUD_BEACON_TIP"
	_beacon_button.custom_minimum_size = Vector2(float(UITokens.TIDE_WIDTH),
		float(UITokens.TOUCH_MIN))
	_beacon_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_beacon_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_beacon_button.pressed.connect(func() -> void: beacon_mode_requested.emit())
	add_child(_beacon_button)

	var hold: TouchTooltip = TouchTooltip.new()
	hold.name = "Hold"
	add_child(hold)
	hold.setup(self)

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_apply_theme()
	elif what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh_texts()

func _apply_theme() -> void:
	_font = get_theme_font("font", "Label")
	_font_size = get_theme_font_size("font_size", "LabelSmall")
	queue_redraw()

func _make_custom_tooltip(for_text: String) -> Object:
	return TooltipView.make(for_text)

# --- События --------------------------------------------------------------

func _on_run_started(_seed_value: int) -> void:
	_buildings.clear()
	_announced.clear()
	queue_redraw()

func _on_level(level: float) -> void:
	_level = level
	queue_redraw()

func _on_phase(phase: int, cycle: int) -> void:
	_phase = phase
	_cycle = cycle
	_tick_second()
	queue_redraw()

func _on_crisis_announced(type: int, cycle: int) -> void:
	_announced[cycle] = type
	queue_redraw()

## Деталей постройки в событии нет — берём срез через разрешённый query
## (research/21 §1, вариант «б»: событие остаётся дешёвым).
func _on_building_changed(id: int) -> void:
	var b: Dictionary = Game.query_building(id)
	if b.is_empty():
		return
	_buildings[id] = {
		"mark": Balance.cell_to_mark(b["cell"] as Vector2i),
		"flooded": bool(b["flooded"]), "damaged": bool(b["damaged"]),
	}
	queue_redraw()

func _on_building_removed(id: int) -> void:
	_buildings.erase(id)
	queue_redraw()

func _tick_second() -> void:
	var clock: Dictionary = Game.query_clock()
	if clock.is_empty():
		return
	_phase = int(clock["phase"])
	_cycle = int(clock["cycle"])
	_ticks_left = int(clock["ticks_left"])
	_low_plateau = float(clock["low_plateau"])
	_high_plateau = float(clock["high_plateau"])
	_refresh_texts()

func _refresh_texts() -> void:
	if _phase_label == null:
		return
	_phase_label.text = tr("PHASE_%s" % SimTypes.phase_name(_phase))
	var seconds: int = int(round(float(_ticks_left) / float(Balance.TICKS_PER_SEC)))
	_time_label.text = "%d:%02d" % [seconds / 60, seconds % 60]

# --- Ввод -----------------------------------------------------------------

## «Тап по шкале — тултип-легенда» (docs/01 §2). Мышь ловим наравне с пальцем:
## на ПК тапа не бывает, и легенда была недостижима вовсе (аудит B2.10).
func _gui_input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null and not touch.pressed:
		legend_requested.emit()
		accept_event()
		return
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and not click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		legend_requested.emit()
		accept_event()

# --- Геометрия ------------------------------------------------------------

## roundf обязателен: дробный Y растеризуется в полупрозрачную линию и риски
## «дрожат» при ресайзе (research/21 §2).
func _mark_to_y(m: float) -> float:
	var top: float = HEADER_H + FORECAST_H
	var usable: float = maxf(size.y - top - float(UITokens.SPACE_2), 1.0)
	var t: float = (float(MARK_TOP) - m) / float(MARK_TOP - MARK_BOTTOM)
	return roundf(top + t * usable)

# --- Отрисовка ------------------------------------------------------------

func _draw() -> void:
	var w: float = size.x
	draw_rect(Rect2(Vector2.ZERO, size), UITokens.PAPER, true)
	_draw_forecast(w)
	_draw_water(w)
	_draw_plateau(w)
	_draw_ticks(w)
	_draw_buildings(w)
	_draw_float(w)

## Порядок слоёв — снизу вверх: вода, плато, риски, постройки, поплавок.
func _draw_water(w: float) -> void:
	var y: float = _mark_to_y(_level)
	var bottom: float = _mark_to_y(float(MARK_BOTTOM))
	var water: Color = UIPalette.water()
	draw_rect(Rect2(Vector2(0.0, y), Vector2(w, bottom - y)),
		Color(water.r, water.g, water.b, 0.55), true)
	# Глубина ниже −6 холоднее: та же температурная ось, что и в мире.
	var deep_y: float = _mark_to_y(-6.0)
	if deep_y < bottom:
		draw_rect(Rect2(Vector2(0.0, maxf(deep_y, y)), Vector2(w, bottom - maxf(deep_y, y))),
			Color(UITokens.COLD_DEEP.r, UITokens.COLD_DEEP.g, UITokens.COLD_DEEP.b, 0.35), true)
	draw_line(Vector2(0.0, y), Vector2(w, y), UIPalette.water(), W_MARK)

func _draw_plateau(w: float) -> void:
	var y: float = _mark_to_y(_low_plateau)
	# Пунктир: сплошная линия спорит с кромкой воды.
	var x: float = 0.0
	while x < w:
		draw_line(Vector2(x, y), Vector2(minf(x + 4.0, w), y), UITokens.MUTED, W_PLATEAU)
		x += 8.0

func _draw_ticks(w: float) -> void:
	for m: int in range(MARK_BOTTOM, MARK_TOP + 1):
		var y: float = _mark_to_y(float(m))
		var labeled: bool = m % 2 == 0
		var dead: bool = m < MARK_FLOOR
		var c: Color = UITokens.DIVIDER if dead else UITokens.BORDER
		if m == 0:
			c = UIPalette.warm()          # ярус 0 — граница тепла и холода
		draw_line(Vector2(0.0, y), Vector2(w * (0.35 if not labeled else 0.55), y),
			c, W_MARK if labeled else W_TICK)
		if not labeled or _font == null:
			continue
		var text: String = str(m)
		draw_string(_font, Vector2(w * 0.6, y + float(_font_size) * 0.35), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size,
			UITokens.FAINT if dead else UITokens.MUTED)

## Точки построек по отметкам: норма / повреждена / затоплена.
func _draw_buildings(w: float) -> void:
	for id: int in _buildings:
		var b: Dictionary = _buildings[id]
		var y: float = _mark_to_y(float(int(b["mark"])))
		var c: Color = UIPalette.success()
		if bool(b["flooded"]):
			c = UIPalette.water()
		if bool(b["damaged"]):
			c = UIPalette.danger()
		draw_rect(Rect2(Vector2(w - 12.0, y - 2.0), Vector2(4.0, 4.0)), c, true)

## Поплавок уровня: треугольник у левого края + число отметки.
func _draw_float(w: float) -> void:
	var y: float = _mark_to_y(_level)
	var pts: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, y - 6.0), Vector2(10.0, y), Vector2(0.0, y + 6.0)])
	draw_colored_polygon(pts, UIPalette.accent())
	draw_line(Vector2(0.0, y), Vector2(w, y), UIPalette.accent(), W_ARROW)
	if _font == null:
		return
	var text: String = "%.1f" % _level
	var tw: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		_font_size).x
	# Подложка: без неё число уровня сливается с подписью яруса.
	draw_rect(Rect2(Vector2(11.0, y - float(_font_size)),
		Vector2(tw + 4.0, float(_font_size) + 2.0)), UITokens.PAPER, true)
	draw_string(_font, Vector2(13.0, y - 4.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size, UIPalette.accent())

## Прогноз: три ближайших цикла. Тип показываем только для объявленных
## кризисов — календарь заранее игроку не открыт (docs/00 §9).
func _draw_forecast(w: float) -> void:
	var box: float = w / float(FORECAST_CYCLES)
	for i: int in FORECAST_CYCLES:
		var cycle: int = _cycle + i
		var x: float = float(i) * box
		var rect: Rect2 = Rect2(Vector2(x + 2.0, HEADER_H), Vector2(box - 4.0, FORECAST_H - 4.0))
		var type: int = int(_announced.get(cycle, -1))
		var c: Color = UITokens.BORDER
		var letter: String = "-"
		match type:
			int(SimTypes.CrisisType.SPRING_TIDE):
				c = UIPalette.water()
				letter = "^"
			int(SimTypes.CrisisType.STORM):
				c = UIPalette.danger()
				letter = "!"
			int(SimTypes.CrisisType.VISIT):
				c = UIPalette.warm()
				letter = "*"
		draw_rect(rect, Color(c.r, c.g, c.b, 0.25), true)
		draw_rect(rect, c, false, W_TICK)
		if _font == null:
			continue
		draw_string(_font, Vector2(rect.position.x + 4.0, rect.position.y + FORECAST_H - 8.0),
			letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size, c)
