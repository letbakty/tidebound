extends Control
## Корень игры: гибридный вьюпорт (мир в SubViewport 640x360) + слои UI.
## Дерево и обоснование — docs/01 §1.1, research/10 §4.

## Сид автостарта до появления главного меню (этап 15). Фиксированный —
## чтобы прогон «запустил и посмотрел» был воспроизводимым.
const DEV_SEED: int = 20260821
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
@onready var debug_layer: CanvasLayer = $DebugLayer

var world_view: WorldView = null
var hud: Hud = null
var panels: PanelHost = null
var build_radial: BuildRadial = null
var deposit_tip: DepositTooltip = null
## Режим установки маяка: следующий тап по миру ставит маяк.
var _beacon_mode: bool = false
## Корни UI на слоях: их размер держим синхронным с окном вручную.
var _layer_roots: Array[Control] = []

func _ready() -> void:
	# TODO(этап 15): забег начинает MainMenu, автостарт убрать.
	Events.phase_changed.connect(_on_phase_changed)
	Events.cycle_ended.connect(_on_cycle_ended)
	Events.draft_ready.connect(_on_draft_ready)
	# Сначала собирается ВСЯ сцена, и только потом стартует забег: стартовые
	# события (ресурсы, постройки, агенты) уходят один раз, и подписчик,
	# созданный позже, их уже не увидит. World рисует рельеф по run_started.
	world_view = (load(WORLD_SCENE) as PackedScene).instantiate() as WorldView
	world_viewport.add_child(world_view)
	_spawn_hud()
	_spawn_panels()
	_wire_gestures()
	_spawn_debug_panel()
	# Один обработчик на все корни: connect с .bind() для каждого узла движок
	# считает одним и тем же callable и ругается на повторное соединение.
	get_viewport().size_changed.connect(_restretch_layer_roots)
	Game.cmd_new_run(DEV_SEED)
	Game.cmd_set_speed(1)

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
	input_service.world_long_pressed.connect(_on_world_long_pressed)
	input_service.edge_swipe_right.connect(func() -> void:
		panels.open(PANEL_POLICIES))

# --- Ввод по миру ---------------------------------------------------------

## Клавиши панелей: политики (P), радиал стройки (B), маяк (M).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("policies"):
		panels.open(PANEL_POLICIES)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_radial"):
		var mouse: Vector2 = get_viewport().get_mouse_position()
		_open_build_radial(mouse)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("beacon"):
		set_beacon_mode(not _beacon_mode)
		get_viewport().set_input_as_handled()

## Режим установки маяка: следующий тап по миру ставит его (docs/00 §13).
func set_beacon_mode(on: bool) -> void:
	_beacon_mode = on
	world_view.beacon.set_placing(on)

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	# Конверсия ЕДИНСТВЕННАЯ на проект и живёт в World (docs/01 §1.1).
	return world_view.screen_to_world(_to_viewport(screen_pos))

## Точка экрана → координаты мирового SubViewport: UI живёт в нативном
## разрешении, мир — в 640×360 с контейнером-множителем.
func _to_viewport(screen_pos: Vector2) -> Vector2:
	var scale: float = float(world_container.stretch_shrink)
	return (screen_pos - world_container.global_position) * scale

func _open_build_radial(screen_pos: Vector2) -> void:
	panels.close()
	build_radial.open_at(screen_pos, _screen_to_world(screen_pos), false)

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
		# Тап мимо валидного места — отмена, а не молчание.
		if not Game.cmd_place_building(world_view.ghost.def_id, cell):
			world_view.ghost.set_def("")
		else:
			world_view.ghost.set_def("")
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
	world_view.ghost.set_cursor_world(at_world)

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

func _on_phase_changed(phase: int, cycle: int) -> void:
	print("[sim] цикл %d, фаза %s, вода %.2f" % [
		cycle, SimTypes.phase_name(phase), Game.world.tide.level])

## Драфт ставит игру на автопаузу и ждёт выбора. Панели выбора ещё нет
## (этап 15), а без выбора мир стоит намертво — поэтому здесь временный
## дублёр: берём первую карту. Кнопки выбора есть в дебаг-панели.
## TODO(этап 15): убрать вместе с автостартом — выбирать будет DraftPanel.
func _on_draft_ready(card_ids: Array[String]) -> void:
	if card_ids.is_empty():
		return
	print("[sim] драфт: ", card_ids, " → берём ", card_ids[0])
	Game.cmd_pick_card(card_ids[0])

func _on_cycle_ended(report: Dictionary) -> void:
	print("[sim] итог цикла: ", report)

## Тема слоям назначается ЯВНО: CanvasLayer — не Control, и каскад темы на нём
## рвётся (research/19 §3). Через этот хелпер этапы 13–15 кладут свои корни.
func attach_ui(layer: CanvasLayer, node: Control) -> void:
	node.theme = load(UI_THEME) as Theme
	layer.add_child(node)
	_layer_roots.append(node)
	_stretch_to_viewport(node)

## ⚠️ Control, созданный кодом под CanvasLayer, размера сам не получает:
## у слоя нет прямоугольника, и якоря считаются от нуля (в сцене это скрыто
## сохранёнными offsets). Растягиваем явно, иначе панели уезжают за экран.
func _restretch_layer_roots() -> void:
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
