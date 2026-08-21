class_name CaptureMode
extends Node
## Режим съёмки геймплея (research/34).
##
## Зачем в коде, а не «выключу HUD руками»: дублей будет десятки, и каждый раз
## что-нибудь остаётся в кадре — курсор, тост, дебаг-панель. Плюс запись идёт
## в реальном времени, а мир на автопаузе стоит: без подавления пауз ролик
## наполовину состоит из неподвижного кадра.
##
## Включается САМ, когда игру запускают на запись:
##   godot --write-movie build/capture/take01.avi --fixed-fps 60 --resolution 1920x1080
## Док Godot: OS.has_feature("movie") — признак запущенного Movie Maker.
##
## Вручную (подобрать кадр глазами) — F9, что попадает в кадр — F10.

signal layers_changed(mode: int)

enum Layers { ALL, WORLD_ONLY, UI_ONLY }

## Скорость во время записи фиксирована: иначе дубли снимаются с разной
## скоростью в зависимости от того, что игрок нажал в прошлый раз.
const CAPTURE_SPEED: int = 1
## Автоостанов записи. ⚠️ Форс-квит портит файл — выход обязан быть корректным.
const DEFAULT_FRAMES: int = 1800          # 30 с при 60 fps

## Ручное включение без Movie Maker.
static var forced: bool = false

var layers: Layers = Layers.ALL
var _frames_left: int = -1
var _autopause_hooked: bool = false
var _saved_pauses: Array[bool] = []

static func is_capturing() -> bool:
	return OS.has_feature("movie") or forced

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("movie"):
		_enter()

func _process(_delta: float) -> void:
	if not OS.has_feature("movie") or _frames_left < 0:
		return
	_frames_left -= 1
	if _frames_left <= 0:
		# Корректный выход: Movie Maker дописывает и закрывает файл.
		get_tree().quit()

# --- Вход и выход ---------------------------------------------------------

func _enter() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	set_layers(Layers.WORLD_ONLY)
	Game.cmd_set_speed(CAPTURE_SPEED)
	_suppress_autopause()
	if _frames_left < 0:
		_frames_left = DEFAULT_FRAMES

func _leave() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_layers(Layers.ALL)
	_restore_autopause()

# --- Слои -----------------------------------------------------------------

## Мир / только интерфейс / всё. Enum, а не bool: ролики про UI тоже нужны.
func set_layers(mode: Layers) -> void:
	layers = mode
	var main: Node = get_parent()
	if main == null:
		return
	var world_on: bool = mode != Layers.UI_ONLY
	var ui_on: bool = mode != Layers.WORLD_ONLY
	_set_visible(main, ^"WorldContainer", world_on)
	_set_visible(main, ^"WeatherLayer", world_on)
	_set_visible(main, ^"HUDLayer", ui_on)
	_set_visible(main, ^"PanelLayer", ui_on)
	_set_visible(main, ^"BannerLayer", ui_on)
	_set_visible(main, ^"ScreenLayer", ui_on)
	# Дебаг в кадре не нужен никогда — ни в одном режиме.
	_set_visible(main, ^"DebugLayer", false)
	layers_changed.emit(int(mode))

func _set_visible(main: Node, path: NodePath, on: bool) -> void:
	var n: Node = main.get_node_or_null(path)
	if n is CanvasItem:
		(n as CanvasItem).visible = on
	elif n is CanvasLayer:
		(n as CanvasLayer).visible = on

# --- Подбор кадра ---------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event.is_action_pressed("capture_layers"):
		set_layers(((int(layers) + 1) % Layers.size()) as Layers)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("capture_toggle"):
		forced = not forced
		if forced:
			_enter()
		else:
			_leave()
		get_viewport().set_input_as_handled()

# --- Автопауза ------------------------------------------------------------

## Драфт и Итог цикла зовут Game.push_pause(). Во время съёмки паузы быть не
## должно: карту берём первую, отчёт не показываем. Флаги настроек при этом
## запоминаем — режим съёмки не имеет права переписать настройки игрока.
func _suppress_autopause() -> void:
	if _autopause_hooked:
		return
	_autopause_hooked = true
	_saved_pauses = [Settings.pause_on_draft, Settings.pause_on_cycle,
		Settings.pause_on_crisis]
	Settings.pause_on_draft = false
	Settings.pause_on_cycle = false
	Settings.pause_on_crisis = false
	Events.draft_ready.connect(_auto_pick)

func _restore_autopause() -> void:
	if not _autopause_hooked:
		return
	_autopause_hooked = false
	if _saved_pauses.size() == 3:
		Settings.pause_on_draft = _saved_pauses[0]
		Settings.pause_on_cycle = _saved_pauses[1]
		Settings.pause_on_crisis = _saved_pauses[2]
	if Events.draft_ready.is_connected(_auto_pick):
		Events.draft_ready.disconnect(_auto_pick)

func _auto_pick(card_ids: Array[String]) -> void:
	if not card_ids.is_empty():
		Game.cmd_pick_card(card_ids[0])

# --- Повтор сцены по журналу ----------------------------------------------

## Перемотать забег к нужному тику и снимать оттуда — единственный способ
## снять «тот самый шторм» десять раз подряд одинаково.
##
## ⚠️ Сцена подбирается СИДОМ, а не флагом «отключить случайные события»:
## второй путь исполнения симуляции — прямой путь к расхождению, и снятый
## ролик перестал бы соответствовать игре.
func replay_to(seed_value: int, command_log: Array[Dictionary], target_tick: int,
		lead_ticks: int = 600) -> void:
	var from_tick: int = maxi(0, target_tick - lead_ticks)
	var w: SimWorld = SimWorld.replay(seed_value, command_log, from_tick,
		Game.cliff_def())
	if w == null:
		push_error("CaptureMode: повтор по журналу не собрался")
		return
	Game.world = w
	Game.rebroadcast_state()
	Game.cmd_set_speed(CAPTURE_SPEED)
