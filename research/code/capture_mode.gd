class_name CaptureMode
extends Node
## Режим съёмки геймплея. Переносить в res://game/capture_mode.gd (этап 18),
## вешать на Main рядом с InputService.
##
## Зачем в коде, а не «выключу HUD руками»: дублей будет десятки, и каждый раз
## что-нибудь останется в кадре — курсор, тост, дебаг-панель (research/34 §0).
##
## Включается САМ, когда игру запускают на запись:
##   godot --write-movie build/capture/take01.avi --fixed-fps 60 --resolution 1920x1080
## Док Godot: «Use OS.has_feature("movie") in scripts to conditionally apply
## high-quality settings during recording».

signal layers_changed(mode: int)

enum Layers { ALL, WORLD_ONLY, UI_ONLY }

## Скорость симуляции во время записи. Фиксирована: иначе дубли снимаются
## с разной скоростью в зависимости от того, что игрок нажал в прошлом.
const CAPTURE_SPEED: int = 1
## Сколько кадров писать до автоостанова. ⚠️ Форс-квит (F8/Ctrl+C) портит файл
## — выход обязан быть корректным.
const DEFAULT_FRAMES: int = 1800          # 30 с при 60 fps

## Ручное включение без Movie Maker — для подбора кадра на глаз.
static var forced: bool = false

var layers: Layers = Layers.ALL
var _frames_left: int = -1
var _saved_scale_mode: Variant = null

static func is_capturing() -> bool:
	return OS.has_feature("movie") or forced

func _ready() -> void:
	if not is_capturing():
		return
	_enter_capture()

func _exit_tree() -> void:
	_restore_settings()

# --- Вход и выход ---------------------------------------------------------

func _enter_capture() -> void:
	# ⚠️ integer только на время съёмки: в игре он даёт чёрные поля на нецелых
	# окнах (research/10 §1), а при --resolution 1920x1080 нужен именно он.
	_saved_scale_mode = ProjectSettings.get_setting("display/window/stretch/scale_mode")
	ProjectSettings.set_setting("display/window/stretch/scale_mode", "integer")

	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	set_layers(Layers.WORLD_ONLY)
	Game.cmd_set_speed(CAPTURE_SPEED)
	# Автопауза остановила бы мир, а запись бы продолжилась: 30 секунд
	# неподвижного кадра (research/34 §2.3).
	_suppress_autopause()
	if _frames_left < 0:
		_frames_left = DEFAULT_FRAMES

func _restore_settings() -> void:
	if _saved_scale_mode != null:
		ProjectSettings.set_setting("display/window/stretch/scale_mode", _saved_scale_mode)
		_saved_scale_mode = null

func _process(_delta: float) -> void:
	if not is_capturing() or _frames_left < 0:
		return
	_frames_left -= 1
	if _frames_left <= 0:
		# Корректный выход: файл дописывается и закрывается.
		get_tree().quit()

# --- Слои -----------------------------------------------------------------

## Мир / только интерфейс / всё. Enum, а не bool: ролики про UI тоже нужны.
func set_layers(mode: Layers) -> void:
	layers = mode
	var main: Node = get_tree().current_scene
	if main == null:
		return
	var world_on: bool = mode != Layers.UI_ONLY
	var ui_on: bool = mode != Layers.WORLD_ONLY
	_set_visible(main, "WorldContainer", world_on)
	_set_visible(main, "HUDLayer", ui_on)
	_set_visible(main, "PanelLayer", ui_on)
	_set_visible(main, "BannerLayer", ui_on)
	_set_visible(main, "DebugLayer", false)     # дебаг в кадре не нужен никогда
	layers_changed.emit(int(mode))

func _set_visible(main: Node, node_name: String, on: bool) -> void:
	var n: Node = main.get_node_or_null(NodePath(node_name))
	if n == null:
		return
	if n is CanvasItem:
		(n as CanvasItem).visible = on
	elif n is CanvasLayer:
		(n as CanvasLayer).visible = on

# --- Управление во время подбора кадра ------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event.is_action_pressed("capture_toggle_layers"):
		set_layers(((int(layers) + 1) % Layers.size()) as Layers)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("capture_toggle"):
		forced = not forced
		if forced:
			_enter_capture()
		else:
			_restore_settings()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			set_layers(Layers.ALL)
		get_viewport().set_input_as_handled()

# --- Автопауза ------------------------------------------------------------

## Драфт и Итог цикла зовут Game.push_pause(). Во время съёмки паузы быть
## не должно: карту берём первую, отчёт не показываем.
func _suppress_autopause() -> void:
	Events.draft_ready.connect(func(ids: Array[String]) -> void:
		if not ids.is_empty():
			Game.cmd_pick_card(ids[0]))
	Events.cycle_ended.connect(func(_report: Dictionary) -> void:
		Game.pop_pause())

# --- Воспроизведение сцены по журналу -------------------------------------

## Перемотать забег к нужному тику и снимать оттуда. Единственный способ
## снять «тот самый шторм» десять раз подряд одинаково (research/34 §2.4).
##
## ⚠️ Сид под нужную сцену подбирается sweep-раннером (research/30 §4),
## а НЕ флагом «отключить случайные события»: второй путь исполнения
## симуляции — прямой путь к расхождению.
func replay_to(seed_value: int, command_log: Array[Dictionary], target_tick: int,
		lead_ticks: int = 600) -> void:
	var from_tick: int = maxi(0, target_tick - lead_ticks)
	Game.world = SimWorld.replay(seed_value, command_log, from_tick, Game.cliff_def())
	Game.rebroadcast_state()
	Game.cmd_set_speed(CAPTURE_SPEED)
