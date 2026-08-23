extends Control
## Корень игры: гибридный вьюпорт (мир в SubViewport 640x360) + слои UI.
## Дерево и обоснование — docs/01 §1.1, research/10 §4.

const WORLD_SCENE: String = "res://game/world.tscn"
const UI_THEME: String = "res://ui/theme/main_theme.tres"
const HUD_SCENE: String = "res://ui/hud/hud.tscn"

## Имена панелей в реестре PanelHost.
const PANEL_POLICIES: String = "policies"
const PANEL_AGENT: String = "agent"
const PANEL_STATION: String = "station"
const PANEL_BUILDING: String = "building"
const PANEL_STORAGE: String = "storage"

## Постройки со своей панелью станции (docs/03 §5.4). Остальные — общая
## панель постройки; склад — своя.
const STATION_SPECIALS: Array[String] = ["forge", "workbench", "evaporator",
	"saltery", "dryer", "ropery", "winch", "condenser", "raincatcher"]

@onready var input_service: InputService = $InputService
@onready var world_container: SubViewportContainer = $WorldContainer
@onready var world_viewport: SubViewport = $WorldContainer/WorldViewport
@onready var hud_layer: CanvasLayer = $HUDLayer
@onready var panel_layer: CanvasLayer = $PanelLayer
@onready var banner_layer: CanvasLayer = $BannerLayer
@onready var screen_layer: CanvasLayer = $ScreenLayer
@onready var debug_layer: CanvasLayer = $DebugLayer
@onready var weather_layer: CanvasLayer = $WeatherLayer

var world_view: WorldView = null
var hud: Hud = null
var panels: PanelHost = null
var build_radial: BuildRadial = null
var deposit_tip: DepositTooltip = null
var router: ScreenRouter = null
var hints: HintCard = null
## Погода и атмосфера (этап 18): дирижирует эффектами внутри мира и снаружи.
var weather: WeatherView = null
## Режим съёмки (research/34): скрывает HUD и фиксирует скорость.
var capture: CaptureMode = null
## Режим установки маяка: следующий тап по миру ставит маяк.
var _beacon_mode: bool = false
## Корни UI на слоях: их размер держим синхронным с окном вручную.
var _layer_roots: Array[Control] = []
## Текущая тема. ⚠️ Хранится, а не читается с диска каждый раз: диалоги
## создаются в рантайме, и после смены кегля новый ConfirmDialog получал
## СТАРУЮ тему из main_theme.tres (аудит B3).
var _theme: Theme = null

func _ready() -> void:
	# ⚠️ Корень игры — полноэкранный Control, который ничего не рисует, и со
	# STOP по умолчанию он съедал ВЕСЬ ввод мышью по миру: событие доходило до
	# WorldContainer (PASS), поднималось по родителям и умирало здесь, так и не
	# дойдя до _unhandled_input. Тап по колонисту, удержание ПКМ (радиал) и зум
	# колесом мышью не работали вовсе — панорама жила только потому, что её
	# ловит CameraRig ВНУТРИ мирового SubViewport.
	# Тот же дефект, что и каркас пустого экрана (ui/screens/game_screen.gd),
	# только слоем ниже. Проверено кликами: см. tools/playtest_run.gd, шаг
	# «постройка ставится одной мышью».
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Events.cycle_ended.connect(_on_cycle_ended)
	Events.draft_ready.connect(_on_draft_ready)
	Events.run_ended.connect(_on_run_ended)
	# Сначала собирается ВСЯ сцена, и только потом стартует забег: стартовые
	# события (ресурсы, постройки, агенты) уходят один раз, и подписчик,
	# созданный позже, их уже не увидит. World рисует рельеф по run_started.
	world_view = (load(WORLD_SCENE) as PackedScene).instantiate() as WorldView
	world_viewport.add_child(world_view)
	_spawn_weather()
	_spawn_hud()
	_spawn_panels()
	_spawn_screens()
	_wire_gestures()
	_spawn_debug_panel()
	# Один обработчик на все корни: connect с .bind() для каждого узла движок
	# считает одним и тем же callable и ругается на повторное соединение.
	get_viewport().size_changed.connect(_restretch_layer_roots)
	# Доступность (кегль, пресет для дальтоников, контраст) меняет саму тему.
	Settings.theme_changed.connect(_rebuild_theme)
	# Забег начинает игрок из меню: автостарта больше нет (docs/03 §2).
	router.goto(ScreenRouter.Screen.BOOT)

## Погода собирается ДО HUD: дождь и туман живут внутри мира, виньетка —
## снаружи, и обе половины должна держать одна нода (этап 18).
func _spawn_weather() -> void:
	weather = WeatherView.new()
	weather.name = "WeatherView"
	add_child(weather)
	weather.setup(world_view.rain_rect(), world_view.fog_rect(),
		weather_layer.get_node_or_null(^"Vignette") as ColorRect,
		world_view.fx_root(), world_viewport)
	capture = CaptureMode.new()
	capture.name = "CaptureMode"
	add_child(capture)

## HUD кладётся на свой слой через attach_ui: каскад темы на CanvasLayer
## рвётся, и корню слоя тема нужна явно (research/19 §3).
func _spawn_hud() -> void:
	hud = (load(HUD_SCENE) as PackedScene).instantiate() as Hud
	attach_ui(hud_layer, hud)
	hud.camera_focus_requested.connect(world_view.camera.focus_on.bind(true))
	hud.overlay_requested.connect(func(mode: String) -> void:
		world_view.overlay.toggle(mode))
	hud.beacon_mode_requested.connect(func() -> void: set_beacon_mode(true))
	# Тап по тосту и по шкале — единственные способы увести камеру (docs/01 §5).
	hud.legend_requested.connect(func() -> void:
		panels.close())

## Панели живут на PanelLayer и общаются с миром только через Main:
## сами они о world_view не знают (docs/02 §1).
func _spawn_panels() -> void:
	panels = PanelHost.new()
	panels.name = "PanelHost"
	attach_ui(panel_layer, panels)

	var policies: PolicyPanel = PolicyPanel.new()
	policies.name = "PolicyPanel"
	panels.register(PANEL_POLICIES, policies)

	var agent: AgentCard = AgentCard.new()
	agent.name = "AgentCard"
	panels.register(PANEL_AGENT, agent)
	agent.focus_requested.connect(func(id: int) -> void:
		world_view.camera.focus_on(Game.query_agent_pos(id), true))

	var station: StationPanel = StationPanel.new()
	station.name = "StationPanel"
	panels.register(PANEL_STATION, station)
	station.repair_requested.connect(_on_repair)
	station.demolish_requested.connect(_on_demolish)

	var building: BuildingPanel = BuildingPanel.new()
	building.name = "BuildingPanel"
	panels.register(PANEL_BUILDING, building)
	building.repair_requested.connect(_on_repair)
	building.demolish_requested.connect(_on_demolish)

	var storage: StoragePanel = StoragePanel.new()
	storage.name = "StoragePanel"
	panels.register(PANEL_STORAGE, storage)

	build_radial = BuildRadial.new()
	build_radial.name = "BuildRadial"
	attach_ui(panel_layer, build_radial)
	build_radial.building_chosen.connect(_on_building_chosen)

	deposit_tip = DepositTooltip.new()
	deposit_tip.name = "DepositTooltip"
	attach_ui(panel_layer, deposit_tip)

	hud.agent_card_requested.connect(func(id: int) -> void:
		panels.open(PANEL_AGENT, {"id": id}))

## Экраны живут на своём слое и переключаются видимостью (research/22 §1).
func _spawn_screens() -> void:
	router = ScreenRouter.new()
	router.name = "ScreenRouter"
	attach_ui(screen_layer, router)
	router.setup_layers(world_container, hud_layer, panel_layer)

	router.screen_changed.connect(_on_screen_changed)

	var boot: BootScreen = BootScreen.new()
	boot.name = "BootScreen"
	router.register(ScreenRouter.Screen.BOOT, boot)
	boot.finished.connect(_on_boot_finished)

	var first: FirstLaunch = FirstLaunch.new()
	first.name = "FirstLaunch"
	router.register(ScreenRouter.Screen.FIRST_LAUNCH, first)
	first.done.connect(func(open_access: bool) -> void:
		Settings.apply()
		if open_access:
			router.open_settings_from(ScreenRouter.Screen.MAIN_MENU)
		else:
			router.goto(ScreenRouter.Screen.MAIN_MENU))

	var menu: MainMenu = MainMenu.new()
	menu.name = "MainMenu"
	router.register(ScreenRouter.Screen.MAIN_MENU, menu)
	menu.continue_requested.connect(_continue_run)
	menu.new_run_requested.connect(_start_run)
	menu.journal_requested.connect(func() -> void:
		router.goto(ScreenRouter.Screen.JOURNAL))
	menu.settings_requested.connect(func() -> void:
		router.open_settings_from(ScreenRouter.Screen.MAIN_MENU))
	menu.credits_requested.connect(func() -> void:
		router.goto(ScreenRouter.Screen.CREDITS))
	menu.quit_requested.connect(func() -> void: get_tree().quit())

	var journal: JournalScreen = JournalScreen.new()
	journal.name = "JournalScreen"
	router.register(ScreenRouter.Screen.JOURNAL, journal)
	journal.back_requested.connect(func() -> void:
		router.goto(ScreenRouter.Screen.MAIN_MENU))

	var settings: SettingsScreen = SettingsScreen.new()
	settings.name = "SettingsScreen"
	router.register(ScreenRouter.Screen.SETTINGS, settings)
	settings.back_requested.connect(func() -> void:
		var back: ScreenRouter.Screen = router.settings_return()
		router.goto(back)
		# Настройки открывали из паузы — возвращаемся именно в неё.
		if back == ScreenRouter.Screen.GAME:
			router.open_modal(ScreenRouter.Modal.PAUSE, {}, true))
	settings.profile_reset.connect(func() -> void:
		router.goto(ScreenRouter.Screen.MAIN_MENU))

	var credits: CreditsScreen = CreditsScreen.new()
	credits.name = "CreditsScreen"
	router.register(ScreenRouter.Screen.CREDITS, credits)
	credits.back_requested.connect(func() -> void:
		router.goto(ScreenRouter.Screen.MAIN_MENU))

	# Экран игры — пустышка без единого узла: мир и HUD живут на своих слоях,
	# роутер только включает их видимость (см. ui/screens/game_screen.gd).
	var game_screen: GameScreen = GameScreen.new()
	game_screen.name = "GameScreen"
	router.register(ScreenRouter.Screen.GAME, game_screen)

	_spawn_modals()

	hints = HintCard.new()
	hints.name = "HintCard"
	attach_ui(hud_layer, hints)
	var save_mark: SaveIndicator = SaveIndicator.new()
	save_mark.name = "SaveIndicator"
	attach_ui(hud_layer, save_mark)

func _spawn_modals() -> void:
	var draft: DraftPanel = DraftPanel.new()
	draft.name = "DraftPanel"
	router.register_modal(ScreenRouter.Modal.DRAFT, draft)
	draft.card_confirmed.connect(func(card_id: String) -> void:
		router.close_modal()
		Game.cmd_pick_card(card_id))

	var cycle: CycleSummary = CycleSummary.new()
	cycle.name = "CycleSummary"
	router.register_modal(ScreenRouter.Modal.CYCLE_SUMMARY, cycle)
	# Паузу этого окна ставил Game на границе цикла, а снимает роутер: окно
	# может закрыться и не кнопкой (его вытеснил Итог забега), а счётчик
	# автопаузы обязан сойтись в любом случае.
	cycle.closed.connect(func() -> void: router.close_modal())

	var run: RunSummary = RunSummary.new()
	run.name = "RunSummary"
	router.register_modal(ScreenRouter.Modal.RUN_SUMMARY, run)
	run.journal_requested.connect(func() -> void:
		router.close_modal()
		router.goto(ScreenRouter.Screen.JOURNAL))

	var pause: PausePanel = PausePanel.new()
	pause.name = "PausePanel"
	router.register_modal(ScreenRouter.Modal.PAUSE, pause)
	pause.resume_requested.connect(func() -> void: router.close_modal())
	pause.settings_requested.connect(func() -> void:
		router.close_modal()
		router.open_settings_from(ScreenRouter.Screen.GAME))
	pause.menu_requested.connect(func() -> void:
		Game.cmd_save()
		router.close_modal()
		router.goto(ScreenRouter.Screen.MAIN_MENU))
	pause.leave_requested.connect(func(early: bool) -> void:
		router.close_modal()
		if early:
			Game.cmd_leave_early()
		else:
			Game.cmd_surrender())

	var error: ErrorDialog = ErrorDialog.new()
	error.name = "ErrorDialog"
	router.register_modal(ScreenRouter.Modal.ERROR, error)
	error.closed.connect(func() -> void:
		router.close_modal()
		router.goto(ScreenRouter.Screen.MAIN_MENU))

## Мир и жесты по миру живут ТОЛЬКО на экране игры. Скрытый мир продолжал
## считать и ловить ввод: WASD и колесо крутили камеру под меню, а тап по
## «пустому месту» экрана уходил в размещение постройки (аудит B1.5).
func _on_screen_changed(screen: int) -> void:
	var in_game: bool = screen == int(ScreenRouter.Screen.GAME)
	var mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT if in_game \
		else Node.PROCESS_MODE_DISABLED
	if world_view != null:
		world_view.process_mode = mode
	if input_service != null:
		input_service.process_mode = mode

func _on_boot_finished(profile_ok: bool) -> void:
	if not profile_ok:
		router.open_modal(ScreenRouter.Modal.ERROR, {
			"what": "ERROR_PROFILE_BROKEN", "did": "ERROR_PROFILE_BROKEN_DID",
			"details": Meta.PROFILE_PATH}, false)
		return
	# Настроек на диске не было — это первый запуск: спрашиваем язык
	# (docs/03 §3.2; карта переходов говорит «нет профиля», но профиль
	# появляется и от одной покупки в Журнале, а settings.json — ровно от
	# первого старта). Флаг снят в Settings._ready ДО первой записи файла:
	# к концу заставки has_file() уже врёт (аудит B1.3).
	router.goto(ScreenRouter.Screen.FIRST_LAUNCH if Settings.first_launch
		else ScreenRouter.Screen.MAIN_MENU)

func _start_run(seed_value: int) -> void:
	# Скорость забега передаём в сам старт: выставлять её после — значит снять
	# автопаузу стартового драфта (см. Game.cmd_new_run).
	Game.cmd_new_run(seed_value, Settings.default_speed)
	world_view.camera.set_zoom_step(Settings.world_zoom)
	router.goto(ScreenRouter.Screen.GAME)

## Продолжение забега из сейва. Битый файл — ErrorDialog, профиль не трогаем
## (docs/03 §8).
func _continue_run() -> void:
	if not Game.cmd_load():
		router.open_modal(ScreenRouter.Modal.ERROR, {
			"what": "ERROR_SAVE_BROKEN", "did": "ERROR_SAVE_BROKEN_DID",
			"details": SaveService.RUN_PATH}, false)
		return
	world_view.camera.set_zoom_step(Settings.world_zoom)
	router.goto(ScreenRouter.Screen.GAME)
	Game.cmd_set_speed(0)

## InputService эмитит свои сигналы и никого не зовёт сам — связывает их Main.
func _wire_gestures() -> void:
	var camera: CameraRig = world_view.camera
	input_service.zoom_step.connect(func(delta: int) -> void:
		if delta > 0:
			camera.zoom_in()
		else:
			camera.zoom_out())
	input_service.world_dragged.connect(camera.pan_by)
	# Двойной тап по пустому месту — цикл скоростей (docs/00 §13).
	input_service.world_double_tapped.connect(func(_pos: Vector2) -> void:
		Game.cmd_set_speed(1 if Game.speed >= 3 else Game.speed + 1))
	input_service.world_tapped.connect(_on_world_tapped)
	# Прогресс долгого нажатия виден у пальца (docs/01 §5).
	input_service.long_press_progress.connect(func(pos: Vector2, t: float) -> void:
		hud.press.show_progress(pos, t))
	# Курсор геймпада появляется только когда игрок взялся за геймпад.
	input_service.device_changed.connect(func(device: int) -> void:
		hud.cursor.set_active(device == int(InputService.Device.PAD))
		hud.hints.set_device(device))
	hud.cursor.tapped.connect(_on_cursor_tapped)
	input_service.world_long_pressed.connect(_on_world_long_pressed)
	input_service.edge_swipe_right.connect(func() -> void:
		panels.open(PANEL_POLICIES))

# --- Ввод по миру ---------------------------------------------------------

## Клавиши панелей: политики (P), радиал стройки (B), маяк (M).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_menu") and router.current == ScreenRouter.Screen.GAME:
		# Панель закрывает PanelHost сам; сюда событие дойдёт только если
		# открытых панелей нет — тогда это запрос окна паузы (docs/03 §2).
		if not router.is_modal_open():
			# Незавершённое размещение Esc отменяет ПЕРВЫМ: меню поверх призрака
			# заставило бы игрока выходить из двух состояний подряд.
			if _cancel_ghost():
				get_viewport().set_input_as_handled()
				return
			router.open_modal(ScreenRouter.Modal.PAUSE, {}, true)
			get_viewport().set_input_as_handled()
		return
	if router.current != ScreenRouter.Screen.GAME or router.is_modal_open():
		return
	# Правый клик — отмена размещения. Событие НЕ поглощаем: удержание той же
	# кнопки открывает радиал, и жест из docs/00 §13 обязан остаться живым.
	var rmb: InputEventMouseButton = event as InputEventMouseButton
	if rmb != null and rmb.pressed and rmb.button_index == MOUSE_BUTTON_RIGHT:
		_cancel_ghost()
	if event.is_action_pressed("zoom_in"):
		world_view.camera.zoom_in()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("zoom_out"):
		world_view.camera.zoom_out()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("policies"):
		panels.open(PANEL_POLICIES)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_radial"):
		# Геймпад открывает радиал у виртуального курсора, мышь — у своего.
		var at: Vector2 = hud.cursor.position_on_screen() if hud.cursor.active \
			else get_viewport().get_mouse_position()
		_open_build_radial(at)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("beacon"):
		set_beacon_mode(not _beacon_mode)
		get_viewport().set_input_as_handled()

## Режим установки маяка: следующий тап по миру ставит его (docs/00 §13).
func set_beacon_mode(on: bool) -> void:
	_beacon_mode = on
	world_view.beacon.set_placing(on)

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	# Конверсия ЕДИНСТВЕННАЯ на проект: вьюпорт↔мир живёт в World (docs/01 §1.1),
	# экран↔вьюпорт — здесь, потому что про контейнер знает только Main.
	return world_view.viewport_to_world(_to_viewport(screen_pos))

## Обратная дорога: точка мира → точка окна. Нужна проверке координат в
## tools/playtest_run.gd и всему, что ставит UI «у объекта».
func _world_to_screen(world_pos: Vector2) -> Vector2:
	return world_view.world_to_viewport(world_pos) * _shrink() \
		+ world_container.global_position

## Точка экрана → координаты мирового SubViewport: UI живёт в нативном
## разрешении, мир — в 640×360 с контейнером-множителем.
##
## ⚠️ ДЕЛЕНИЕ, а не умножение: 1280 пикселей окна — это 640 пикселей вьюпорта
## при stretch_shrink = 2. Умножение уводило клик на 34 клетки от курсора, и
## ошибка росла от левого верхнего угла к правому нижнему. Через эту точку
## ходит ВЕСЬ ввод по миру: выбор колониста, панели, тултип депозита, маяк,
## размещение постройки.
func _to_viewport(screen_pos: Vector2) -> Vector2:
	return (screen_pos - world_container.global_position) / _shrink()

func _shrink() -> float:
	return maxf(float(world_container.stretch_shrink), 1.0)

func _open_build_radial(screen_pos: Vector2) -> void:
	panels.close()
	build_radial.open_at(screen_pos, _screen_to_world(screen_pos), false)

## Тап курсором геймпада — тот же путь, что и палец: один разбор на всё.
func _on_cursor_tapped(screen_pos: Vector2) -> void:
	_on_world_tapped(screen_pos)

func _on_world_long_pressed(screen_pos: Vector2) -> void:
	build_radial.open_at(screen_pos, _screen_to_world(screen_pos), true)

## Один разбор тапа по миру на всю игру: маяк, размещение постройки, хит-тест.
func _on_world_tapped(screen_pos: Vector2) -> void:
	var world_pos: Vector2 = _screen_to_world(screen_pos)
	var cell: Vector2i = WorldGeo.world_to_cell(world_pos)
	if _beacon_mode:
		Game.cmd_set_beacon(cell)
		set_beacon_mode(false)
		return
	if not world_view.ghost.def_id.is_empty():
		# Палец и курсор геймпада «наводят» призрак самим тапом: ховера у них
		# нет, и без этого шага подсветка осталась бы в точке открытия радиала.
		if not _pointer_is_mouse():
			world_view.ghost.set_cursor_world(world_pos)
		# Ставим в клетку ПРИЗРАКА, а не клика: игрок видел валидность именно
		# её, и источник правды обязан быть один (docs/01 §3).
		if Game.cmd_place_building(world_view.ghost.def_id,
				world_view.ghost.current_cell()):
			world_view.ghost.set_def("")     # поставили — призрак больше не нужен
		else:
			# Отказ призрак НЕ снимает: игрок видит причину отказа и пробует
			# соседнюю клетку, а не открывает радиал заново тремя действиями.
			# Снять — правым кликом или Esc. Успех озвучит AudioService.
			AudioService.play_ui("ui_error")
		return
	var hit: Dictionary = world_view.pick_at(world_pos)
	match str(hit["kind"]):
		"agent":
			panels.open(PANEL_AGENT, {"id": int(hit["id"])})
		"building":
			_open_building_panel(int(hit["id"]))
		"deposit":
			deposit_tip.show_for(int(hit["id"]), screen_pos)
		_:
			panels.close()

## Хит-тест различает склад, станцию и прочую постройку: каждый открывает своё.
func _open_building_panel(id: int) -> void:
	var b: Dictionary = Game.query_building(id)
	if b.is_empty():
		return
	var def: BuildingDef = DB.building(str(b["def_id"]))
	if def == null:
		return
	if def.special == "storage":
		var sid: int = Game.query_storage_at(b["cell"] as Vector2i)
		if sid >= 0:
			panels.open(PANEL_STORAGE, {"id": sid})
			return
	if STATION_SPECIALS.has(def.special):
		panels.open(PANEL_STATION, {"id": id})
		return
	panels.open(PANEL_BUILDING, {"id": id})

func _on_building_chosen(def_id: String, at_world: Vector2) -> void:
	world_view.ghost.set_def(def_id)
	# На ПК призрак ходит за курсором сам; палец и курсор геймпада ведут его
	# последней точкой жеста (game/build_ghost.gd).
	if _pointer_is_mouse():
		world_view.ghost.follow_mouse()
	else:
		world_view.ghost.set_cursor_world(at_world)

## Чем игрок целится прямо сейчас. Курсор геймпада включается только когда за
## геймпад взялись, «mobile» — сборка под телефон: и там, и там ховера нет.
func _pointer_is_mouse() -> bool:
	if hud != null and hud.cursor != null and hud.cursor.active:
		return false
	return not OS.has_feature("mobile")

## Снимает призрак стройки. true — было что снимать: Esc и правый клик сначала
## отменяют начатое размещение и только потом делают своё обычное дело.
func _cancel_ghost() -> bool:
	if world_view == null or world_view.ghost.def_id.is_empty():
		return false
	world_view.ghost.set_def("")
	AudioService.play_ui("ui_cancel")
	return true

## Снос — необратим, поэтому через подтверждение (docs/03 §4.4).
func _on_demolish(building_id: int) -> void:
	var dialog: ConfirmDialog = ConfirmDialog.new()
	dialog.name = "ConfirmDemolish"
	attach_ui(panel_layer, dialog)
	dialog.setup("PANEL_BUILDING", "CONFIRM_DEMOLISH", "ACT_DEMOLISH", true, "")
	dialog.confirmed.connect(func() -> void:
		Game.cmd_demolish(building_id)
		panels.close()
		dialog.queue_free())
	dialog.cancelled.connect(func() -> void: dialog.queue_free())
	dialog.open()

func _on_repair(building_id: int) -> void:
	Game.cmd_repair(building_id)

## Дебаг-панель именно СОЗДАЁТСЯ по гейту, а не прячется: скрытая утащила бы
## в релиз сцену, скрипт и все подписки на Events.
## load(), а не preload(): preload разрешается на этапе компиляции и попал бы
## в сборку независимо от условия (research/13 §3).
func _spawn_debug_panel() -> void:
	if not OS.is_debug_build():
		return
	var scn: PackedScene = load("res://debug/debug_panel.tscn") as PackedScene
	if scn == null:
		return                      # release-пресет вырезает res://debug/*
	var panel: Control = scn.instantiate() as Control
	debug_layer.add_child(panel)
	panel.call("setup", world_view)

## Драфт, итог цикла и итог забега — модальные окна поверх живой игры.
##
## Оба приходят из sim ОДНИМ батчем, поэтому оба идут в очередь роутера, а не
## затирают друг друга: Итог цикла показывается первым, драфт ждёт (docs/03 §1).
## Экран не проверяем — окно забега вне игры роутер придержит сам, и драфт
## после «Продолжить» не потеряется (docs/03 §8).
func _on_draft_ready(card_ids: Array[String]) -> void:
	if card_ids.is_empty():
		return
	# Паузу уже поставил Game (если игрок её не выключил) — второй раз не ставим,
	# но роутер обязан её снять, когда окно закроется.
	router.open_modal(ScreenRouter.Modal.DRAFT, {"cards": card_ids}, false,
		Settings.pause_on_draft)

func _on_cycle_ended(report: Dictionary) -> void:
	router.open_modal(ScreenRouter.Modal.CYCLE_SUMMARY, {"report": report}, false,
		Settings.pause_on_cycle)

## Забег кончился, пока была открыта панель — панель закрывается, итог поверх
## (docs/03 §8).
func _on_run_ended(report: Dictionary) -> void:
	panels.close()
	router.open_modal(ScreenRouter.Modal.RUN_SUMMARY, {"report": report}, false)

## Тема слоям назначается ЯВНО: CanvasLayer — не Control, и каскад темы на нём
## рвётся (research/19 §3). Через этот хелпер этапы 13–15 кладут свои корни.
func attach_ui(layer: CanvasLayer, node: Control) -> void:
	if _theme == null:
		_theme = load(UI_THEME) as Theme
	node.theme = _theme
	layer.add_child(node)
	_prune_layer_roots()
	_layer_roots.append(node)
	_stretch_to_viewport(node)

## Диалоги живут до закрытия и уходят в queue_free — их ссылки в списке
## остаются навсегда, если их не выметать (аудит B3).
func _prune_layer_roots() -> void:
	var alive: Array[Control] = []
	for node: Control in _layer_roots:
		if is_instance_valid(node):
			alive.append(node)
	_layer_roots = alive

## ⚠️ Control, созданный кодом под CanvasLayer, размера сам не получает:
## у слоя нет прямоугольника, и якоря считаются от нуля (в сцене это скрыто
## сохранёнными offsets). Растягиваем явно, иначе панели уезжают за экран.
## Пересборка темы из токенов и палитры: сцены при этом не трогаются —
## компоненты подхватят новое через NOTIFICATION_THEME_CHANGED (docs/01 §1.2).
func _rebuild_theme() -> void:
	_theme = UIThemeFactory.build()
	_prune_layer_roots()
	for node: Control in _layer_roots:
		node.theme = _theme

func _restretch_layer_roots() -> void:
	_prune_layer_roots()
	for node: Control in _layer_roots:
		_stretch_to_viewport(node)

func _stretch_to_viewport(node: Control) -> void:
	if not is_instance_valid(node):
		return
	# Якоря НУЛЕВЫЕ, размер задаём руками: при растянутых якорях движок
	# пересчитает size от родителя (у слоя он нулевой) и перекроет наш.
	node.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	node.size = get_viewport_rect().size

## Зум мира ступенями 2..4.
## РЕШЕНИЕ (research/10 §1): stretch_shrink держим константой 2, зум делает камера.
## Причина: 1280/3 = 426.67 — на shrink=3 контейнер не делится нацело и появляется
## полупиксельный шов.
func set_world_zoom(factor: int) -> void:
	if world_view == null:
		return
	world_view.camera.set_zoom_step(clampi(factor, 2, 4))
