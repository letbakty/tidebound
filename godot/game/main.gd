extends Control
## Корень игры: гибридный вьюпорт (мир в SubViewport 640x360) + слои UI.
## Дерево и обоснование — docs/01 §1.1, research/10 §4.

@onready var world_container: SubViewportContainer = $WorldContainer
@onready var world_viewport: SubViewport = $WorldContainer/WorldViewport
@onready var hud_layer: CanvasLayer = $HUDLayer
@onready var panel_layer: CanvasLayer = $PanelLayer
@onready var banner_layer: CanvasLayer = $BannerLayer
@onready var debug_layer: CanvasLayer = $DebugLayer

func _ready() -> void:
	# Смоук-проверка локализации (этап 00): должно печатать «Отлив», а не ключ.
	print("[main] tr(APP_NAME) = ", tr("APP_NAME"))
	print("[main] window size = ", get_window().size, "  container = ", world_container.size)
	print("[main] world viewport size = ", world_viewport.size, " (ожидается половина контейнера)")

## Зум мира ступенями 2..4.
## РЕШЕНИЕ (research/10 §1): stretch_shrink держим константой 2, зум делает камера.
## Причина: 1280/3 = 426.67 — на shrink=3 контейнер не делится нацело и появляется
## полупиксельный шов. Этап 02 заменит тело на CameraRig.set_zoom_step(factor).
func set_world_zoom(factor: int) -> void:
	var f: int = clampi(factor, 2, 4)
	push_warning("set_world_zoom(%d): заглушка, зум переедет в CameraRig (этап 02)" % f)
