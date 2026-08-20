extends Control
## Корень игры: гибридный вьюпорт (мир в SubViewport 640x360) + слои UI.
## Дерево и обоснование — docs/01 §1.1, research/10 §4.

## Сид автостарта до появления главного меню (этап 15). Фиксированный —
## чтобы прогон «запустил и посмотрел» был воспроизводимым.
const DEV_SEED: int = 20260821
const WORLD_SCENE: String = "res://game/world.tscn"

@onready var world_container: SubViewportContainer = $WorldContainer
@onready var world_viewport: SubViewport = $WorldContainer/WorldViewport
@onready var hud_layer: CanvasLayer = $HUDLayer
@onready var panel_layer: CanvasLayer = $PanelLayer
@onready var banner_layer: CanvasLayer = $BannerLayer
@onready var debug_layer: CanvasLayer = $DebugLayer

var world_view: Node2D = null

func _ready() -> void:
	# TODO(этап 15): забег начинает MainMenu, автостарт убрать.
	Events.phase_changed.connect(_on_phase_changed)
	Events.cycle_ended.connect(_on_cycle_ended)
	# Забег создаётся ДО мира: World в _ready() уже видит рельеф и рисует его
	# сразу, без пустого кадра.
	Game.cmd_new_run(DEV_SEED)
	world_view = (load(WORLD_SCENE) as PackedScene).instantiate() as Node2D
	world_viewport.add_child(world_view)
	Game.cmd_set_speed(1)

func _on_phase_changed(phase: int, cycle: int) -> void:
	print("[sim] цикл %d, фаза %s, вода %.2f" % [
		cycle, SimTypes.phase_name(phase), Game.world.tide.level])

func _on_cycle_ended(report: Dictionary) -> void:
	print("[sim] итог цикла: ", report)

## Зум мира ступенями 2..4.
## РЕШЕНИЕ (research/10 §1): stretch_shrink держим константой 2, зум делает камера.
## Причина: 1280/3 = 426.67 — на shrink=3 контейнер не делится нацело и появляется
## полупиксельный шов.
func set_world_zoom(factor: int) -> void:
	if world_view == null:
		return
	(world_view.get_node("CameraRig") as CameraRig).set_zoom_step(clampi(factor, 2, 4))
