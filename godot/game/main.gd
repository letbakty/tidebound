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
	Events.draft_ready.connect(_on_draft_ready)
	# Забег создаётся ДО мира: World в _ready() уже видит рельеф и рисует его
	# сразу, без пустого кадра.
	Game.cmd_new_run(DEV_SEED)
	world_view = (load(WORLD_SCENE) as PackedScene).instantiate() as Node2D
	world_viewport.add_child(world_view)
	_spawn_debug_panel()
	Game.cmd_set_speed(1)

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

## Зум мира ступенями 2..4.
## РЕШЕНИЕ (research/10 §1): stretch_shrink держим константой 2, зум делает камера.
## Причина: 1280/3 = 426.67 — на shrink=3 контейнер не делится нацело и появляется
## полупиксельный шов.
func set_world_zoom(factor: int) -> void:
	if world_view == null:
		return
	(world_view.get_node("CameraRig") as CameraRig).set_zoom_step(clampi(factor, 2, 4))
