class_name ScreenRouter
extends Control
## Роутер экранов: Boot → MainMenu → Game → (Итог → Журнал) → MainMenu
## (docs/03 §2).
##
## ⚠️ Переключение ВИДИМОСТЬЮ, а не change_scene_to_*: пересоздание игровой
## сцены убило бы состояние забега и все кэши виджетов (research/22 §1).
## Мир под полупрозрачным окном итога остаётся живым — это и нужно.

signal screen_changed(screen: int)

## NONE — сентинел «экрана ещё нет». Без него первый же goto(BOOT) выходил
## по ветке «уже там», on_enter не звался и игрок смотрел в чёрный экран
## (аудит B1.2). Значение −1, чтобы номера остальных экранов не поехали.
enum Screen { NONE = -1, BOOT, FIRST_LAUNCH, MAIN_MENU, GAME, JOURNAL, SETTINGS, CREDITS }
## Модальные окна забега: игра видна, но на паузе (docs/03 §1).
enum Modal { NONE, DRAFT, CYCLE_SUMMARY, RUN_SUMMARY, PAUSE, ERROR }

## Окна забега: показываются только поверх игры. Всё остальное (ErrorDialog)
## имеет право открыться на любом экране.
const GAME_MODALS: Array[int] = [int(Modal.DRAFT), int(Modal.CYCLE_SUMMARY),
	int(Modal.RUN_SUMMARY), int(Modal.PAUSE)]
## Окно, ради которого закрывают всё остальное: забег кончился, и Итог цикла
## поверх него уже не нужен (docs/03 §8).
const PREEMPTING: Array[int] = [int(Modal.RUN_SUMMARY), int(Modal.ERROR)]

var current: Screen = Screen.NONE
var modal: Modal = Modal.NONE

var _screens: Dictionary[int, ScreenBase] = {}
var _modals: Dictionary[int, Control] = {}
## Куда вернуться из Настроек: они открываются и из меню, и из паузы.
var _settings_return: Screen = Screen.MAIN_MENU
## Автопауза текущего модального окна: снимается при ЛЮБОМ его закрытии —
## и по кнопке, и когда окно вытеснили. Считает и свою паузу (pause), и
## «унаследованную» от Game (adopt) — иначе вытесненное окно уносило бы
## снятие паузы с собой.
var _modal_pause: bool = false
## Очередь модальных окон. cycle_ended и draft_ready приходят из sim ОДНИМ
## батчем, и драфт обязан ждать, пока игрок закроет Итог цикла: раньше он
## молча закрывал Итог, и единственный pop_pause того уровня не нажимался —
## после драфта игра оставалась на паузе навсегда (docs/03 §1, аудит B1.4).
var _queue: Array[Dictionary] = []
## Мир скрыт экраном — тик выключен флагом Game.world_hidden, а не автопаузой
## (см. комментарий там же).

## Мир и слои игры принадлежат Main; роутер только показывает и прячет их.
var _world: CanvasItem = null
var _hud: CanvasLayer = null
var _panels: CanvasLayer = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Роутер уходит из дерева — свои автопаузы он обязан унести с собой:
## счётчик в Game переживает сцену, и оставленная пауза застряла бы навсегда.
func _exit_tree() -> void:
	_close_current_modal()
	_drop_queue()
	Game.world_hidden = false

func setup_layers(world: CanvasItem, hud: CanvasLayer, panels: CanvasLayer) -> void:
	_world = world
	_hud = hud
	_panels = panels

func register(screen: Screen, node: ScreenBase) -> void:
	_screens[int(screen)] = node
	node.visible = false
	add_child(node)

func register_modal(kind: Modal, node: Control) -> void:
	_modals[int(kind)] = node
	node.visible = false
	add_child(node)

func screen_node(screen: Screen) -> ScreenBase:
	return _screens.get(int(screen), null)

func modal_node(kind: Modal) -> Control:
	return _modals.get(int(kind), null)

# --- Экраны ---------------------------------------------------------------

func goto(screen: Screen, args: Dictionary = {}) -> void:
	if screen == current and screen != Screen.GAME:
		return
	# Без chaining: очередь модалок разбираем в конце, когда новый экран уже
	# на месте — иначе окно забега открылось бы поверх главного меню.
	_close_current_modal()
	var prev: ScreenBase = _screens.get(int(current), null)
	if prev != null:
		prev.visible = false
		prev.on_exit()
	current = screen
	var next: ScreenBase = _screens.get(int(screen), null)
	if next != null:
		next.on_enter(args)
		next.visible = true
		next.grab_initial_focus()
	_apply_game_visibility()
	_apply_world_gate()
	screen_changed.emit(int(screen))
	_open_next()

## Мир скрыт экраном — он обязан ещё и СТОЯТЬ. Иначе под главным меню агенты
## тонут в фоне, автосейв переписывает сейв, а run_ended открывает Итог забега
## поверх меню (аудит B1.5).
func _apply_world_gate() -> void:
	Game.world_hidden = current != Screen.GAME

## Мир и HUD видны ТОЛЬКО в игре: экран прячет их целиком (docs/03 §1).
func _apply_game_visibility() -> void:
	var in_game: bool = current == Screen.GAME
	if _world != null:
		_world.visible = in_game
	if _hud != null:
		_hud.visible = in_game
	if _panels != null:
		_panels.visible = in_game

func open_settings_from(screen: Screen) -> void:
	_settings_return = screen
	goto(Screen.SETTINGS)

func settings_return() -> Screen:
	return _settings_return

# --- Модальные окна -------------------------------------------------------

## Модальное окно открывается только поверх игры и закрывает панель
## (docs/03 §1).
##
## pause=true  — окно само просит автопаузу и само её снимет.
## adopt=true  — паузу за это окно уже поставил Game (итог цикла, драфт);
##               роутер обязан снять её при закрытии окна любым способом.
##
## Занято — окно встаёт В ОЧЕРЕДЬ, а не вытесняет открытое: два модальных
## подряд не должны снять паузу раньше времени (docs/03 §1).
func open_modal(kind: Modal, args: Dictionary = {}, pause: bool = true,
		adopt: bool = false) -> void:
	if kind == Modal.NONE:
		return
	var item: Dictionary = {"kind": int(kind), "args": args,
		"pause": pause, "adopt": adopt}
	# Окно забега вне игры не показывается ни при каких условиях: модальное
	# поверх экрана — прямой запрет docs/03 §1.
	var off_screen: bool = GAME_MODALS.has(int(kind)) and current != Screen.GAME
	if PREEMPTING.has(int(kind)):
		_drop_queue()                   # забег кончился: Итог цикла уже неважен
		if off_screen:
			_enqueue(item)
			return
		_close_current_modal()
	elif off_screen or modal != Modal.NONE:
		# Ждать своей очереди — в том числе возвращения игрока в игру:
		# драфт после «Продолжить» показывается снова (docs/03 §8).
		_enqueue(item)
		return
	_show_modal(item)

## Одно окно каждого вида, не стопка копий: rebroadcast_state после промотки
## заново шлёт draft_ready, и без этого драфт вставал бы в очередь сам за собой
## (а «унаследованная» автопауза копилась бы вместе с ним).
func _enqueue(item: Dictionary) -> void:
	if int(item["kind"]) == int(modal):
		_release_pause(item)            # это окно уже на экране
		return
	for q: Dictionary in _queue:
		if int(q["kind"]) == int(item["kind"]):
			_release_pause(item)
			return
	_queue.append(item)

func _show_modal(item: Dictionary) -> void:
	var kind: Modal = int(item["kind"]) as Modal
	var node: Control = _modals.get(int(kind), null)
	if node == null:
		_release_pause(item)
		return
	modal = kind
	if node.has_method("open_with"):
		node.call("open_with", item["args"] as Dictionary)
	node.visible = true
	if node.has_method("grab_initial_focus"):
		node.call("grab_initial_focus")
	if bool(item["pause"]):
		Game.push_pause()
	_modal_pause = bool(item["pause"]) or bool(item["adopt"])

func close_modal() -> void:
	_close_current_modal()
	_open_next()

func _close_current_modal() -> void:
	if modal == Modal.NONE:
		return
	var node: Control = _modals[int(modal)]
	node.visible = false
	if node.has_method("on_closed"):
		node.call("on_closed")
	modal = Modal.NONE
	if _modal_pause:
		_modal_pause = false
		Game.pop_pause()

func _open_next() -> void:
	if modal != Modal.NONE or _queue.is_empty():
		return
	var item: Dictionary = _queue[0]
	if GAME_MODALS.has(int(item["kind"])) and current != Screen.GAME:
		return                          # дождётся возвращения в игру
	_queue.remove_at(0)
	_show_modal(item)

## Выброшенное из очереди окно уносит с собой и свою автопаузу.
func _drop_queue() -> void:
	for item: Dictionary in _queue:
		_release_pause(item)
	_queue.clear()

func _release_pause(item: Dictionary) -> void:
	if bool(item["adopt"]):
		Game.pop_pause()

func is_modal_open() -> bool:
	return modal != Modal.NONE

func queued_modals() -> int:
	return _queue.size()
