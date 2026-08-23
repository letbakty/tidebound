class_name SettingsScreen
extends ScreenBase
## Пять вкладок (docs/03 §3.6): Игра · Экран · Звук · Управление · Доступность.
## Применяется СРАЗУ, без кнопки «Сохранить»; у каждой настройки — строка
## пояснения, иначе половину из них игрок не поймёт.

signal profile_reset()

var _tabs: TabContainer = null
var _tab_keys: Array[String] = ["SET_TAB_GAME", "SET_TAB_SCREEN", "SET_TAB_SOUND",
	"SET_TAB_INPUT", "SET_TAB_ACCESS"]
var _confirm: ConfirmDialog = null
## Действие -> три кнопки слотов (клавиша, вторая клавиша, геймпад).
var _bind_rows: Dictionary[String, Array] = {}
var _capture_note: Label = null
## Действие, для которого ждём нажатие ("" — не ждём).
var _capturing: String = ""
## Какой слот этого действия правим (InputBindings.Slot).
var _capture_slot: int = 0
## Список подключённых геймпадов: обновляется по сигналу, а не при заходе.
var _pads_label: Label = null
var _preset_pick: OptionButton = null

func _ready() -> void:
	super()
	set_title("MENU_SETTINGS")
	_build_settings()
	# Геймпад, подключённый при открытом окне, обязан появиться в списке сам.
	Input.joy_connection_changed.connect(_on_joy_changed)

func _on_joy_changed(_device: int, _connected: bool) -> void:
	_refresh_pads()

func _build_settings() -> void:
	_tabs = TabContainer.new()
	_tabs.name = "Tabs"
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_tabs)
	_tabs.add_child(_build_game_tab())
	_tabs.add_child(_build_screen_tab())
	_tabs.add_child(_build_sound_tab())
	_tabs.add_child(_build_input_tab())
	_tabs.add_child(_build_access_tab())
	_confirm = ConfirmDialog.new()
	_confirm.name = "Confirm"
	add_child(_confirm)
	_confirm.confirmed.connect(_on_reset_confirmed)
	_refresh_tab_titles()

# --- Кирпичики ------------------------------------------------------------

func _tab(name: String) -> VBoxContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return box

## Каждая настройка — со строкой пояснения (docs/03 §3.6).
func _row(box: VBoxContainer, label_key: String, control: Control,
		hint_key: String) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	box.add_child(row)
	var label: Label = Label.new()
	label.text = label_key
	label.custom_minimum_size = Vector2(220.0, 0.0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	var hint: Label = Label.new()
	hint.theme_type_variation = &"LabelSmall"
	UILayout.wrap(hint, 520.0)
	hint.text = hint_key
	box.add_child(hint)

func _check(pressed: bool, on_toggle: Callable) -> CheckBox:
	var cb: CheckBox = CheckBox.new()
	cb.button_pressed = pressed
	cb.custom_minimum_size = Vector2(0.0, float(UITokens.TOUCH_MIN))
	cb.focus_mode = Control.FOCUS_ALL
	cb.toggled.connect(on_toggle)
	return cb

func _slider(value: float, from: float, to: float, step: float,
		on_change: Callable) -> HSlider:
	var s: HSlider = HSlider.new()
	s.min_value = from
	s.max_value = to
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(200.0, float(UITokens.TOUCH_MIN))
	s.focus_mode = Control.FOCUS_ALL
	s.value_changed.connect(on_change)
	return s

func _options(items: Array[String], selected: int, on_pick: Callable) -> OptionButton:
	var o: OptionButton = OptionButton.new()
	o.custom_minimum_size = Vector2(0.0, float(UITokens.TOUCH_MIN))
	o.focus_mode = Control.FOCUS_ALL
	for i: int in items.size():
		o.add_item(tr(items[i]), i)
	o.selected = selected
	o.item_selected.connect(on_pick)
	return o

# --- Вкладки --------------------------------------------------------------

func _build_game_tab() -> Control:
	var box: VBoxContainer = _tab("Game")
	_row(box, "SET_LANGUAGE", _options(["LANG_RU", "LANG_EN"],
		0 if Settings.locale.begins_with("ru") else 1,
		func(i: int) -> void:
			Settings.set_locale("ru" if i == 0 else "en")
			Settings.apply()), "SET_LANGUAGE_HINT")
	_row(box, "SET_HINTS", _check(Settings.hints_enabled, func(on: bool) -> void:
		Settings.hints_enabled = on
		Settings.mark_dirty()), "SET_HINTS_HINT")
	_row(box, "SET_PAUSE_DRAFT", _check(Settings.pause_on_draft, func(on: bool) -> void:
		Settings.pause_on_draft = on
		Settings.mark_dirty()), "SET_PAUSE_DRAFT_HINT")
	_row(box, "SET_PAUSE_CYCLE", _check(Settings.pause_on_cycle, func(on: bool) -> void:
		Settings.pause_on_cycle = on
		Settings.mark_dirty()), "SET_PAUSE_CYCLE_HINT")
	_row(box, "SET_PAUSE_CRISIS", _check(Settings.pause_on_crisis, func(on: bool) -> void:
		Settings.pause_on_crisis = on
		Settings.mark_dirty()), "SET_PAUSE_CRISIS_HINT")
	_row(box, "SET_SPEED", _options(["HUD_SPEED_1", "HUD_SPEED_2", "HUD_SPEED_3"],
		Settings.default_speed - 1, func(i: int) -> void:
			Settings.default_speed = i + 1
			Settings.mark_dirty()), "SET_SPEED_HINT")

	# Блок «Данные» внизу вкладки «Игра» (docs/03 §3.6).
	var data_head: Label = Label.new()
	data_head.theme_type_variation = &"LabelTitle"
	data_head.text = "SET_DATA"
	box.add_child(data_head)
	var path: Label = Label.new()
	path.theme_type_variation = &"LabelSmall"
	path.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	UILayout.wrap(path, 520.0)
	path.text = ProjectSettings.globalize_path("user://")
	box.add_child(path)
	var open_folder: PixelButton = PixelButton.new()
	open_folder.setup("SET_OPEN_FOLDER", PixelButton.Variant.GHOST)
	open_folder.pressed.connect(func() -> void:
		OS.shell_open(ProjectSettings.globalize_path("user://")))
	box.add_child(open_folder)
	var reset: PixelButton = PixelButton.new()
	reset.setup("SET_RESET_PROFILE", PixelButton.Variant.DANGER)
	reset.pressed.connect(_ask_reset)
	box.add_child(reset)
	var version: Label = Label.new()
	version.theme_type_variation = &"LabelSmall"
	version.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	version.text = BootScreen.build_version()
	box.add_child(version)
	return box.get_parent() as Control

func _build_screen_tab() -> Control:
	var box: VBoxContainer = _tab("Screen")
	_row(box, "SET_UI_SCALE", _slider(Settings.ui_scale, Settings.UI_SCALE_MIN,
		Settings.UI_SCALE_MAX, Settings.UI_SCALE_STEP, func(v: float) -> void:
			Settings.ui_scale = v
			Settings.apply()), "SET_UI_SCALE_HINT")
	_row(box, "SET_WORLD_ZOOM", _options(["ZOOM_2", "ZOOM_3", "ZOOM_4"],
		Settings.world_zoom - 2, func(i: int) -> void:
			Settings.world_zoom = i + 2
			Settings.mark_dirty()), "SET_WORLD_ZOOM_HINT")
	_row(box, "SET_FULLSCREEN", _check(Settings.fullscreen, func(on: bool) -> void:
		Settings.fullscreen = on
		Settings.apply()), "SET_FULLSCREEN_HINT")
	_row(box, "SET_VSYNC", _check(Settings.vsync, func(on: bool) -> void:
		Settings.vsync = on
		Settings.apply()), "SET_VSYNC_HINT")
	_row(box, "SET_INTEGER", _check(Settings.integer_scaling, func(on: bool) -> void:
		Settings.integer_scaling = on
		Settings.apply()), "SET_INTEGER_HINT")
	return box.get_parent() as Control

## Диапазон ползунков — константы Settings: на минимуме шина глушится
## по-настоящему, и знать этот край должен один файл, а не два.
func _build_sound_tab() -> Control:
	var box: VBoxContainer = _tab("Sound")
	_row(box, "SET_VOL_MASTER", _slider(Settings.master_db, Settings.MUTE_DB, Settings.MAX_DB, 1.0,
		func(v: float) -> void:
			Settings.master_db = v
			Settings.apply()), "SET_VOL_HINT")
	_row(box, "SET_VOL_MUSIC", _slider(Settings.music_db, Settings.MUTE_DB, Settings.MAX_DB, 1.0,
		func(v: float) -> void:
			Settings.music_db = v
			Settings.apply()), "SET_VOL_HINT")
	_row(box, "SET_VOL_SFX", _slider(Settings.sfx_db, Settings.MUTE_DB, Settings.MAX_DB, 1.0,
		func(v: float) -> void:
			Settings.sfx_db = v
			Settings.apply()), "SET_VOL_HINT")
	_row(box, "SET_VOL_UI", _slider(Settings.ui_db, Settings.MUTE_DB, Settings.MAX_DB, 1.0,
		func(v: float) -> void:
			Settings.ui_db = v
			Settings.apply()), "SET_VOL_HINT")
	_row(box, "SET_VOL_AMBIENT", _slider(Settings.ambient_db, Settings.MUTE_DB, Settings.MAX_DB, 1.0,
		func(v: float) -> void:
			Settings.ambient_db = v
			Settings.apply()), "SET_VOL_HINT")
	# Вибрация есть и у геймпада на ПК: доки Godot прямо просят давать ползунок
	# отключения — «vibration can be uncomfortable for certain players».
	# Скрываем строку только там, где вибрировать нечему.
	if OS.has_feature("mobile") or not Input.get_connected_joypads().is_empty():
		_row(box, "SET_HAPTICS", _check(Settings.haptics, func(on: bool) -> void:
			Settings.haptics = on
			Settings.mark_dirty()), "SET_HAPTICS_HINT")
	return box.get_parent() as Control

## Вкладка «Управление» (docs/03 §3.6): схема · ремап списком с подсветкой
## конфликтов · чувствительность камеры · сброс к умолчаниям.
##
## Служебные действия (ui_*, дебаг, режим съёмки) не переназначаются: их ремап
## ломает навигацию геймпадом, а это прямой отказ в Steam Deck Verified. В
## проверке конфликтов они всё равно участвуют — см. Settings.conflicts().
func _build_input_tab() -> Control:
	var box: VBoxContainer = _tab("Input")
	var note: Label = Label.new()
	UILayout.wrap(note, 520.0)
	note.text = "SET_INPUT_NOTE"
	box.add_child(note)

	# Подключённые устройства — сверху: игрок с неработающим геймпадом первым
	# делом смотрит, видит ли его игра вообще.
	_pads_label = Label.new()
	_pads_label.name = "Pads"
	_pads_label.theme_type_variation = &"LabelSmall"
	_pads_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	UILayout.wrap(_pads_label, 520.0)
	box.add_child(_pads_label)
	_refresh_pads()

	_row(box, "SET_SCHEME", _options(["SCHEME_AUTO", "SCHEME_MOUSE", "SCHEME_PAD",
		"SCHEME_TOUCH"], int(Settings.input_scheme), func(i: int) -> void:
			Settings.set_input_scheme(i)), "SET_SCHEME_HINT")
	_row(box, "SET_CAM_SENS", _slider(Settings.camera_sensitivity,
		Settings.CAM_SENS_MIN, Settings.CAM_SENS_MAX, 0.1, func(v: float) -> void:
			Settings.camera_sensitivity = v
			Settings.mark_dirty()), "SET_CAM_SENS_HINT")
	_row(box, "SET_DEADZONE", _slider(Settings.stick_deadzone,
		Settings.DEADZONE_MIN, Settings.DEADZONE_MAX, 0.05, func(v: float) -> void:
			Settings.stick_deadzone = v
			Settings.mark_dirty()), "SET_DEADZONE_HINT")
	# Профили ВМЕСТЕ с полной свободой — требование Game Accessibility
	# Guidelines. «Своя» не выбирается: она появляется сама, как только игрок
	# правит строку.
	_preset_pick = _options(["PRESET_DEFAULT", "PRESET_ARROWS", "PRESET_ONE_HAND",
		"PRESET_CUSTOM"], Settings.current_preset(), func(i: int) -> void:
			if i == int(Settings.Preset.CUSTOM):
				return
			Settings.apply_preset(i)
			_refresh_bindings())
	_row(box, "SET_PRESET", _preset_pick, "SET_PRESET_HINT")

	var head: HBoxContainer = HBoxContainer.new()
	box.add_child(head)
	var head_action: Label = Label.new()
	head_action.theme_type_variation = &"LabelSmall"
	head_action.text = "SET_ACTION"
	head_action.custom_minimum_size = Vector2(180.0, 0.0)
	head.add_child(head_action)
	for key: String in InputBindings.SLOT_KEYS:
		var h: Label = Label.new()
		h.theme_type_variation = &"LabelSmall"
		h.text = key
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(h)

	_bind_rows.clear()
	for action: String in Settings.REMAPPABLE:
		var row: HBoxContainer = HBoxContainer.new()
		box.add_child(row)
		var label: Label = Label.new()
		label.text = "ACT_%s" % action.to_upper()
		label.custom_minimum_size = Vector2(180.0, 0.0)
		row.add_child(label)
		# Три кнопки вместо одной сплошной: назначение клавиши больше не имеет
		# права стереть кнопку геймпада на том же действии.
		var buttons: Array = []
		for slot: int in InputBindings.SLOT_COUNT:
			var button: PixelButton = PixelButton.new()
			button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.pressed.connect(func() -> void: _start_capture(action, slot))
			row.add_child(button)
			buttons.append(button)
		_bind_rows[action] = buttons
		# Сброс ОДНОЙ строки: раньше единственная кнопка сбрасывала весь список.
		var one: PixelButton = PixelButton.new()
		one.setup("SET_RESET_ROW", PixelButton.Variant.GHOST)
		one.tooltip_text = "SET_RESET_ROW_TIP"
		one.pressed.connect(func() -> void:
			Settings.reset_action(action)
			_refresh_bindings())
		row.add_child(one)

	var reset: PixelButton = PixelButton.new()
	reset.setup("SET_RESET_KEYS", PixelButton.Variant.GHOST)
	reset.pressed.connect(func() -> void:
		Settings.reset_bindings()
		_refresh_bindings())
	box.add_child(reset)
	_capture_note = Label.new()
	_capture_note.theme_type_variation = &"LabelSmall"
	UILayout.wrap(_capture_note, 520.0)
	_capture_note.visible = false
	box.add_child(_capture_note)
	_refresh_bindings()
	return box.get_parent() as Control

## Список геймпадов. Пусто — честная строка «геймпад не найден», а не пустое
## место: игрок должен видеть разницу между «не поддерживаем» и «не вижу».
func _refresh_pads() -> void:
	if _pads_label == null:
		return
	var names: PackedStringArray = []
	for device: int in Input.get_connected_joypads():
		names.append("%d: %s" % [device, Input.get_joy_name(device)])
	_pads_label.text = tr("SET_PADS_NONE") if names.is_empty() \
		else "%s %s" % [tr("SET_PADS"), ", ".join(names)]

## Ждём следующего нажатия — и принимаем только событие ТОГО устройства, чей
## слот правим: кнопка геймпада не должна попадать в клавиатурный слот.
func _start_capture(action: String, slot: int) -> void:
	_capturing = action
	_capture_slot = slot
	_capture_note.visible = true
	_capture_note.text = tr("SET_PRESS_KEY_PAD" if slot == int(InputBindings.Slot.PAD)
		else "SET_PRESS_KEY")

func _unhandled_input(event: InputEvent) -> void:
	if _capturing.is_empty() or not visible:
		return
	# Esc и «назад» на геймпаде отменяют захват, а не назначаются на действие:
	# без выхода игрок был обязан назначить хоть что-то (аудит B5). Это же и
	# защита от «запереть себя»: выход в меню занять нечем.
	if event.is_action_pressed("ui_cancel"):
		_cancel_capture()
		get_viewport().set_input_as_handled()
		return
	var key: InputEventKey = event as InputEventKey
	var pad: InputEventJoypadButton = event as InputEventJoypadButton
	var want_pad: bool = _capture_slot == int(InputBindings.Slot.PAD)
	var event_ok: bool = (pad != null and pad.pressed) if want_pad \
		else (key != null and key.pressed)
	if not event_ok:
		return
	get_viewport().set_input_as_handled()
	# Служебную кнопку занимать нельзя: без «принять» и «отмена» игрок остаётся
	# без навигации по меню. Своё умолчание вернуть можно всегда.
	if Settings.is_reserved_event(_capturing, event):
		_capture_note.text = tr("SET_KEY_RESERVED")
		return
	if not Settings.set_slot(_capturing, _capture_slot, event):
		_capture_note.text = tr("SET_KEY_REFUSED")
		return
	_capturing = ""
	_capture_note.visible = false
	_refresh_bindings()

func _cancel_capture() -> void:
	_capturing = ""
	_capture_note.visible = false
	_refresh_bindings()

## Конфликт видно сразу: две одинаковые клавиши краснеют обе.
func _refresh_bindings() -> void:
	var bad: Dictionary = Settings.conflicts()
	for action: String in _bind_rows:
		var buttons: Array = _bind_rows[action]
		for slot: int in buttons.size():
			var button: PixelButton = buttons[slot] as PixelButton
			button.text = InputBindings.slot_label(action, slot)
			button.variant = PixelButton.Variant.DANGER if bad.has(action) \
				else PixelButton.Variant.NORMAL
	if _preset_pick != null:
		_preset_pick.selected = Settings.current_preset()

func _build_access_tab() -> Control:
	var box: VBoxContainer = _tab("Access")
	var note: Label = Label.new()
	UILayout.wrap(note, 520.0)
	note.text = "SET_ACCESS_NOTE"
	box.add_child(note)
	# Кегль, пресет для дальтоников и контраст пересобирают тему — эффект виден
	# сразу, а не после смены языка или перезапуска (docs/03 §3.6, аудит B2.8).
	_row(box, "SET_FONT_SCALE", _slider(Settings.font_scale, 0.75, 2.0, 0.25,
		func(v: float) -> void:
			Settings.font_scale = v
			Settings.apply_accessibility()), "SET_FONT_SCALE_HINT")
	_row(box, "SET_COLORBLIND", _options(["CB_NONE", "CB_PROTAN", "CB_DEUTER",
		"CB_TRITAN"], int(Settings.colorblind), func(i: int) -> void:
			Settings.colorblind = i as Settings.Colorblind
			Settings.apply_accessibility()), "SET_COLORBLIND_HINT")
	_row(box, "SET_REDUCE_MOTION", _check(Settings.reduce_motion,
		func(on: bool) -> void:
			Settings.reduce_motion = on
			Settings.mark_dirty()), "SET_REDUCE_MOTION_HINT")
	_row(box, "SET_CONTRAST", _check(Settings.high_contrast, func(on: bool) -> void:
		Settings.high_contrast = on
		Settings.apply_accessibility()), "SET_CONTRAST_HINT")
	_row(box, "SET_TOAST_TIME", _slider(Settings.toast_seconds, 0.0, 15.0, 1.0,
		func(v: float) -> void:
			Settings.toast_seconds = v
			Settings.mark_dirty()), "SET_TOAST_TIME_HINT")
	_row(box, "SET_SCREEN_READER", _check(Settings.screen_reader,
		func(on: bool) -> void:
			Settings.screen_reader = on
			Settings.mark_dirty()), "SET_SCREEN_READER_HINT")
	return box.get_parent() as Control

# --- Сброс профиля --------------------------------------------------------

## Необратимо — поэтому со словом подтверждения (docs/03 §4.4).
func _ask_reset() -> void:
	_confirm.setup("SET_RESET_PROFILE", "SET_RESET_BODY", "SET_RESET_PROFILE",
		true, tr("SET_RESET_WORD"))
	_confirm.open()

func _on_reset_confirmed() -> void:
	# ⚠️ Чистим и файл, и состояние в памяти: иначе первый же автосейв
	# запишет профиль обратно (research/22 §4).
	Meta.wipe()
	profile_reset.emit()

func _refresh_tab_titles() -> void:
	for i: int in _tab_keys.size():
		_tabs.set_tab_title(i, tr(_tab_keys[i]))

func _refresh_texts() -> void:
	super()
	if _tabs == null:
		return
	_refresh_tab_titles()
	# Пункты OptionButton переведены в момент создания: при смене языка вкладки
	# пересобираются целиком — это дешевле, чем хранить ссылку на каждый пункт.
	if visible:
		_rebuild_tabs()

func _rebuild_tabs() -> void:
	var page: int = _tabs.current_tab
	for c: Node in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	_tabs.add_child(_build_game_tab())
	_tabs.add_child(_build_screen_tab())
	_tabs.add_child(_build_sound_tab())
	_tabs.add_child(_build_input_tab())
	_tabs.add_child(_build_access_tab())
	_refresh_tab_titles()
	_tabs.current_tab = page
