extends Control
## Корень игры: гибридный вьюпорт (мир в SubViewport 640x360) + слои UI.
## Дерево и обоснование — docs/01 §1.1, research/10 §4.

## Сид автостарта до появления главного меню (этап 15). Фиксированный —
## чтобы прогон «запустил и посмотрел» был воспроизводимым.
const DEV_SEED: int = 20260821
const WORLD_SCENE: String = "res://game/world.tscn"
const UI_THEME: String = "res://ui/theme/main_theme.tres"
const HUD_SCENE: String = "res://ui/hud/hud.tscn"

@onready var input_service: InputService = $InputService
@onready var world_container: SubViewportContainer = $WorldContainer
@onready var world_viewport: SubViewport = $WorldContainer/WorldViewport
@onready var hud_layer: CanvasLayer = $HUDLayer
@onready var panel_layer: CanvasLayer = $PanelLayer
@onready var banner_layer: CanvasLayer = $BannerLayer
@onready var debug_layer: CanvasLayer = $DebugLayer

var world_view: WorldView = null
var hud: Hud = null

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
	_wire_gestures()
	_spawn_debug_panel()
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

## InputService эмитит свои сигналы и никого не зовёт сам — связывает их Main.
## Радиал стройки по долгому нажатию подключит этап 14.
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

## Зум мира ступенями 2..4.
## РЕШЕНИЕ (research/10 §1): stretch_shrink держим константой 2, зум делает камера.
## Причина: 1280/3 = 426.67 — на shrink=3 контейнер не делится нацело и появляется
## полупиксельный шов.
func set_world_zoom(factor: int) -> void:
	if world_view == null:
		return
	world_view.camera.set_zoom_step(clampi(factor, 2, 4))
