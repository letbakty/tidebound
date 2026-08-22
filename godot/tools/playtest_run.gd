extends RefCounted
## Прогон НАСТОЯЩЕЙ игры headless: грузит res://game/main.tscn со всеми
## автолоадами и проходит её как игрок — заставка, меню, забег, модалки, меню.
##
## Зачем отдельно от tests/: сьюты собирают виджеты поштучно и в дереве игры
## их не видят. Пять блокеров аудита (`audit/01-minuses.md` §B1) были зелёными
## во всех 12 тысячах проверок — чёрный экран на старте, зависание на пятом
## тосте, проглоченный итог цикла. Ловится только запуском.
##
##   tools/playtest.sh            # обычный запуск (профиль и настройки на месте)
##   tools/playtest.sh fresh      # первый запуск: настройки убираются в .bak
##   tools/playtest.sh full       # + весь забег до Итога забега
##
## ⚠️ res://tools/* вырезается экспорт-пресетами — в релиз это не уедет.

const MAIN_SCENE: String = "res://game/main.tscn"
## Потолок ожидания любого шага, кадров. 60 кадров ≈ секунда.
const WAIT_FRAMES: int = 240
## Размер куска промотки. Не мельче, чем нужно: каждый debug_fast_forward
## заканчивается rebroadcast_state(), а это переэмиссия всего состояния мира —
## именно она, а не сами тики, и стоит времени в полном забеге.
const FF_CHUNK: int = 250
## Потолок промотки одного цикла, кусков (цикл — 3000 тиков).
const FF_CHUNKS_PER_CYCLE: int = 24

var _fails: PackedStringArray = []
var _steps: int = 0
var _main: Control = null
var _router: ScreenRouter = null
var _hud: Hud = null
var _fresh: bool = false
var _full: bool = false

## Дерево передаёт лаунчер: сам раннер — не MainLoop, а обычный объект.
var _tree: SceneTree = null

func start(tree: SceneTree) -> void:
	_tree = tree
	ErrorGuard.reset()
	ErrorGuard.install()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_fresh = args.has("fresh")
	_full = args.has("full")
	_drive()

# --- Сценарий -------------------------------------------------------------

func _drive() -> void:
	await _tree.process_frame
	_tree.change_scene_to_file(MAIN_SCENE)
	await _tree.process_frame
	await _tree.process_frame
	_main = _tree.current_scene as Control
	if _main == null:
		_fail("сцена игры не загрузилась")
		_finish()
		return
	_router = _main.get("router") as ScreenRouter
	_hud = _main.get("hud") as Hud
	if _router == null or _hud == null:
		_fail("Main без router/hud — сцена собралась не до конца")
		_finish()
		return

	await _step_boot()
	await _step_menu_to_game()
	await _step_start_draft()
	await _step_toast_storm()
	await _step_cycle_and_draft()
	await _step_menus_freeze_world()
	await _step_gauge_legend()
	await _step_wheel_zoom()
	await _step_accessibility_now()
	await _step_save_keeps_ui()
	await _step_panels_and_radial()
	if _full:
		await _step_full_run()
	_finish()

## 1.2 — чёрный экран: goto(BOOT) при current == BOOT выходил «уже там»,
## on_enter не звался, полоса не двигалась, finished не эмитился.
func _step_boot() -> void:
	_step("заставка уходит сама")
	var boot: ScreenBase = _router.screen_node(ScreenRouter.Screen.BOOT)
	_check(boot != null and boot.visible, "BootScreen показан в первом кадре")
	var ok: bool = await _wait(func() -> bool:
		return _router.current != ScreenRouter.Screen.BOOT)
	if not _check(ok, "заставка сменилась экраном за %d кадров" % WAIT_FRAMES):
		return
	# 1.3 — FirstLaunch недостижим: Settings писал файл в первом же кадре, и
	# has_file() к концу заставки отвечал «да» на любом запуске.
	# settings.json прячет tools/playtest.sh — запуск ВСЕГДА первый.
	if not _check(_router.current == ScreenRouter.Screen.FIRST_LAUNCH,
			"первый запуск ведёт на выбор языка (сейчас %d)" % int(_router.current)):
		return
	var first: FirstLaunch = _router.screen_node(
		ScreenRouter.Screen.FIRST_LAUNCH) as FirstLaunch
	first.done.emit(false)
	await _tree.process_frame
	_check(_router.current == ScreenRouter.Screen.MAIN_MENU,
		"игрок в главном меню (сейчас %d)" % int(_router.current))

func _step_menu_to_game() -> void:
	_step("новый забег из меню")
	var menu: MainMenu = _router.screen_node(ScreenRouter.Screen.MAIN_MENU) as MainMenu
	if not _check(menu != null, "главное меню зарегистрировано"):
		return
	menu.new_run_requested.emit(20260822)
	await _tree.process_frame
	_check(_router.current == ScreenRouter.Screen.GAME, "экран игры открыт")
	_check(Game.world != null, "мир создан")
	var hud_layer: CanvasLayer = _main.get("hud_layer") as CanvasLayer
	_check(hud_layer.visible and _hud.is_visible_in_tree(), "HUD виден в игре")

## Первый Спад отдаёт драфт ещё до того, как игрок увидел экран игры: раньше
## это окно молча терялось (гейт «не в GAME») и карту за игрока брал
## auto_pick_if_needed. Теперь оно ждёт в очереди роутера (docs/03 §2, §8).
func _step_start_draft() -> void:
	_step("стартовый драфт")
	var came: bool = await _wait(func() -> bool:
		return _router.modal == ScreenRouter.Modal.DRAFT)
	if not _check(came,
			"драфт первого цикла показан (modal=%d)" % int(_router.modal)):
		return
	_check(Game.speed == 0, "и держит автопаузу (speed=%d)" % Game.speed)
	await _pick_card()
	_check(_router.modal == ScreenRouter.Modal.NONE, "после выбора окно закрылось")
	_check(Game.pause_depth() == 0,
		"счётчик автопаузы обнулился (сейчас %d)" % Game.pause_depth())
	_check(Game.speed > 0, "забег пошёл (speed=%d)" % Game.speed)

## 1.1 — зависание на пятом тосте: queue_free не убирает ноду из дерева
## до конца кадра, и `while get_child_count() > MAX` крутился вечно.
## Если фикса нет — прогон не падает, а ВИСНЕТ: ловит внешний таймаут.
func _step_toast_storm() -> void:
	_step("шторм из шести тостов")
	for i: int in 6:
		_hud.notices.push(NoticeQueue.Kind.TOAST, {
			"type": "storm_%d" % i, "text": "тост %d" % i,
			"tone": Toast.Tone.WARN, "cell": Vector2i.ZERO, "life": -1.0})
	await _tree.process_frame
	var box: Node = _hud.toasts.get_node_or_null(^"Box")
	if not _check(box != null, "стек тостов собран"):
		return
	_check(box.get_child_count() <= ToastStack.MAX_VISIBLE,
		"на экране не больше %d тостов (сейчас %d)"
		% [ToastStack.MAX_VISIBLE, box.get_child_count()])

## 1.4 — итог цикла проглатывался драфтом: cycle_ended и draft_ready приходят
## одним батчем, open_modal(DRAFT) молча закрывал Итог, его «Дальше» никто не
## нажимал, и автопауза оставалась висеть навсегда.
func _step_cycle_and_draft() -> void:
	_step("конец цикла: Итог, затем драфт")
	var seen: bool = await _run_until_modal()
	if not _check(seen, "модальное окно на границе цикла появилось"):
		return
	if not _check(_router.modal == ScreenRouter.Modal.CYCLE_SUMMARY,
			"первым показан Итог цикла (сейчас modal=%d)" % int(_router.modal)):
		return
	_check(Game.speed == 0, "автопауза Итога стоит")
	var cycle: CycleSummary = _router.modal_node(ScreenRouter.Modal.CYCLE_SUMMARY) as CycleSummary
	cycle.closed.emit()                     # «Дальше»
	await _tree.process_frame
	if not _check(_router.modal == ScreenRouter.Modal.DRAFT,
			"после Итога открылся драфт (сейчас modal=%d)" % int(_router.modal)):
		return
	_check(Game.speed == 0, "автопауза драфта держит игру")
	if not _check(await _pick_card(), "карты драфта есть"):
		return
	_check(_router.modal == ScreenRouter.Modal.NONE, "после выбора модалок нет")
	_check(Game.pause_depth() == 0,
		"счётчик автопаузы обнулился (сейчас %d)" % Game.pause_depth())
	_check(Game.speed > 0,
		"игра пошла дальше после драфта (speed=%d)" % Game.speed)

## 1.5 — симуляция жила под меню и настройками: мир скрыт, но тикал, автосейв
## переписывал сейв, а клавиши скрытого HUD продолжали командовать симом.
func _step_menus_freeze_world() -> void:
	_step("мир под экраном не живёт")
	Game.cmd_set_speed(3)
	_router.open_modal(ScreenRouter.Modal.PAUSE, {}, true)
	await _tree.process_frame
	_check(Game.speed == 0, "окно паузы остановило игру")
	var pause: PausePanel = _router.modal_node(ScreenRouter.Modal.PAUSE) as PausePanel
	pause.settings_requested.emit()
	await _tree.process_frame
	_check(_router.current == ScreenRouter.Screen.SETTINGS, "настройки открылись")
	_check(Game.world_hidden, "под настройками мир выключен")
	var tick_before: int = Game.world.clock.total_ticks()
	for i: int in 30:
		await _tree.process_frame
	_check(Game.world.clock.total_ticks() == tick_before,
		"мир под настройками не натикал (%d -> %d)"
		% [tick_before, Game.world.clock.total_ticks()])

	# Скрытый HUD не должен ловить клавиши: Space = Отзыв, 1/2/3 = скорость.
	var recalls: Array[bool] = []
	var on_recall: Callable = func(hard: bool) -> void: recalls.append(hard)
	Events.recall_issued.connect(on_recall)
	_send_action("recall")
	_send_action("speed_3")
	await _tree.process_frame
	await _tree.process_frame
	Events.recall_issued.disconnect(on_recall)
	_check(recalls.is_empty(), "Space под настройками не отзывает людей")
	_check(Game.world_hidden, "клавиша скорости под настройками не будит мир")

	var settings: SettingsScreen = _router.screen_node(ScreenRouter.Screen.SETTINGS) as SettingsScreen
	settings.back_requested.emit()
	await _tree.process_frame
	_check(_router.current == ScreenRouter.Screen.GAME, "вернулись в игру")
	_check(_router.modal == ScreenRouter.Modal.PAUSE, "и снова в окне паузы")
	pause.resume_requested.emit()
	await _tree.process_frame
	_check(Game.speed > 0, "«Продолжить» вернуло скорость (speed=%d)" % Game.speed)

## Полный забег до Итога забега: каждая граница цикла обслуживается как
## игроком. Проверяет, что цикл «конец цикла -> драфт -> игра» замыкается
## двенадцать раз подряд, а не один.
func _step_full_run() -> void:
	_step("весь забег до Итога забега")
	var cycles: int = 0
	for i: int in Balance.CYCLES_PER_RUN + 2:
		if Game.world == null or Game.world.run_state.finished:
			break
		var seen: bool = await _run_until_modal()
		if not seen:
			_fail("цикл %d: граница не наступила за отведённые тики" % (i + 1))
			return
		if _router.modal == ScreenRouter.Modal.RUN_SUMMARY:
			break
		await _close_modals()
		cycles += 1
		if not _check(Game.speed > 0,
				"цикл %d: игра пошла дальше (speed=%d, автопауз %d, банер %s)"
				% [cycles, Game.speed, Game.pause_depth(),
					"открыт" if _hud.banner.visible else "нет"]):
			return
	_check(_router.modal == ScreenRouter.Modal.RUN_SUMMARY,
		"забег закончился Итогом забега (modal=%d)" % int(_router.modal))
	_check(cycles >= 2, "пройдено не меньше двух полных циклов (пройдено %d)" % cycles)
	var run: RunSummary = _router.modal_node(ScreenRouter.Modal.RUN_SUMMARY) as RunSummary
	run.journal_requested.emit()
	await _tree.process_frame
	_check(_router.current == ScreenRouter.Screen.JOURNAL, "из итога — в Журнал")
	var journal: ScreenBase = _router.screen_node(ScreenRouter.Screen.JOURNAL)
	journal.back_requested.emit()
	await _tree.process_frame
	_check(_router.current == ScreenRouter.Screen.MAIN_MENU, "и обратно в меню")

## B2.10 · «Тап по шкале — тултип-легенда» (docs/01 §2) не был реализован:
## обработчик только закрывал панели, а мышь шкала не слушала вовсе.
func _step_gauge_legend() -> void:
	_step("легенда шкалы прилива")
	var legend: Control = _hud.get_node_or_null(^"TideLegend") as Control
	if not _check(legend != null, "легенда собрана в HUD"):
		return
	_check(not legend.visible, "по умолчанию скрыта")
	_hud.tide_gauge.legend_requested.emit()
	await _tree.process_frame
	_check(legend.visible, "тап по шкале открыл легенду")
	_hud.tide_gauge.legend_requested.emit()
	await _tree.process_frame
	_check(not legend.visible, "повторный тап закрыл — это тумблер")

## B2.7 · колесо ловили и InputService, и CameraRig: один щелчок давал две
## ступени зума вместо одной.
func _step_wheel_zoom() -> void:
	_step("колесо даёт одну ступень зума")
	var camera: CameraRig = (_main.get("world_view") as Node).get("camera") as CameraRig
	if not _check(camera != null, "камера мира на месте"):
		return
	camera.set_zoom_step(3)
	await _tree.process_frame
	var before: int = camera.zoom_factor()
	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await _tree.process_frame
	await _tree.process_frame
	_check_eq(camera.zoom_factor(), before - 1,
		"один щелчок колеса — одна ступень (было ×%d)" % before)
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	await _tree.process_frame
	await _tree.process_frame
	_check_eq(camera.zoom_factor(), before, "обратно тоже на одну")

## B2.8 · кегль и пресет для дальтоников применялись только после смены языка
## или перезапуска (docs/03 §3.6).
func _step_accessibility_now() -> void:
	_step("доступность применяется сразу")
	var before: float = UIThemeFactory.font_scale
	var theme_before: Theme = _hud.theme
	var fired: Array[bool] = []
	var on_theme: Callable = func() -> void: fired.append(true)
	Settings.theme_changed.connect(on_theme)
	Settings.font_scale = before + 0.25
	Settings.apply_accessibility()
	await _tree.process_frame
	Settings.theme_changed.disconnect(on_theme)
	_check(not fired.is_empty(), "тема пересобрана без перезапуска")
	_check_eq_f(UIThemeFactory.font_scale, before + 0.25, "кегль темы поехал за настройкой")
	_check(_hud.theme != theme_before, "HUD получил новую тему")
	Settings.font_scale = before
	Settings.apply_accessibility()
	await _tree.process_frame

## B2.6 · ui-секция сейва терялась: аварийный сейв писал её пустой, а загрузка
## не читала вовсе — после «Продолжить» банеры кризисов снова были первыми и
## снова ставили автопаузу.
func _step_save_keeps_ui() -> void:
	_step("секция интерфейса переживает «Продолжить»")
	var kind: int = int(SimTypes.CrisisType.STORM)
	_check(Game.note_banner(kind), "банер шторма показан впервые")
	_check(not Game.note_banner(kind), "второй раз — уже не первый")
	Game.cmd_save()
	_check(Game.has_save(), "забег сохранён")
	var menu: MainMenu = _router.screen_node(ScreenRouter.Screen.MAIN_MENU) as MainMenu
	_router.goto(ScreenRouter.Screen.MAIN_MENU)
	await _tree.process_frame
	menu.continue_requested.emit()
	await _tree.process_frame
	if not _check(_router.current == ScreenRouter.Screen.GAME, "забег продолжен"):
		return
	_check(not Game.note_banner(kind),
		"после загрузки банер шторма всё ещё не первый")

## Панель — не модальное окно: мир под ней ВИДЕН и ИДЁТ (docs/03 §1).
## Радиал стройки на ПК должен подсвечивать слот под курсором, а отмена —
## возвращать фокус тому, у кого он был (аудит B4).
func _step_panels_and_radial() -> void:
	_step("панели и радиал стройки")
	var panels: PanelHost = _main.get("panels") as PanelHost
	Game.cmd_set_speed(1)
	panels.open("policies")
	await _tree.process_frame
	_check(panels.is_open("policies"), "панель политик открыта")
	_check(Game.speed > 0, "мир под панелью идёт (speed=%d)" % Game.speed)
	_check(_router.modal == ScreenRouter.Modal.NONE, "панель — не модальное окно")
	panels.close()
	await _tree.process_frame
	_check(not panels.is_open(), "панель закрылась")

	var radial: BuildRadial = _main.get("build_radial") as BuildRadial
	if not _check(radial != null, "радиал стройки собран"):
		return
	var at: Vector2 = _tree.root.get_visible_rect().size * 0.5
	radial.open_at(at, Vector2.ZERO, false)
	await _tree.process_frame
	var menu: RadialMenu = radial.get("_radial") as RadialMenu
	if not _check(menu != null and menu.is_open(), "радиал открылся"):
		return
	var slot: Vector2 = menu.call("_slot_center", 0) as Vector2
	var move: InputEventMouseMotion = InputEventMouseMotion.new()
	move.position = slot
	menu._gui_input(move)
	_check(int(menu.get("_hover")) == 0, "мышь подсвечивает слот под курсором")
	menu.close()
	await _tree.process_frame
	_check(not menu.is_open(), "радиал закрылся")

## Крутит симуляцию кусками, пока не откроется модальное окно. Куски мелкие:
## между ними проверяется состояние роутера.
func _run_until_modal() -> bool:
	for i: int in FF_CHUNKS_PER_CYCLE:
		if _router.is_modal_open():
			return true
		Game.debug_fast_forward(FF_CHUNK)
		await _tree.process_frame
		await _dismiss_banner()
		if _router.is_modal_open():
			return true
	return false

## Банер ПЕРВОГО кризиса ставит автопаузу и держит её, пока игрок его не
## закроет (промпт 13 п.5). Прогон обязан вести себя как игрок, иначе забег
## встанет на первом же шторме — и это будет дефект прогона, а не игры.
func _dismiss_banner() -> void:
	if _hud.banner == null or not _hud.banner.visible:
		return
	_hud.banner.dismissed.emit()
	await _tree.process_frame

## Закрывает всё, что открылось на границе цикла, как это сделал бы игрок.
func _close_modals() -> void:
	await _dismiss_banner()
	for i: int in 4:
		match _router.modal:
			ScreenRouter.Modal.CYCLE_SUMMARY:
				(_router.modal_node(ScreenRouter.Modal.CYCLE_SUMMARY) as CycleSummary).closed.emit()
			ScreenRouter.Modal.DRAFT:
				if not await _pick_card():
					_router.close_modal()
			ScreenRouter.Modal.RUN_SUMMARY:
				return
			_:
				return
		await _tree.process_frame

# --- Мелочи ---------------------------------------------------------------

## Выбор первой карты драфта — как игрок: тап по карте и «Взять».
func _pick_card() -> bool:
	var draft: DraftPanel = _router.modal_node(ScreenRouter.Modal.DRAFT) as DraftPanel
	var ids: Array[String] = Game.world.run_state.draft.duplicate()
	if ids.is_empty():
		return false
	draft.card_confirmed.emit(ids[0])
	await _tree.process_frame
	return true

func _wheel(button: int) -> void:
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = button
	ev.position = _tree.root.get_visible_rect().size * 0.5
	ev.pressed = true
	Input.parse_input_event(ev)

func _check_eq(got: int, want: int, msg: String) -> void:
	_check(got == want, "%s — получили %d, ждали %d" % [msg, got, want])

func _check_eq_f(got: float, want: float, msg: String) -> void:
	_check(is_equal_approx(got, want), "%s — получили %.2f, ждали %.2f" % [msg, got, want])

func _send_action(action: String) -> void:
	var ev: InputEventAction = InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)

func _wait(cond: Callable) -> bool:
	for i: int in WAIT_FRAMES:
		if bool(cond.call()):
			return true
		await _tree.process_frame
	return false

## Всё пишем в stderr: stdout при перенаправлении в файл буферизуется, и на
## ЗАВИСАНИИ (а половина дефектов UI — именно оно) лог теряется целиком.
func _say(line: String) -> void:
	printerr(line)

func _step(title: String) -> void:
	_steps += 1
	_say("\n> %d. %s" % [_steps, title])

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
	_say("")
	var guard: String = ErrorGuard.report()
	if not guard.is_empty():
		_say(guard)
	if _fails.is_empty() and guard.is_empty():
		_say("PLAYTEST OK — шагов: %d, ошибок рантайма нет" % _steps)
		_tree.quit(0)
		return
	_say("PLAYTEST FAILED — провалов: %d" % _fails.size())
	for f: String in _fails:
		_say("   • " + f)
	_tree.quit(1)
