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

## Фолбэк обязателен: на десктопе и в headless get_display_safe_area вернёт
## весь экран, разность окажется нулём и отступов не будет вовсе (research/20 §7).
const SAFE_FALLBACK: int = 12

var tide_gauge: TideGauge = null
var top_bar: TopBar = null
var recall: RecallButton = null
var toasts: ToastStack = null
var banner: BannerView = null
var notices: NoticeQueue = null

var _margin: MarginContainer = null
## id -> {flooded, damaged}: тост показываем на ПЕРЕХОДЕ, а не на каждом
## событии, иначе одна затопленная постройка даст сотню тостов за цикл.
var _building_state: Dictionary[int, Dictionary] = {}
var _banner_paused: bool = false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
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
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
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

	var middle: HBoxContainer = HBoxContainer.new()
	middle.name = "Middle"
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(middle)

	tide_gauge = TideGauge.new()
	tide_gauge.name = "TideGauge"
	middle.add_child(tide_gauge)
	tide_gauge.legend_requested.connect(func() -> void: legend_requested.emit())

	var right: Control = Control.new()
	right.name = "Right"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.add_child(right)

	toasts = ToastStack.new()
	toasts.name = "ToastStack"
	toasts.set_anchors_preset(Control.PRESET_FULL_RECT)
	right.add_child(toasts)
	toasts.focus_requested.connect(_on_toast_focus)

	recall = RecallButton.new()
	recall.name = "RecallButton"
	recall.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	recall.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	recall.grow_vertical = Control.GROW_DIRECTION_BEGIN
	right.add_child(recall)

	banner = BannerView.new()
	banner.name = "Banner"
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
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

## Оверлеи мира: F2/F3/F4. Тумблеры, одновременно активен один.
func _unhandled_input(event: InputEvent) -> void:
	for pair: Array in [["overlay_marks", GameOverlay.MODE_MARKS],
			["overlay_flood", GameOverlay.MODE_FLOOD],
			["overlay_jobs", GameOverlay.MODE_JOBS]]:
		if event.is_action_pressed(str(pair[0])):
			overlay_requested.emit(str(pair[1]))
			get_viewport().set_input_as_handled()
			return

# --- События -> уведомления -----------------------------------------------

func _on_run_started(_seed_value: int) -> void:
	_building_state.clear()
	_banner_paused = false
	notices.clear()
	banner.hide_banner()

func _on_crisis_announced(type: int, cycle: int) -> void:
	notices.push(NoticeQueue.Kind.BANNER, {
		"title": _crisis_key(type), "text": "%s_D" % _crisis_key(type),
		"tone": _crisis_tone(type), "type": type, "cycle": cycle})

func _on_crisis_started(type: int) -> void:
	notices.push(NoticeQueue.Kind.BANNER, {
		"title": _crisis_key(type), "text": "%s_D" % _crisis_key(type),
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

func _toast(type: String, text: String, tone: Toast.Tone,
		cell: Vector2i = Vector2i.ZERO, life: float = -1.0) -> void:
	notices.push(NoticeQueue.Kind.TOAST, {"type": type, "text": text,
		"tone": tone, "cell": cell, "life": life})

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

static func _crisis_key(type: int) -> String:
	match type:
		int(SimTypes.CrisisType.SPRING_TIDE): return "CRISIS_SPRING_TIDE"
		int(SimTypes.CrisisType.STORM): return "CRISIS_STORM"
	return "CRISIS_VISIT"

static func _crisis_tone(type: int) -> BannerView.Tone:
	match type:
		int(SimTypes.CrisisType.STORM): return BannerView.Tone.DANGER
		int(SimTypes.CrisisType.SPRING_TIDE): return BannerView.Tone.WARN
	return BannerView.Tone.WARN
