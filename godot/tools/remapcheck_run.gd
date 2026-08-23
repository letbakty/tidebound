extends RefCounted
## Ремап переживает ПЕРЕЗАПУСК ИГРЫ — проверка в два процесса.
##
## Зачем отдельно от tests/ и от playtest: путь «Settings._ready -> файл ->
## InputMap» проверяется только настоящим запуском. Сьюты зовут apply_bindings()
## руками, а playtest живёт в одном процессе. Ровно на этом стыке ремап и был
## сломан: файл читался в поле, а InputMap не трогал никто.
##
##   tools/remapcheck.sh          # назначить R -> перезапуск -> проверить
##
## ⚠️ res://tools/* вырезается экспорт-пресетами — в релиз это не уедет.

const MAIN_SCENE: String = "res://game/main.tscn"
const WAIT_FRAMES: int = 240
## На что переназначаем «Отзыв» в фазе set.
const NEW_KEY: Key = KEY_R

var _fails: PackedStringArray = []
var _tree: SceneTree = null
var _main: Control = null
var _router: ScreenRouter = null

func start(tree: SceneTree) -> void:
	_tree = tree
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_drive(args.has("verify"))

func _drive(verify: bool) -> void:
	await _tree.process_frame
	_tree.change_scene_to_file(MAIN_SCENE)
	await _tree.process_frame
	await _tree.process_frame
	_main = _tree.current_scene as Control
	_router = _main.get("router") as ScreenRouter if _main != null else null
	if _router == null:
		_fail("сцена игры не собралась")
		_finish()
		return
	await _leave_boot()
	if verify:
		await _step_verify()
	else:
		await _step_assign()
	_finish()

## Заставка и (на чистом профиле) выбор языка — как в playtest.
func _leave_boot() -> void:
	await _wait(func() -> bool: return _router.current != ScreenRouter.Screen.BOOT)
	if _router.current == ScreenRouter.Screen.FIRST_LAUNCH:
		var first: FirstLaunch = _router.screen_node(
			ScreenRouter.Screen.FIRST_LAUNCH) as FirstLaunch
		first.done.emit(false)
		await _tree.process_frame

# --- Фаза 1: назначаем -----------------------------------------------------

## Как игрок: открыть настройки, вкладку «Управление», нажать кнопку слота и
## нажать клавишу. Клик — настоящий мышью, клавиша — настоящее событие.
func _step_assign() -> void:
	_say("> назначаем «Отзыв» на %s" % OS.get_keycode_string(NEW_KEY))
	_router.open_settings_from(ScreenRouter.Screen.MAIN_MENU)
	await _tree.process_frame
	var screen: SettingsScreen = _router.screen_node(
		ScreenRouter.Screen.SETTINGS) as SettingsScreen
	if not _check(screen != null, "экран настроек на месте"):
		return
	var tabs: TabContainer = screen.get("_tabs") as TabContainer
	tabs.current_tab = 3                        # «Управление»
	await _tree.process_frame
	var rows: Dictionary = screen.get("_bind_rows") as Dictionary
	if not _check(rows.has("recall"), "строка «Отзыва» собрана"):
		return
	var slot: Control = (rows["recall"] as Array)[int(InputBindings.Slot.KEY_1)] as Control
	_click(slot.get_global_rect().get_center())
	await _tree.process_frame
	_check(str(screen.get("_capturing")) == "recall", "захват клавиши начался")
	_press_key(NEW_KEY)
	await _tree.process_frame
	await _tree.process_frame
	_check(InputMap.event_is_action(_key(NEW_KEY), "recall"),
		"клавиша назначилась прямо сейчас")
	# Файл пишется с дебаунсом в _process — здесь просим явно.
	Settings.save_settings()
	_check(Settings.has_file(), "настройки записаны на диск")
	_say("   bindings: %s" % JSON.stringify(Settings.bindings))

# --- Фаза 2: проверяем после перезапуска -----------------------------------

func _step_verify() -> void:
	_say("> тот же вопрос после перезапуска процесса")
	_check(InputMap.event_is_action(_key(NEW_KEY), "recall"),
		"%s отзывает людей" % OS.get_keycode_string(NEW_KEY))
	_check(not InputMap.event_is_action(_key(KEY_SPACE), "recall"),
		"прежний Space на «Отзыве» не остался")
	var pad: InputEventJoypadButton = InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_B
	pad.device = 1                              # намеренно НЕ нулевой геймпад
	_check(InputMap.event_is_action(pad, "recall"),
		"кнопка B живёт на «Отзыве» — и на геймпаде №1 тоже")
	# Полоса подсказок обязана показывать новую клавишу, а не старую.
	var hud: Hud = _main.get("hud") as Hud
	var rows: Node = hud.hints.get_node_or_null(^"Rows")
	var first: Label = rows.get_child(0) as Label if rows != null \
		and rows.get_child_count() > 0 else null
	if _check(first != null, "полоса подсказок собрана"):
		_say("   подсказка: «%s»" % first.text)
		_check(first.text.begins_with(OS.get_keycode_string(NEW_KEY)),
			"подсказка показывает новую клавишу, а не Space")
	# Возвращаем раскладку: файл прячет обёртка, но пусть и содержимое будет чистым.
	Settings.reset_bindings()
	Settings.save_settings()

# --- Синтетический ввод ----------------------------------------------------

## Событие мыши приходит в координатах ОКНА; корень пересчитывает его своим
## final_transform (в headless окно вырождено). Тот же хелпер, что и в
## tools/playtest_run.gd.
func _click(viewport_pos: Vector2) -> void:
	var at: Vector2 = _tree.root.get_final_transform() * viewport_pos
	for pressed: bool in [true, false]:
		var mb: InputEventMouseButton = InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.position = at
		mb.global_position = at
		mb.pressed = pressed
		Input.parse_input_event(mb)
	Input.flush_buffered_events()

func _press_key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var e: InputEventKey = InputEventKey.new()
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
	Input.flush_buffered_events()

func _key(code: Key) -> InputEventKey:
	var e: InputEventKey = InputEventKey.new()
	e.physical_keycode = code
	return e

# --- Мелочи ----------------------------------------------------------------

func _wait(cond: Callable) -> bool:
	for i: int in WAIT_FRAMES:
		if bool(cond.call()):
			return true
		await _tree.process_frame
	return false

func _say(line: String) -> void:
	printerr(line)

func _check(ok: bool, msg: String) -> bool:
	if ok:
		_say("   OK   " + msg)
	else:
		_fail(msg)
	return ok

func _fail(msg: String) -> void:
	_say("   FAIL " + msg)
	_fails.append(msg)

func _finish() -> void:
	if _fails.is_empty():
		_say("REMAPCHECK OK")
		_tree.quit(0)
		return
	_say("REMAPCHECK FAILED — провалов: %d" % _fails.size())
	_tree.quit(1)
