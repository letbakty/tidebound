class_name Hud
extends Control
## Сборка HUD: шкала прилива слева, строка сверху, тосты и Отзыв справа внизу,
## банер сверху по центру. Три постоянные зоны и ни одной больше (docs/01 §2).
##
## HUD не читает sim: только Events вверх, Game.cmd_* вниз и разрешённые
## Game.query_* по месту (docs/02 §3.3).

signal camera_focus_requested(world_pos: Vector2)
signal agent_card_requested(agent_id: int)
signal overlay_requested(mode: String)
signal legend_requested()
signal beacon_mode_requested()
## Кнопка «Политики» в верхней строке: панель открывает Main.
signal policies_requested()

## Фолбэк обязателен: на десктопе и в headless get_display_safe_area вернёт
## весь экран, разность окажется нулём и отступов не будет вовсе (research/20 §7).
const SAFE_FALLBACK: int = 12
## Сколько живёт легенда шкалы, если её не закрыли повторным тапом.
const LEGEND_LIFE_SEC: float = 12.0
## Легенда — десять строк текста, а не подпись к кнопке: узкий тултип превратил
## бы её в лапшу из одного слова в строке.
const LEGEND_WIDTH_PX: float = 320.0
## Подсказка размещения — одна фраза с требованием, а не абзац.
const BUILD_HINT_WIDTH_PX: float = 280.0
## Строки легенды по порядку сверху вниз.
const LEGEND_KEYS: Array[String] = ["HUD_LEGEND_TITLE", "HUD_LEGEND_LEVEL",
	"HUD_LEGEND_MARKS", "HUD_LEGEND_PLATEAU", "HUD_LEGEND_DOTS",
	"HUD_LEGEND_FORECAST", "HUD_LEGEND_SPRING", "HUD_LEGEND_STORM",
	"HUD_LEGEND_VISIT", "HUD_LEGEND_QUIET"]
## Ключ группировки персистентного тоста «колония на грани»: его снимают
## по имени два разных события, и строка в трёх местах разъехалась бы.
const TOAST_COLONY_EDGE: String = "colony_edge"

var tide_gauge: TideGauge = null
var top_bar: TopBar = null
var recall: RecallButton = null
var toasts: ToastStack = null
var banner: BannerView = null
var notices: NoticeQueue = null
var press: PressIndicator = null
var hints: ButtonHints = null
var cursor: GamepadCursor = null

## Легенда шкалы прилива: тап по шкале (docs/01 §2). Тултип, а не панель —
## ничего не закрывает и уходит сам.
var _legend: TooltipView = null
## Причина отказа размещения. Живёт ЗДЕСЬ, а не в мире: в мировом вьюпорте
## 640×360 подпись занимает несколько пикселей высоты, и на 1080p прочитать её
## нельзя — игрок видел красный призрак без единого слова (FIX-playtest-01 §3).
var _build_tip: TooltipView = null
var _legend_timer: Timer = null
var _margin: MarginContainer = null
## id -> {flooded, damaged}: тост показываем на ПЕРЕХОДЕ, а не на каждом
## событии, иначе одна затопленная постройка даст сотню тостов за цикл.
var _building_state: Dictionary[int, Dictionary] = {}
var _banner_paused: bool = false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Полноэкранный Control поверх мира со STOP гарантированно сломал бы всё
	# управление миром (research/19 §5, п.4).
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_connect_events()
	get_tree().root.size_changed.connect(_apply_safe_area)
	_apply_safe_area()

func _build() -> void:
	_margin = MarginContainer.new()
	_margin.name = "Safe"
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_margin)

	var rows: VBoxContainer = VBoxContainer.new()
	rows.name = "Rows"
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.add_child(rows)

	top_bar = TopBar.new()
	top_bar.name = "TopBar"
	rows.add_child(top_bar)
	top_bar.agent_focus_requested.connect(_on_agent_focus)
	top_bar.agent_card_requested.connect(func(id: int) -> void:
		agent_card_requested.emit(id))
	top_bar.policies_requested.connect(func() -> void:
		policies_requested.emit())

	var middle: HBoxContainer = HBoxContainer.new()
	middle.name = "Middle"
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(middle)

	tide_gauge = TideGauge.new()
	tide_gauge.name = "TideGauge"
	middle.add_child(tide_gauge)
	tide_gauge.legend_requested.connect(_on_legend_requested)
	tide_gauge.beacon_mode_requested.connect(func() -> void:
		beacon_mode_requested.emit())

	var right: Control = Control.new()
	right.name = "Right"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.add_child(right)

	toasts = ToastStack.new()
	toasts.name = "ToastStack"
	toasts.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	right.add_child(toasts)
	toasts.focus_requested.connect(_on_toast_focus)

	# ⚠️ «Отзыв» висит на КОРНЕ HUD, а не в ячейке строки: минимальная ширина
	# верхней строки в живой игре (кнопки скоростей + четыре ресурса + чипы
	# агентов) больше окна на Deck и при UI 125%, MarginContainer раздувается
	# шире экрана — и единственная командная кнопка игры уезжала за правый край
	# на 65 px, то есть не нажималась вовсе. Пустой HUD в тестах этого не
	# показывает: минимум там считается по ненаполненной строке (test_edge_cases
	# hud_fits_extreme_resolutions зелёный). Поймано кликом в playtest_run.
	recall = RecallButton.new()
	recall.name = "RecallButton"
	recall.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	recall.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	recall.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(recall)

	banner = BannerView.new()
	banner.name = "Banner"
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.custom_minimum_size = Vector2(560.0, 0.0)
	banner.dismissed.connect(_on_banner_dismissed)
	add_child(banner)
	# Банер живёт ПОД строкой ресурсов: наехав на неё, он закрывает ровно те
	# числа, ради которых игрок и смотрит на объявление кризиса.
	top_bar.resized.connect(_place_banner)
	_place_banner()

	notices = NoticeQueue.new()
	notices.name = "Notices"
	add_child(notices)
	notices.show_banner.connect(_on_show_banner)
	notices.show_toast.connect(_on_show_toast)

	# Мёртвая зона тостов считается от кнопки, а не «на глаз в пикселях».
	toasts.set_deadzone(float(UITokens.DEADZONE_PX))

	hints = ButtonHints.new()
	hints.name = "ButtonHints"
	hints.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hints.grow_vertical = Control.GROW_DIRECTION_BEGIN
	rows.add_child(hints)

	# Индикатор удержания и курсор — поверх всего HUD и без мыши.
	press = PressIndicator.new()
	press.name = "PressIndicator"
	press.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(press)
	cursor = GamepadCursor.new()
	cursor.name = "GamepadCursor"
	cursor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cursor)

	_legend = TooltipView.new()
	_legend.name = "TideLegend"
	_legend.visible = false
	add_child(_legend)
	_build_tip = TooltipView.new()
	_build_tip.name = "BuildHint"
	_build_tip.visible = false
	add_child(_build_tip)
	_legend_timer = Timer.new()
	_legend_timer.name = "LegendLife"
	_legend_timer.one_shot = true
	_legend_timer.timeout.connect(hide_legend)
	add_child(_legend_timer)

## Тап по шкале — тумблер легенды (docs/01 §2).
func _on_legend_requested() -> void:
	legend_requested.emit()
	if _legend == null:
		return
	if _legend.visible:
		hide_legend()
	else:
		_show_legend()

## Легенда шкалы: что означают риски, точки и значки прогноза. Значки названы
## СЛОВАМИ — для дальтоника прогноз шкалы это главный инструмент планирования
## (docs/01 §6), и один цвет тут не канал.
func _show_legend() -> void:
	var lines: Array[String] = []
	for key: String in LEGEND_KEYS:
		lines.append(tr(key))
	_legend.setup("\n".join(lines), LEGEND_WIDTH_PX)
	_legend.position = Vector2(
		tide_gauge.global_position.x + tide_gauge.size.x + float(UITokens.SPACE_3),
		tide_gauge.global_position.y + float(UITokens.SPACE_3)) - global_position
	_legend.visible = true
	_legend_timer.start(LEGEND_LIFE_SEC)

func hide_legend() -> void:
	if _legend != null:
		_legend.visible = false

## Причина отказа размещения у призрака. text — уже переведённая строка,
## at — точка ОКНА, куда смотрит игрок (её считает Main: только он знает
## про растяжку мирового вьюпорта).
func show_build_hint(text: String, at: Vector2) -> void:
	if _build_tip == null:
		return
	if text.is_empty():
		hide_build_hint()
		return
	_build_tip.setup(text, BUILD_HINT_WIDTH_PX)
	_build_tip.visible = true
	# Размер панели известен только после раскладки: до неё клампить нечем.
	_build_tip.reset_size()
	var pos: Vector2 = at - global_position \
		- Vector2(_build_tip.size.x * 0.5, _build_tip.size.y + float(UITokens.SPACE_3))
	_build_tip.position = pos.clamp(Vector2(float(UITokens.SPACE_2),
		float(UITokens.SPACE_2)), size - _build_tip.size
		- Vector2(float(UITokens.SPACE_2), float(UITokens.SPACE_2)))

func hide_build_hint() -> void:
	if _build_tip != null:
		_build_tip.visible = false

## Легенда собирается одной строкой заранее и авто-перевода не получает: при
## смене языка на открытой легенде её надо пересобрать руками.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _legend != null \
			and _legend.visible:
		_show_legend()

func _place_banner() -> void:
	if banner == null or top_bar == null:
		return
	# Считаем от НИЖНЕЙ кромки строки в координатах корня HUD: сама строка
	# лежит внутри safe-area, а банер — нет.
	banner.offset_top = top_bar.global_position.y - global_position.y \
		+ top_bar.size.y + float(UITokens.SPACE_3)

func _connect_events() -> void:
	Events.run_started.connect(_on_run_started)
	Events.crisis_announced.connect(_on_crisis_announced)
	Events.crisis_started.connect(_on_crisis_started)
	Events.agent_drowning.connect(_on_agent_drowning)
	Events.agent_died.connect(_on_agent_died)
	Events.agent_spawned.connect(_on_agent_spawned)
	Events.creature_spawned.connect(_on_creature_spawned)
	Events.building_state_changed.connect(_on_building_state)
	Events.building_removed.connect(func(id: int) -> void: _building_state.erase(id))
	Events.cycle_ended.connect(_on_cycle_ended)
	Events.ship_arrived.connect(_on_ship_arrived)
	Events.recall_issued.connect(_on_recall_issued)

## Safe area — в физических пикселях экрана, а UI живёт в единицах контента:
## при content_scale_factor != 1 отступы надо делить на фактор.
##
## ⚠️ ПРОВЕРЕНО на macOS: get_display_safe_area() возвращает область ЭКРАНА
## за вычетом системной панели (60 px на Retina), а не окна — на десктопе от
## неё HUD уезжает вниз на пустом месте. Поэтому вырез спрашиваем только на
## телефонах, а на всём остальном берём минимум из docs/01 §5.
func _apply_safe_area() -> void:
	var win: Vector2i = DisplayServer.window_get_size()
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var left: int = SAFE_FALLBACK
	var top: int = SAFE_FALLBACK
	var right: int = SAFE_FALLBACK
	var bottom: int = SAFE_FALLBACK
	if OS.has_feature("mobile") and safe.size.x > 0 and safe.size.y > 0 \
			and safe.size != win:
		var f: float = maxf(get_tree().root.content_scale_factor, 0.01)
		left = maxi(int(float(safe.position.x) / f), SAFE_FALLBACK)
		top = maxi(int(float(safe.position.y) / f), SAFE_FALLBACK)
		right = maxi(int(float(win.x - safe.end.x) / f), SAFE_FALLBACK)
		bottom = maxi(int(float(win.y - safe.end.y) / f), SAFE_FALLBACK)
	_margin.add_theme_constant_override("margin_left", left)
	_margin.add_theme_constant_override("margin_top", top)
	_margin.add_theme_constant_override("margin_right", right)
	_margin.add_theme_constant_override("margin_bottom", bottom)
	# Кнопка отзыва живёт вне этого контейнера — отступы вырезаем ей отдельно.
	if recall != null:
		recall.offset_right = -float(right)
		recall.offset_bottom = -float(bottom)

## Оверлеи мира: F2/F3/F4. Тумблеры, одновременно активен один.
func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return                          # HUD скрыт экраном — F2/F3/F4 не наши
	for pair: Array in [["overlay_marks", GameOverlay.MODE_MARKS],
			["overlay_flood", GameOverlay.MODE_FLOOD],
			["overlay_jobs", GameOverlay.MODE_JOBS]]:
		if event.is_action_pressed(str(pair[0])):
			overlay_requested.emit(str(pair[1]))
			get_viewport().set_input_as_handled()
			return

# --- События -> уведомления -----------------------------------------------

## ⚠️ Банер уносит свою автопаузу С СОБОЙ. run_started приходит не только на
## новый забег: его же шлёт rebroadcast_state (загрузка сейва, промотка времени
## дебаг-панелью), а там счётчик автопауз никто не обнуляет. Сброшенный флаг без
## pop_pause оставлял паузу висеть навсегда — при том, что банера на экране уже
## нет и снять её нечем.
func _on_run_started(_seed_value: int) -> void:
	_building_state.clear()
	if _banner_paused:
		_banner_paused = false
		Game.pop_pause()
	notices.clear()
	banner.hide_banner()
	# Стек тостов только что очищен (ToastStack._on_run_started), а колония
	# после «Продолжить» может стоять ровно на пороге: предупреждение обязано
	# вернуться вместе с ней, иначе загрузка молча снимает единственный
	# сигнал о том, что следующая смерть заканчивает забег.
	_check_colony_edge()

func _on_crisis_announced(type: int, cycle: int) -> void:
	notices.push(NoticeQueue.Kind.BANNER, {
		"title": crisis_key(type), "text": "%s_D" % crisis_key(type),
		"tone": _crisis_tone(type), "type": type, "cycle": cycle})

func _on_crisis_started(type: int) -> void:
	notices.push(NoticeQueue.Kind.BANNER, {
		"title": crisis_key(type), "text": "%s_D" % crisis_key(type),
		"tone": _crisis_tone(type), "type": type, "cycle": 0})

## Автопауза — только на ПЕРВОМ появлении типа за забег: дальше игрок уже
## знает, что это, и пауза начинает мешать (промпт 13 п.5).
func _on_show_banner(payload: Dictionary) -> void:
	banner.show_banner(str(payload["title"]), str(payload["text"]),
		payload["tone"] as BannerView.Tone)
	banner.grab_initial_focus()
	if Game.note_banner(int(payload["type"])):
		_banner_paused = true
		Game.push_pause()

func _on_banner_dismissed() -> void:
	banner.hide_banner()
	if _banner_paused:
		_banner_paused = false
		Game.pop_pause()
	notices.release(NoticeQueue.Kind.BANNER)

func _on_show_toast(payload: Dictionary) -> void:
	toasts.push(str(payload["type"]), str(payload["text"]),
		payload["tone"] as Toast.Tone, payload.get("cell", Vector2i.ZERO) as Vector2i,
		float(payload.get("life", -1.0)))

## life = −1 — «по умолчанию»: длительность берёт настройка доступности
## «сколько живёт тост», где 0 значит «не закрывать сами» (docs/03 §3.6).
## Ползунок иначе не делал ничего вовсе (аудит B4). Явное число сильнее:
## тост тонущего persistent по своей природе.
##
## Настройку читает HUD, а не сам Toast: компонентам про Settings знать нельзя
## (tests/test_ui, components_are_pure).
func _toast(type: String, text: String, tone: Toast.Tone,
		cell: Vector2i = Vector2i.ZERO, life: float = -1.0) -> void:
	notices.push(NoticeQueue.Kind.TOAST, {"type": type, "text": text,
		"tone": tone, "cell": cell,
		"life": Settings.toast_seconds if life < 0.0 else life})

## Тонущий — единственный персистентный тост: он не должен исчезнуть раньше,
## чем игрок нажмёт Отзыв (docs/01 §2).
func _on_agent_drowning(id: int) -> void:
	var a: Dictionary = Game.query_agent(id)
	_toast("drowning", tr("TOAST_DROWNING").format({"name": a.get("name", "?")}),
		Toast.Tone.DANGER, _agent_cell(id), 0.0)

func _on_agent_died(id: int, cause: String) -> void:
	var key: String = "CAUSE_%s" % cause.to_upper()
	# tr() возвращает сам ключ, если его нет: незнакомая причина не должна
	# выводить на экран сырой UPPER_SNAKE (research/22 §3.1).
	var cause_text: String = tr(key)
	if cause_text == key:
		cause_text = tr("CAUSE_UNKNOWN")
	_toast("death", tr("TOAST_DIED").format(
		{"name": _dead_name(id), "cause": cause_text}),
		Toast.Tone.DANGER, _agent_cell(id))
	_check_colony_edge()

## Колония на грани: живых ровно столько, сколько нужно, чтобы забег
## закончился на СЛЕДУЮЩЕЙ границе цикла (Balance.WIPE_THRESHOLD, docs/00
## §11.2). Порог без предупреждения — несправедливость, а не сложность,
## поэтому тост персистентный: он живёт до конца цикла или до прихода
## человека, а не гаснет через пять секунд вместе с тостом о смерти.
func _check_colony_edge() -> void:
	if Game.query_survivors().size() != Balance.WIPE_THRESHOLD:
		return
	_toast(TOAST_COLONY_EDGE, tr("TOAST_COLONY_EDGE").format(
		{"n": Balance.WIPE_THRESHOLD}), Toast.Tone.DANGER, Vector2i.ZERO, 0.0)

## Пришёл человек — колония уже не на грани.
func _on_agent_spawned(_id: int) -> void:
	toasts.dismiss(TOAST_COLONY_EDGE)

func _on_creature_spawned(_id: int) -> void:
	_toast("creature", tr("TOAST_CREATURE"), Toast.Tone.WARN)

func _on_building_state(id: int) -> void:
	var b: Dictionary = Game.query_building(id)
	if b.is_empty():
		return
	var was: Dictionary = _building_state.get(id, {})
	var flooded: bool = bool(b["flooded"])
	var damaged: bool = bool(b["damaged"])
	var cell: Vector2i = b["cell"] as Vector2i
	if damaged and not bool(was.get("damaged", false)):
		_toast("damaged", tr("TOAST_DAMAGED").format(
			{"name": tr(DB.building(str(b["def_id"])).display_key)}),
			Toast.Tone.WARN, cell)
	if flooded and not bool(was.get("flooded", false)):
		_toast("flooded", tr("TOAST_FLOODED").format(
			{"name": tr(DB.building(str(b["def_id"])).display_key)}),
			Toast.Tone.INFO, cell)
	_building_state[id] = {"flooded": flooded, "damaged": damaged}

## Потери за цикл приходят одним отчётом — из него и делаем тост, а не
## слушаем каждый смытый стак отдельно.
func _on_cycle_ended(report: Dictionary) -> void:
	# Предупреждение живёт ровно один цикл: границу колония пережила.
	toasts.dismiss(TOAST_COLONY_EDGE)
	var washed: int = int(report.get("washed", 0))
	if washed > 0:
		_toast("washed", tr("TOAST_WASHED").format({"n": washed}), Toast.Tone.WARN)
	var spoiled: Dictionary = report.get("spoiled", {}) as Dictionary
	var spoiled_n: int = 0
	for k: Variant in spoiled:
		spoiled_n += int(spoiled[k])
	if spoiled_n > 0:
		_toast("spoiled", tr("TOAST_SPOILED").format({"n": spoiled_n}), Toast.Tone.WARN)

func _on_ship_arrived() -> void:
	_toast("ship", tr("TOAST_SHIP"), Toast.Tone.INFO)

func _on_recall_issued(hard: bool) -> void:
	_toast("recall", tr("TOAST_RECALL_HARD" if hard else "TOAST_RECALL"),
		Toast.Tone.INFO)

# --- Камера ---------------------------------------------------------------

func _on_agent_focus(agent_id: int) -> void:
	camera_focus_requested.emit(Game.query_agent_pos(agent_id))

func _on_toast_focus(cell: Vector2i) -> void:
	if cell == Vector2i.ZERO:
		return
	camera_focus_requested.emit(WorldGeo.cell_center_world(cell))

# --- Мелочи ---------------------------------------------------------------

func _agent_cell(id: int) -> Vector2i:
	return WorldGeo.world_to_cell(Game.query_agent_pos(id))

func _dead_name(id: int) -> String:
	var a: Dictionary = Game.query_agent(id)
	return str(a.get("name", "?"))

## Ключ названия кризиса: им пользуются и экраны итогов.
static func crisis_key(type: int) -> String:
	match type:
		int(SimTypes.CrisisType.SPRING_TIDE): return "CRISIS_SPRING_TIDE"
		int(SimTypes.CrisisType.STORM): return "CRISIS_STORM"
	return "CRISIS_VISIT"

static func _crisis_tone(type: int) -> BannerView.Tone:
	match type:
		int(SimTypes.CrisisType.STORM): return BannerView.Tone.DANGER
		int(SimTypes.CrisisType.SPRING_TIDE): return BannerView.Tone.WARN
	return BannerView.Tone.WARN
