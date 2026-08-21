class_name ScreenRouter
extends Control
## Роутер экранов: Boot → MainMenu → Game → (Итог → Журнал) → MainMenu
## (docs/03 §2).
##
## ⚠️ Переключение ВИДИМОСТЬЮ, а не change_scene_to_*: пересоздание игровой
## сцены убило бы состояние забега и все кэши виджетов (research/22 §1).
## Мир под полупрозрачным окном итога остаётся живым — это и нужно.

signal screen_changed(screen: int)

enum Screen { BOOT, FIRST_LAUNCH, MAIN_MENU, GAME, JOURNAL, SETTINGS, CREDITS }
## Модальные окна забега: игра видна, но на паузе (docs/03 §1).
enum Modal { NONE, DRAFT, CYCLE_SUMMARY, RUN_SUMMARY, PAUSE, ERROR }

var current: Screen = Screen.BOOT
var modal: Modal = Modal.NONE

var _screens: Dictionary[int, ScreenBase] = {}
var _modals: Dictionary[int, Control] = {}
## Куда вернуться из Настроек: они открываются и из меню, и из паузы.
var _settings_return: Screen = Screen.MAIN_MENU
var _paused_by_modal: bool = false

## Мир и слои игры принадлежат Main; роутер только показывает и прячет их.
var _world: CanvasItem = null
var _hud: CanvasLayer = null
var _panels: CanvasLayer = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

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
	close_modal()
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
	screen_changed.emit(int(screen))

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
## (docs/03 §1). pause=true — окно само просит автопаузу.
func open_modal(kind: Modal, args: Dictionary = {}, pause: bool = true) -> void:
	if kind == Modal.NONE:
		return
	close_modal()
	var node: Control = _modals.get(int(kind), null)
	if node == null:
		return
	modal = kind
	if node.has_method("open_with"):
		node.call("open_with", args)
	node.visible = true
	if node.has_method("grab_initial_focus"):
		node.call("grab_initial_focus")
	if pause:
		_paused_by_modal = true
		Game.push_pause()

func close_modal() -> void:
	if modal == Modal.NONE:
		return
	var node: Control = _modals[int(modal)]
	node.visible = false
	if node.has_method("on_closed"):
		node.call("on_closed")
	modal = Modal.NONE
	if _paused_by_modal:
		_paused_by_modal = false
		Game.pop_pause()

func is_modal_open() -> bool:
	return modal != Modal.NONE
