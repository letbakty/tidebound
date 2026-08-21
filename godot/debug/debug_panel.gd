extends Control
## Дебаг-панель: время, вода, оверлеи, забег, лог сигналов. F1 — тумблер.
##
## Живёт на DebugLayer главной сцены (CanvasLayer layer=100 из этапа 00) —
## в НАТИВНОМ разрешении, а не в мировом вьюпорте: иначе текст пикселизуется
## вместе с миром и становится нечитаемым (research/13 §2).
##
## Создаётся только в debug-сборке, и создаётся, а не прячется: скрытая панель
## утащила бы в релиз сцену, скрипт и все подписки на Events.

const LOG_MAX: int = 200
const PANEL_W: float = 340.0
const GRAPH_SAMPLES: int = 120
const TICK_BUDGET_MS: float = 2.0     # бюджет тика из docs/00 §16

var _overlay: DebugOverlay = null
var _log: Array[String] = []
var _log_dirty: bool = false
var _samples: PackedFloat32Array = PackedFloat32Array()
var _touch_ids: Dictionary[int, bool] = {}

var _box: VBoxContainer = null
var _time_label: Label = null
var _log_label: Label = null
var _graph: Control = null
var _water_slider: HSlider = null
var _water_on: CheckBox = null
var _seed_edit: LineEdit = null
var _beacon_label: Label = null
var _build_hint: Label = null
var _crisis_label: Label = null
var _card_label: Label = null
var _card_row: HBoxContainer = null
var _card_shown: Array[String] = []
var _meta_label: Label = null

const CRISIS_NAMES: Dictionary = {
	SimTypes.CrisisType.SPRING_TIDE: "сизигия",
	SimTypes.CrisisType.STORM: "шторм",
	SimTypes.CrisisType.VISIT: "приход",
}
var _policy_sliders: Dictionary[int, HSlider] = {}
var _policy_labels: Dictionary[int, Label] = {}

const POLICY_NAMES: Dictionary = {
	SimTypes.Policy.GREED: "Жадность",
	SimTypes.Policy.CAUTION: "Осторожность",
	SimTypes.Policy.REPAIR: "Ремонт",
	SimTypes.Policy.BUILD: "Стройка",
	SimTypes.Policy.SUPPLY: "Заготовка",
	SimTypes.Policy.REST: "Отдых",
}

## world — корень мира: в него кладётся оверлей, потому что он рисует
## мировые координаты.
func setup(world: Node2D) -> void:
	_overlay = DebugOverlay.new()
	_overlay.name = "DebugOverlay"
	world.add_child(_overlay)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_LEFT_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build_ui()
	_connect_all_events()

func _build_ui() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.custom_minimum_size = Vector2(PANEL_W, 0.0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	_box = VBoxContainer.new()
	panel.add_child(_box)

	# --- Время ---
	_head("ВРЕМЯ")
	_time_label = _label("—")
	var speeds: HBoxContainer = _row()
	for m: int in 4:
		var b: Button = Button.new()
		b.text = "пауза" if m == 0 else "×%d" % m
		b.pressed.connect(func() -> void: Game.cmd_set_speed(m))
		speeds.add_child(b)
	var skips: HBoxContainer = _row()
	_button(skips, "+1 фаза", func() -> void:
		Game.debug_fast_forward(Game.debug_ticks_to_next_phase()))
	_button(skips, "+1 цикл", func() -> void:
		Game.debug_fast_forward(Game.debug_ticks_to_next_cycle()))
	_graph = Control.new()
	_graph.custom_minimum_size = Vector2(0.0, 40.0)
	_graph.draw.connect(_draw_graph)
	_box.add_child(_graph)

	# --- Вода ---
	_head("ВОДА")
	_water_on = CheckBox.new()
	_water_on.text = "override"
	_water_on.toggled.connect(_on_water_override_toggled)
	_box.add_child(_water_on)
	_water_slider = HSlider.new()
	_water_slider.min_value = -12.0
	_water_slider.max_value = 3.0
	_water_slider.step = 0.1
	_water_slider.value = 0.0
	_water_slider.value_changed.connect(_on_water_slider)
	_box.add_child(_water_slider)

	# --- Мир ---
	_head("МИР")
	for pair: Array in [["graph", "граф навигации"], ["marks", "отметки ярусов"],
			["deposits", "остатки депозитов"], ["flood", "затопление"]]:
		var cb: CheckBox = CheckBox.new()
		cb.text = str(pair[1])
		var key: String = str(pair[0])
		cb.toggled.connect(func(on: bool) -> void:
			if _overlay != null:
				_overlay.set_flag(key, on))
		_box.add_child(cb)

	# --- Политики (панель игрока — этап 14; здесь дебажный дублёр) ---
	_head("ПОЛИТИКИ")
	_policy_labels.clear()
	for pol: int in SimTypes.POLICY_ORDER:
		var row: HBoxContainer = _row()
		var lbl: Label = Label.new()
		lbl.custom_minimum_size = Vector2(150.0, 0.0)
		row.add_child(lbl)
		_policy_labels[pol] = lbl
		var sl: HSlider = HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 3.0
		sl.step = 1.0
		sl.custom_minimum_size = Vector2(140.0, 0.0)
		sl.value_changed.connect(func(v: float) -> void:
			Game.cmd_set_policy(pol, int(v)))
		row.add_child(sl)
		_policy_sliders[pol] = sl

	# --- Маяк ---
	_head("МАЯК")
	var beacon_row: HBoxContainer = _row()
	_beacon_label = Label.new()
	beacon_row.add_child(_beacon_label)
	_button(beacon_row, "поставить по курсору", _on_place_beacon)
	_button(beacon_row, "отзыв", func() -> void: Game.cmd_recall(false))

	# --- Стройка (радиал — этап 14; здесь дебажный дублёр) ---
	_head("СТРОЙКА")
	var row1: HBoxContainer = _row()
	var row2: HBoxContainer = _row()
	var i: int = 0
	for bid: String in DB.building_ids():
		var target: HBoxContainer = row1 if i < 9 else row2
		i += 1
		var b: Button = Button.new()
		b.text = tr(DB.building(bid).display_key).substr(0, 4)
		b.tooltip_text = bid
		b.pressed.connect(func() -> void: _select_building(bid))
		target.add_child(b)
	var row3: HBoxContainer = _row()
	_button(row3, "отменить призрак", func() -> void: _select_building(""))
	_build_hint = _label("—")

	# --- Забег ---
	_head("ЗАБЕГ")
	var run_row: HBoxContainer = _row()
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "сид"
	_seed_edit.text = "20260821"
	_seed_edit.custom_minimum_size = Vector2(120.0, 0.0)
	run_row.add_child(_seed_edit)
	_button(run_row, "новый забег", _on_new_run)
	_button(run_row, "завершить цикл", func() -> void:
		Game.debug_fast_forward(Game.debug_ticks_to_next_cycle()))

	_head("СЕЙВ И ЖУРНАЛ")
	var save_row: HBoxContainer = _row()
	_button(save_row, "сохранить", func() -> void: Game.cmd_save())
	_button(save_row, "загрузить", func() -> void: Game.cmd_load())
	_button(save_row, "стереть профиль", func() -> void: Meta.wipe())
	var end_row: HBoxContainer = _row()
	_button(end_row, "уйти досрочно", func() -> void: Game.cmd_leave_early())
	_button(end_row, "сдаться", func() -> void: Game.cmd_surrender())
	_meta_label = _label("—")

	_head("КАРТЫ")
	_card_label = _label("—")
	_card_row = _row()

	_head("КРИЗИСЫ")
	_crisis_label = _label("—")

	_head("СОБЫТИЯ")
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 220.0)
	_box.add_child(scroll)
	# Label, а не RichTextLabel: BBCode не нужен, а перерасчёт лейаута на
	# каждый append за забег съел бы больше, чем сама симуляция.
	_log_label = Label.new()
	_log_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	scroll.add_child(_log_label)

func _head(text: String) -> void:
	var l: Label = Label.new()
	l.text = "── " + text
	_box.add_child(l)

func _label(text: String) -> Label:
	var l: Label = Label.new()
	l.text = text
	_box.add_child(l)
	return l

func _row() -> HBoxContainer:
	var h: HBoxContainer = HBoxContainer.new()
	_box.add_child(h)
	return h

func _button(parent: Node, text: String, cb: Callable) -> void:
	var b: Button = Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)

# --- Ввод -----------------------------------------------------------------

## _unhandled_input, а не _input: иначе F1, нажатая при фокусе в поле сида,
## и откроет панель, и напечатается в поле.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_panel"):
		visible = not visible
		get_viewport().set_input_as_handled()
		return
	_handle_overlay_hotkeys(event)
	_handle_four_finger(event)

func _handle_overlay_hotkeys(event: InputEvent) -> void:
	for pair: Array in [["overlay_marks", "marks"], ["overlay_flood", "flood"],
			["overlay_jobs", "graph"]]:
		if not event.is_action_pressed(str(pair[0])):
			continue
		var key: String = str(pair[1])
		if _overlay == null:
			return
		var now: bool = not _flag_of(key)
		_overlay.set_flag(key, now)
		_sync_checkbox(key, now)
		get_viewport().set_input_as_handled()
		return

func _flag_of(key: String) -> bool:
	match key:
		"graph": return _overlay.show_graph
		"marks": return _overlay.show_marks
		"deposits": return _overlay.show_deposits
		"flood": return _overlay.show_flood
	return false

func _sync_checkbox(key: String, on: bool) -> void:
	var titles: Dictionary = {
		"graph": "граф навигации", "marks": "отметки ярусов",
		"deposits": "остатки депозитов", "flood": "затопление",
	}
	for n: Node in _box.get_children():
		var cb: CheckBox = n as CheckBox
		if cb != null and cb.text == str(titles.get(key, "")):
			cb.set_pressed_no_signal(on)

## Заглушка-хук четырёхпальцевого тапа. Счёт по index, а не инкрементом:
## при потере события «отпускание» счётчик залипал бы навсегда.
func _handle_four_finger(event: InputEvent) -> void:
	var t: InputEventScreenTouch = event as InputEventScreenTouch
	if t == null:
		return
	if t.pressed:
		_touch_ids[t.index] = true
	else:
		_touch_ids.erase(t.index)
	if t.pressed and _touch_ids.size() >= 4:
		visible = not visible

# --- Обновление -----------------------------------------------------------

func _process(_delta: float) -> void:
	# Закрытая панель не должна стоить ничего.
	if not visible:
		return
	_refresh_time()
	_refresh_policies()
	_refresh_build_hint()
	_refresh_crises()
	_refresh_cards()
	_refresh_meta()
	if _log_dirty:
		_log_dirty = false
		_log_label.text = "\n".join(_log)
	_samples.append(Game.tick_budget_ms())
	if _samples.size() > GRAPH_SAMPLES:
		_samples.remove_at(0)
	_graph.queue_redraw()

func _refresh_time() -> void:
	if Game.world == null:
		_time_label.text = "забег не начат"
		return
	var c: SimClock = Game.world.clock
	_time_label.text = "тик %d · цикл %d · %s %d%% · вода %.2f · скорость ×%d" % [
		c.total_ticks(), c.cycle, SimTypes.phase_name(int(c.phase)),
		int(c.phase_progress() * 100.0), Game.world.tide.level, Game.speed]

func _draw_graph() -> void:
	var h: float = _graph.size.y
	var w: float = _graph.size.x
	_graph.draw_rect(Rect2(0.0, 0.0, w, h), Color(0, 0, 0, 0.35), true)
	var budget_y: float = h - h * 0.5
	_graph.draw_line(Vector2(0.0, budget_y), Vector2(w, budget_y),
		Color(1.0, 0.4, 0.4, 0.5), 1.0)
	if _samples.size() < 2:
		return
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in _samples.size():
		pts.append(Vector2(w * float(i) / float(GRAPH_SAMPLES),
			h - clampf(_samples[i] / (TICK_BUDGET_MS * 2.0), 0.0, 1.0) * h))
	_graph.draw_polyline(pts, Color("7fd8a0"), 1.0)

# --- Вода -----------------------------------------------------------------

func _on_water_override_toggled(on: bool) -> void:
	if Game.world == null:
		return
	Game.world.tide.level_override = _water_slider.value if on else NAN
	_push_water()

func _on_water_slider(v: float) -> void:
	if Game.world == null or not _water_on.button_pressed:
		return
	Game.world.tide.level_override = v
	_push_water()

## Оверрайд обязан двигать воду и is_flooded в тот же кадр, даже на паузе,
## когда тика не будет.
func _push_water() -> void:
	var tide: Tide = Game.world.tide
	if not is_nan(tide.level_override):
		tide.level = tide.level_override
	Events.water_level_changed.emit(tide.level)

func _refresh_policies() -> void:
	if Game.world == null:
		return
	for pol: int in SimTypes.POLICY_ORDER:
		var v: int = Game.world.policies.get_value(pol)
		(_policy_labels[pol] as Label).text = "%s %d" % [str(POLICY_NAMES[pol]), v]
		var sl: HSlider = _policy_sliders[pol]
		if int(sl.value) != v:
			sl.set_value_no_signal(float(v))
	var b: Vector2i = Game.world.beacon_cell()
	_beacon_label.text = "нет" if b == Balance.NO_BEACON else "%d,%d" % [b.x, b.y]

## Ставит маяк в клетку под курсором мыши. Полноценный режим установки —
## этап 14; здесь достаточно кнопки для проверки скоринга.
func _on_place_beacon() -> void:
	var world_view: Node = get_tree().root.find_child("World", true, false)
	if world_view == null:
		return
	var vp: Viewport = world_view.get_viewport()
	var world_pos: Vector2 = world_view.call("screen_to_world", vp.get_mouse_position())
	Game.cmd_set_beacon(WorldGeo.world_to_cell(world_pos))

## Включает призрак размещения выбранной постройки.
func _select_building(def_id: String) -> void:
	var ghost: Node = get_tree().root.find_child("BuildGhost", true, false)
	if ghost == null:
		return
	ghost.call("set_def", def_id)
	_build_hint.text = "—" if def_id.is_empty() else def_id

## Драфт до появления панели карт (этап 15): кнопка на каждую карту.
func _refresh_meta() -> void:
	var st: Dictionary = Meta.stats()
	var ship: String = "—"
	if Game.world != null:
		ship = "цикл %d" % Game.world.run_state.ship_cycle
	_meta_label.text = "очки %d · забегов %d (побед %d) · разблокировок %d · судно %s" % [
		int(st["points_total"]), int(st["runs_played"]), int(st["runs_won"]),
		Meta.unlocked.size(), ship]

func _refresh_cards() -> void:
	if Game.world == null:
		return
	var draft: Array[String] = Game.world.run_state.draft
	var active: String = Game.world.run_state.active_card
	_card_label.text = "выбрано: %s" % ("—" if active.is_empty() else active)
	if draft == _card_shown:
		return
	_card_shown = draft.duplicate()
	for n: Node in _card_row.get_children():
		n.queue_free()
	for id: String in draft:
		var b: Button = Button.new()
		b.text = tr(DB.card(id).display_key)
		b.tooltip_text = tr(DB.card(id).desc_key)
		b.pressed.connect(func() -> void: Game.cmd_pick_card(id))
		_card_row.add_child(b)

func _refresh_crises() -> void:
	if Game.world == null:
		return
	var now: PackedStringArray = PackedStringArray()
	for type: int in Game.world.crisis.active:
		now.append(str(CRISIS_NAMES.get(type, type)))
	var soon: PackedStringArray = PackedStringArray()
	for type2: int in Game.world.crisis.announced:
		soon.append(str(CRISIS_NAMES.get(type2, type2)))
	_crisis_label.text = "сейчас: %s · объявлено: %s · существ: %d" % [
		"—" if now.is_empty() else ", ".join(now),
		"—" if soon.is_empty() else ", ".join(soon),
		Game.world.crisis.creatures.size()]

func _refresh_build_hint() -> void:
	var ghost: Node = get_tree().root.find_child("BuildGhost", true, false)
	if ghost == null or str(ghost.get("def_id")).is_empty():
		return
	var def_id: String = str(ghost.get("def_id"))
	var cell: Vector2i = ghost.call("current_cell")
	var err: String = Game.query_place_error(def_id, cell)
	_build_hint.text = "%s @ %d,%d — %s" % [def_id, cell.x, cell.y,
		"можно" if err.is_empty() else tr(err)]

func _on_new_run() -> void:
	Game.cmd_new_run(_seed_edit.text.to_int())

# --- Лог сигналов ---------------------------------------------------------

## Подписка на ВСЕ сигналы Events рефлексией: сигналы, добавленные будущими
## этапами, попадут в лог сами. Заодно это «санитария сигналов» этапа 19.
##
## bind() тут не годится: он дописывает аргумент в конец, арность у сигналов
## разная — сигнатура не совпадёт, и обработчик молча не вызовется.
func _connect_all_events() -> void:
	for sig: Dictionary in Events.get_signal_list():
		var sname: String = str(sig["name"])
		var argc: int = (sig["args"] as Array).size()
		var cb: Callable
		match argc:
			0:
				cb = func() -> void: _log_event(sname, [])
			1:
				cb = func(a1: Variant) -> void: _log_event(sname, [a1])
			2:
				cb = func(a1: Variant, a2: Variant) -> void: _log_event(sname, [a1, a2])
			_:
				push_warning("DebugPanel: сигнал %s с %d аргументами не логируется"
					% [sname, argc])
				continue
		Events.connect(sname, cb)

func _log_event(sname: String, args: Array) -> void:
	# sim_ticked идёт 10 раз в секунду и вытеснил бы из буфера всё остальное.
	if sname == "sim_ticked":
		return
	_log.append("%s %s" % [sname, str(args)])
	if _log.size() > LOG_MAX:
		_log.remove_at(0)
	_log_dirty = true
