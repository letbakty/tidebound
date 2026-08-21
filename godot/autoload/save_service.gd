extends Node
## Сейв забега в JSON (docs/02 §6). Профиль пишет Meta — здесь только забег.
##
## Пользовательские файлы читаются ТОЛЬКО через JSON.parse: ResourceLoader,
## ConfigFile и str_to_var исполняют встроенный код и на пользовательском
## файле это дыра (docs/02 §10).

const RUN_PATH: String = "user://save_run.json"
## Журнал команд лежит ОТДЕЛЬНО от сейва (ARCH-08): сейв читается в меню при
## каждом запуске, а журнал нужен только для баг-репорта и воспроизведения.
## Внутри сейва он бы удорожал каждое чтение ради редкого сценария.
const COMMANDS_PATH: String = "user://save_commands.json"
const SAVE_VERSION: int = 1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Иначе окно закроется ДО нашего обработчика и забег потеряется.
	get_tree().set_auto_accept_quit(false)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			_save_all()
			get_tree().quit()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_save_all()
			get_tree().quit()
		NOTIFICATION_APPLICATION_PAUSED:
			# На iOS на всё про всё около пяти секунд: пишем синхронно.
			_save_all()

## ⚠️ Профиль пишется вместе с забегом, а не полагается на дебаунс Meta._process:
## между NOTIFICATION_WM_CLOSE_REQUEST и quit() кадра больше не будет, и
## _process в нём может не выполниться. Окно потери — одна покупка
## разблокировки или один итог забега (REL-03).
func _save_all() -> void:
	save_run()
	Meta.save_profile()

func has_save() -> bool:
	return FileAccess.file_exists(RUN_PATH)

func delete_run() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUN_PATH))
	if FileAccess.file_exists(COMMANDS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(COMMANDS_PATH))

## ui — секция интерфейса (показанные банеры и подсказки): её наполняют
## этапы 13 и 15, sim о ней не знает.
func save_run(ui: Dictionary = {}) -> bool:
	if Game.world == null or Game.world.run_state.finished:
		return false
	var data: Dictionary = {
		"save_version": SAVE_VERSION,
		"seed": Game.world.rng.seed_value,
		"world": Game.world.to_dict(),
		"ui": ui.duplicate(true),
	}
	# Журнал пишется только когда он ведётся (debug-сборка): в релизе файла
	# просто нет, и это не отказ.
	if not Game.world.command_log.is_empty():
		SaveIO.write_json(COMMANDS_PATH, Game.world.commands_to_dict())
	return SaveIO.write_json(RUN_PATH, data) == OK

## Возвращает false, если файла нет или он несовместим.
func load_run() -> bool:
	var d: Dictionary = SaveIO.read_json(RUN_PATH)
	if d.is_empty():
		return false
	var v: int = int(d.get("save_version", 0))
	if v != SAVE_VERSION:
		push_warning("сейв версии %d, ожидалась %d — загрузка отклонена"
			% [v, SAVE_VERSION])
		return false
	Game.restore_world(d.get("world", {}) as Dictionary)
	_load_commands(Game.world)
	return true

## Журнал команд после загрузки. Чужой журнал (от другого забега) молча не
## подставляем: сид обязан совпасть, иначе воспроизведение даст другой мир.
func _load_commands(world: SimWorld) -> void:
	if world == null:
		return
	var d: Dictionary = SaveIO.read_json(COMMANDS_PATH)
	if d.is_empty():
		return
	if int(d.get("seed", -1)) != world.rng.seed_value:
		push_warning("журнал команд от другого забега — не подставляем")
		return
	world.commands_from_dict(d)

## Короткая справка о сейве для меню: на каком цикле остановились и какой сид.
## Читает файл, а не мир: в меню мира ещё нет.
func saved_info() -> Dictionary:
	var d: Dictionary = SaveIO.read_json(RUN_PATH)
	if d.is_empty() or int(d.get("save_version", 0)) != SAVE_VERSION:
		return {}
	var world: Dictionary = d.get("world", {}) as Dictionary
	var clock: Dictionary = world.get("clock", {}) as Dictionary
	return {"cycle": int(clock.get("cycle", 1)), "seed": int(d.get("seed", 0))}

## Сейв есть и он читается: «Продолжить» на битом файле показывать нельзя
## (docs/03 §8).
func has_valid_save() -> bool:
	return not saved_info().is_empty()

func saved_ui() -> Dictionary:
	var d: Dictionary = SaveIO.read_json(RUN_PATH)
	return d.get("ui", {}) as Dictionary
