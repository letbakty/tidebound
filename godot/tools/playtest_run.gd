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
	await _step_mouse_reaches_game()
	await _step_mouse_buttons()
	await _step_mouse_build()
	await _step_mouse_radial_frees_hud()
	await _step_mouse_agent_card()
	await _step_input_tab()
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

# --- Мышь: настоящие клики по узлам ---------------------------------------
#
# ⚠️ Всё, что ниже, нажимает НАСТОЯЩЕЙ мышью: warp_mouse + InputEventMouse*
# через Input.parse_input_event. Остальной прогон дёргает signal.emit() — и
# именно поэтому 13 тысяч зелёных проверок ужились с игрой, в которой мышью
# не нажималась ни одна кнопка интерфейса, а клик по миру уезжал на 34 клетки
# от курсора. Проверять композицию сцены (mouse_filter соседних слоёв,
# конверсию координат, кто под курсором) можно только так.

## Долгое нажатие копит время в _process InputService: кадров нужно заметно
## больше обычного потолка, зато выходим по первому же признаку радиала.
const HOLD_FRAMES: int = 600
## Допуск круговой проверки координат — половина тайла (docs/01 §1.1).
const COORD_EPS_PX: float = 16.0

## Кто под курсором в середине окна. Одна строка, которая ловит весь класс
## «невидимый полноэкранный Control поверх игры» навсегда: каркас пустого
## GameScreen лежал на слое 40 и съедал клики у HUD, панелей и банеров.
func _step_mouse_reaches_game() -> void:
	_step("мышь достаёт до игры, а не до каркаса экрана")
	if not await _ensure_plain_game():
		return
	var center: Vector2 = _view_size() * 0.5
	await _move_mouse(center)
	var hovered: Control = _tree.root.gui_get_hovered_control()
	var who: String = str(hovered.get_path()) if hovered != null else "<никто>"
	_check(hovered == null or not _router.is_ancestor_of(hovered),
		"под курсором в середине окна не каркас экрана (%s)" % who)

	# Круговая проверка координат: мир -> вьюпорт -> экран -> обратно.
	# Дефект «клик уезжает на 34 клетки» фиксируется здесь числом.
	var id: int = _live_agent()
	if not _check(id >= 0, "в колонии есть живой колонист"):
		return
	var world_pos: Vector2 = Game.query_agent_pos(id)
	var camera: CameraRig = (_main.get("world_view") as Node).get("camera") as CameraRig
	camera.focus_on(world_pos, false)
	await _tree.process_frame
	var on_screen: Vector2 = _main.call("_world_to_screen", world_pos) as Vector2
	var back: Vector2 = _main.call("_screen_to_world", on_screen) as Vector2
	_check(back.distance_to(world_pos) <= COORD_EPS_PX,
		"экран↔мир сходится: агент в %s, обратно %s (расхождение %.1f px)"
		% [str(world_pos.round()), str(back.round()), back.distance_to(world_pos)])
	# И то же самое от середины окна: там ошибка умножения была максимальной.
	var mid_world: Vector2 = _main.call("_screen_to_world", center) as Vector2
	_check(mid_world.distance_to(camera.global_position) <= COORD_EPS_PX,
		"клик в центр окна попадает туда, куда смотрит камера (%s против %s)"
		% [str(mid_world.round()), str(camera.global_position.round())])

## Три настоящие кнопки. Кликаем по ЖИВОЙ кнопке, а не по её обёртке:
## у «Отзыва» это Box/Button, обёртка вокруг него 176×176 и IGNORE.
func _step_mouse_buttons() -> void:
	_step("кнопки интерфейса нажимаются мышью")
	if not await _ensure_plain_game():
		return
	Game.cmd_set_speed(1)                   # команда доедет до sim только тиком
	var recalls: Array[bool] = []
	var on_recall: Callable = func(hard: bool) -> void: recalls.append(hard)
	Events.recall_issued.connect(on_recall)
	var button: Control = _hud.recall.get_node_or_null(^"Box/Button") as Control
	if _check(button != null and button.is_visible_in_tree(), "кнопка «Отзыв» на месте"):
		await _click_at(button.get_global_rect().get_center())
		var fired: bool = await _wait(func() -> bool: return not recalls.is_empty())
		_check(fired, "клик по «Отзыву» отзывает людей")
	Events.recall_issued.disconnect(on_recall)

	Game.cmd_set_speed(2)
	await _tree.process_frame
	var pause: Control = _hud.top_bar.get_node_or_null(^"Row/Speed0") as Control
	if _check(pause != null, "кнопка паузы в верхней строке на месте"):
		await _click_at(pause.get_global_rect().get_center())
		_check(Game.speed == 0, "клик по ⏸ ставит игру на паузу (speed=%d)" % Game.speed)
	var play: Control = _hud.top_bar.get_node_or_null(^"Row/Speed1") as Control
	if _check(play != null, "кнопка ×1 на месте"):
		await _click_at(play.get_global_rect().get_center())
		_check(Game.speed == 1, "клик по ×1 снимает паузу (speed=%d)" % Game.speed)

## Сквозной сценарий стройки ОДНОЙ мышью — единственная проверка, которая
## доказывает, что игра играбельна мышью: удержание ПКМ -> слот радиала ->
## наведение на клетку -> клик. Без неё остальные проверки снова разъедутся.
func _step_mouse_build() -> void:
	_step("постройка ставится одной мышью")
	if not await _ensure_plain_game():
		return
	var ids: Array[String] = Game.query_unlocked_buildings()
	if not _check(not ids.is_empty(), "есть что строить"):
		return
	var def_id: String = ids[0]
	var spot: Dictionary = _find_spot(def_id)
	if not _check(not spot.is_empty(),
			"нашлась валидная клетка для «%s» в видимой части мира" % def_id):
		return

	# 1. Удержание ПКМ по миру открывает радиал (docs/00 §13).
	var radial: BuildRadial = _main.get("build_radial") as BuildRadial
	await _hold_rmb(_view_size() * 0.5)
	if not _check(radial.is_open(), "удержание ПКМ открыло радиал стройки"):
		return
	# 2. Клик по слоту радиала выбирает постройку.
	var menu: RadialMenu = radial.get("_radial") as RadialMenu
	await _click_at(menu.call("_slot_center", 0) as Vector2)
	var ghost: BuildGhost = (_main.get("world_view") as Node).get("ghost") as BuildGhost
	if not _check(not ghost.def_id.is_empty(),
			"слот радиала выбран мышью (призрак: «%s»)" % ghost.def_id):
		return
	# 3. Призрак обязан идти ЗА КУРСОРОМ, а не стоять там, где открыли радиал.
	var cell: Vector2i = spot["cell"] as Vector2i
	await _move_mouse(spot["screen"] as Vector2)
	await _tree.process_frame
	_check(ghost.current_cell() == cell,
		"призрак под курсором: ждали клетку %s, он в %s"
		% [str(cell), str(ghost.current_cell())])
	_check(ghost.error_key().is_empty(),
		"призрак показывает клетку валидной («%s»)" % ghost.error_key())
	# 4. Клик по НЕвалидной клетке призрак не снимает: игрок видит причину и
	# пробует соседнюю, а не открывает радиал заново тремя действиями.
	var bad: Dictionary = _find_spot(def_id, false)
	if _check(not bad.is_empty(), "нашлась заведомо невалидная видимая клетка"):
		await _click_at(bad["screen"] as Vector2)
		await _tree.process_frame
		_check(not ghost.def_id.is_empty(), "отказ не снял призрак")
		_check(not ghost.error_key().is_empty(),
			"и причина отказа показана («%s»)" % ghost.error_key())
	# 5. Клик ставит постройку — именно туда, где показана валидность.
	await _move_mouse(spot["screen"] as Vector2)
	var before: int = Game.world.buildings.buildings.size()
	Game.cmd_set_speed(1)                   # команда доедет до sim только тиком
	await _click_at(spot["screen"] as Vector2)
	var built: bool = await _wait(func() -> bool:
		return Game.world.buildings.buildings.size() > before)
	_check(built, "клик поставил постройку (было %d, стало %d)"
		% [before, Game.world.buildings.buildings.size()])
	_check(ghost.def_id.is_empty(), "после удачной постановки призрак снят")
	_check(Game.world.buildings.building_at(cell) >= 0,
		"постройка встала именно в клетку %s, которую подсвечивал призрак" % str(cell))

	# 6. Отмена размещения: правый клик и Esc. Ставит призрак сюда код — под
	# проверкой сама отмена, а не повторный проход по радиалу.
	ghost.set_def(def_id)
	ghost.follow_mouse()
	await _tree.process_frame
	_mouse_button(MOUSE_BUTTON_RIGHT, spot["screen"] as Vector2, true)
	_mouse_button(MOUSE_BUTTON_RIGHT, spot["screen"] as Vector2, false)
	await _tree.process_frame
	_check(ghost.def_id.is_empty(), "правый клик снимает призрак")
	ghost.set_def(def_id)
	await _tree.process_frame
	_send_action("pause_menu")
	await _tree.process_frame
	_check(ghost.def_id.is_empty(), "Esc тоже снимает призрак")
	_check(not _router.is_modal_open(),
		"и не открывает при этом окно паузы: сначала отмена начатого")

## Открытый радиал не имеет права блокировать HUD: перехват у него только в
## круге, а клик мимо — закрывает его и доходит до кнопки под курсором
## (docs/01 §3). Полноэкранный STOP держал «Отзыв» и паузу мёртвыми.
func _step_mouse_radial_frees_hud() -> void:
	_step("радиал не держит HUD в заложниках")
	if not await _ensure_plain_game():
		return
	var radial: BuildRadial = _main.get("build_radial") as BuildRadial
	await _hold_rmb(_view_size() * 0.5)
	if not _check(radial.is_open(), "радиал открыт удержанием ПКМ"):
		return
	Game.cmd_set_speed(2)
	await _tree.process_frame
	var pause: Control = _hud.top_bar.get_node_or_null(^"Row/Speed0") as Control
	await _click_at(pause.get_global_rect().get_center())
	_check(not radial.is_open(), "клик мимо круга закрыл радиал")
	_check(Game.speed == 0,
		"и тем же кликом нажалась кнопка HUD под ним (speed=%d)" % Game.speed)
	var ghost: BuildGhost = (_main.get("world_view") as Node).get("ghost") as BuildGhost
	_check(ghost.def_id.is_empty(), "постройка при этом не выбралась")
	Game.cmd_set_speed(1)

## Карточка агента открывается кликом по колонисту и закрывается крестиком —
## и ни одна панель не смеет накрыть «Отзыв» (docs/01 §2).
func _step_mouse_agent_card() -> void:
	_step("карточка колониста: открыть и закрыть мышью")
	if not await _ensure_plain_game():
		return
	# Пауза обязательна: колонист ходит, и за те кадры, что идут между
	# наведением и отпусканием кнопки, он уходит из-под курсора. Тактическая
	# пауза — штатный режим игры (docs/01 §2), а не поблажка прогону.
	Game.cmd_set_speed(0)
	await _tree.process_frame
	var at: Vector2 = await _aim_at_agent()
	if not _check(at != Vector2.INF, "нашёлся колонист, видимый в стороне от HUD"):
		return
	var panels: PanelHost = _main.get("panels") as PanelHost
	await _click_at(at)
	await _tree.process_frame
	if not _check(panels.is_open("agent"),
			"клик по колонисту открыл его карточку (открыто: «%s»)" % panels.current()):
		return
	_check_free_recall("AgentCard", panels.current())
	var card: Control = _panel_node(panels, "agent")
	var close: Control = card.get_node_or_null(^"Box/Header/Close") as Control
	if _check(close != null, "крестик карточки на месте"):
		await _click_at(close.get_global_rect().get_center())
		_check(not panels.is_open(), "крестик закрыл карточку")

	# Остальные панели проверяем на ту же мёртвую зону: попап поверх кнопки
	# Rush — прямой антипаттерн Fallout Shelter (docs/01 §2).
	for name: String in ["policies", "storage"]:
		panels.open(name)
		await _tree.process_frame
		if panels.is_open(name):
			_check_free_recall(name, name)
		panels.close()
		await _tree.process_frame
	Game.cmd_set_speed(1)

## Панель не имеет права пересекаться с кнопкой «Отзыв».
func _check_free_recall(title: String, panel_name: String) -> void:
	var panels: PanelHost = _main.get("panels") as PanelHost
	var node: Control = _panel_node(panels, panel_name)
	var button: Control = _hud.recall.get_node_or_null(^"Box/Button") as Control
	if node == null or button == null:
		return
	_check(not node.get_global_rect().intersects(button.get_global_rect()),
		"%s не перекрывает «Отзыв» (панель %s, кнопка %s)"
		% [title, str(node.get_global_rect()), str(button.get_global_rect())])

func _panel_node(panels: PanelHost, panel_name: String) -> Control:
	var reg: Dictionary = panels.get("_panels") as Dictionary
	return reg.get(panel_name, null) as Control

# --- Синтетическая мышь ----------------------------------------------------

## ⚠️ Событие мыши приходит в координатах ОКНА, а корневой вьюпорт пересчитывает
## его в свои координаты через final_transform (растяжка content_scale). В
## headless окна нет вовсе: DisplayServer отдаёт размер 0×0, растяжка выходит
## ×0.05 — и клик по кнопке уезжал в двадцать раз дальше её прямоугольника, а
## gui_get_hovered_control() отвечал «никто» независимо от дефектов игры.
## Все позиции ниже — в координатах вьюпорта (там же, где get_global_rect()),
## в окно их переводит этот хелпер. В обычном окне преобразование единичное.
func _to_window(viewport_pos: Vector2) -> Vector2:
	return _tree.root.get_final_transform() * viewport_pos

## Наведение. Событие движения нужно и GUI (ховер), и мировому SubViewport:
## призрак стройки берёт позицию оттуда.
##
## ⚠️ Порядок важен: сначала системный курсор, потом НАШЕ событие движения.
## В настоящем окне warp_mouse двигает курсор ОС, и она присылает своё событие
## следом — прилетая после нашего, оно уводило призрак к прежней точке и
## отменяло удержание ПКМ (сдвиг больше MOVE_TOLERANCE_PX): радиал то
## открывался, то нет. Даём системному событию приземлиться и перекрываем его
## своим. В headless warp_mouse — пустышка, но позиция курсора там и не нужна.
func _move_mouse(pos: Vector2) -> void:
	var at: Vector2 = _to_window(pos)
	Input.warp_mouse(at)
	await _tree.process_frame
	await _tree.process_frame
	var mm: InputEventMouseMotion = InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	Input.parse_input_event(mm)
	Input.flush_buffered_events()
	await _tree.process_frame

func _click_at(pos: Vector2) -> void:
	await _move_mouse(pos)
	_mouse_button(MOUSE_BUTTON_LEFT, pos, true)
	await _tree.process_frame
	_mouse_button(MOUSE_BUTTON_LEFT, pos, false)
	await _tree.process_frame

func _mouse_button(button: int, pos: Vector2, pressed: bool) -> void:
	var at: Vector2 = _to_window(pos)
	var mb: InputEventMouseButton = InputEventMouseButton.new()
	mb.button_index = button
	mb.position = at
	mb.global_position = at
	mb.pressed = pressed
	Input.parse_input_event(mb)
	Input.flush_buffered_events()

## Удержание ПКМ: радиал открывает InputService по своему таймеру, поэтому
## ждём его признака, а не считаем кадры на глазок.
func _hold_rmb(pos: Vector2) -> void:
	await _move_mouse(pos)
	_mouse_button(MOUSE_BUTTON_RIGHT, pos, true)
	var radial: BuildRadial = _main.get("build_radial") as BuildRadial
	for i: int in HOLD_FRAMES:
		if radial.is_open():
			break
		await _tree.process_frame
	_mouse_button(MOUSE_BUTTON_RIGHT, pos, false)
	await _tree.process_frame

# --- Мелочи мышиных шагов --------------------------------------------------

func _view_size() -> Vector2:
	return _tree.root.get_visible_rect().size

## Наводит камеру на первого колониста, которого после наводки видно в стороне
## от зон HUD, и отдаёт точку окна для клика. INF — такого нет.
##
## Целимся в НАРИСОВАННОГО колониста, а не в его позицию в симуляции: вид
## интерполирует ход и на паузе намеренно не доезжает до цели, а хит-тест
## (world.pick_at) считает по прямоугольнику вида. Игрок кликает по тому, что
## видит. Камеру у края карты клампит лимитами, поэтому колонист на верхней
## площадке может оказаться под верхней строкой — такого пропускаем.
func _aim_at_agent() -> Vector2:
	var camera: CameraRig = (_main.get("world_view") as Node).get("camera") as CameraRig
	var view: Vector2 = _view_size()
	for a: SimAgent in Game.world.agents.agents:
		if not a.is_alive():
			continue
		var world_pos: Vector2 = _agent_view_pos(a.id)
		camera.focus_on(world_pos, false)
		await _tree.process_frame
		var at: Vector2 = _main.call("_world_to_screen", world_pos) as Vector2
		if _is_world_point(at, view):
			return at
	return Vector2.INF

## Середина НАРИСОВАННОГО колониста (game/agent_view.gd), а не его позиция в
## симуляции. Именно середина прямоугольника: position — это ноги, а нижнюю
## кромку Rect2.has_point не считает своей, и клик «точно в агента» промахивался
## на пиксель округления.
func _agent_view_pos(id: int) -> Vector2:
	var views: Dictionary = (_main.get("world_view") as Node).get("_agent_views") as Dictionary
	var view: Node2D = views.get(id, null) as Node2D
	if view == null:
		return Game.query_agent_pos(id)
	return (view.call("hit_rect") as Rect2).get_center()

func _live_agent() -> int:
	if Game.world == null:
		return -1
	for a: SimAgent in Game.world.agents.agents:
		if a.is_alive():
			return a.id
	return -1

## Экран игры, без модалок, панелей и призрака: каждый мышиный шаг начинает
## с чистого состояния, иначе они таскают хвосты друг за другом.
func _ensure_plain_game() -> bool:
	if _router.current != ScreenRouter.Screen.GAME:
		_router.goto(ScreenRouter.Screen.GAME)
	if _router.is_modal_open():
		_router.close_modal()
	(_main.get("panels") as PanelHost).close()
	var ghost: BuildGhost = (_main.get("world_view") as Node).get("ghost") as BuildGhost
	ghost.set_def("")
	(_main.get("build_radial") as BuildRadial).close()
	await _dismiss_banner()
	await _tree.process_frame
	return _check(_router.current == ScreenRouter.Screen.GAME
		and not _router.is_modal_open(), "игра на экране и без модальных окон")

## Клетка, видная на экране в стороне от зон HUD (клик по ней обязан быть
## кликом по МИРУ, а не по интерфейсу) и подходящая под постройку — либо,
## при valid = false, заведомо НЕ подходящая: на такой проверяется отказ.
func _find_spot(def_id: String, valid: bool = true) -> Dictionary:
	var view: Vector2 = _view_size()
	var center_cell: Vector2i = WorldGeo.world_to_cell(
		_main.call("_screen_to_world", view * 0.5) as Vector2)
	for r: int in 20:
		for dy: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue            # только кольцо радиуса r
				var cell: Vector2i = center_cell + Vector2i(dx, dy)
				if Game.query_can_place(def_id, cell) != valid:
					continue
				var at: Vector2 = _main.call("_world_to_screen",
					WorldGeo.cell_center_world(cell)) as Vector2
				if _is_world_point(at, view):
					return {"cell": cell, "screen": at}
	return {}

## Точка окна свободна от HUD: верхняя строка, колонка шкалы, мёртвая зона
## «Отзыва» и края — не мир.
func _is_world_point(at: Vector2, view: Vector2) -> bool:
	var pad: float = 64.0
	if at.x < float(UITokens.TIDE_WIDTH) + pad or at.x > view.x - pad:
		return false
	if at.y < 120.0 or at.y > view.y - pad:
		return false
	return at.x < view.x - float(UITokens.DEADZONE_PX) \
		or at.y < view.y - float(UITokens.DEADZONE_PX)

## Вкладка «Управление» в живом дереве: строки ремапа собраны, подписи читаемы,
## список устройств честен. Ремап через перезапуск проверяет tools/remapcheck.sh —
## одним процессом этот стык не берётся.
func _step_input_tab() -> void:
	_step("вкладка «Управление»")
	_router.open_settings_from(ScreenRouter.Screen.GAME)
	await _tree.process_frame
	var screen: SettingsScreen = _router.screen_node(
		ScreenRouter.Screen.SETTINGS) as SettingsScreen
	if not _check(screen != null, "экран настроек собран"):
		return
	var tabs: TabContainer = screen.get("_tabs") as TabContainer
	tabs.current_tab = 3
	await _tree.process_frame

	var rows: Dictionary = screen.get("_bind_rows") as Dictionary
	_check_eq(rows.size(), Settings.REMAPPABLE.size(),
		"строка на каждое переназначаемое действие")
	var recall_row: Array = rows.get("recall", [] as Array) as Array
	if _check(recall_row.size() == InputBindings.SLOT_COUNT,
			"у действия три слота: две клавиши и геймпад"):
		# ⚠️ Подпись обязана быть человеческой: as_text() давал «Space - Physical»
		# и «Joypad Button 1 (Right Action, Sony Circle, Xbox B, Nintendo A)».
		_check_text((recall_row[0] as Button).text, "Space", "первый слот «Отзыва»")
		_check_text((recall_row[2] as Button).text, "B", "слот геймпада «Отзыва»")

	var pads: Label = screen.find_child("Pads", true, false) as Label
	if _check(pads != null, "список устройств на месте"):
		_check(not pads.text.strip_edges().is_empty(),
			"и он не пустое место, а строка: «%s»" % pads.text)
	# Подключение на ходу: экран обязан быть подписан на сигнал, а не читать
	# список один раз при заходе.
	_check(Input.joy_connection_changed.is_connected(
		Callable(screen, "_on_joy_changed")),
		"экран слушает подключение геймпада")

	_router.goto(ScreenRouter.Screen.GAME)
	await _tree.process_frame

## Подпись слота: сравниваем без учёта регистра и лишних пробелов — точную
## строку клавиши отдаёт движок.
func _check_text(got: String, want: String, what: String) -> void:
	_check(got.strip_edges() == want,
		"%s подписан как «%s» (получили «%s»)" % [what, want, got])

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
