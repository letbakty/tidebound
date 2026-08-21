extends Node
## Сейв забега в JSON (docs/02 §6). Профиль пишет Meta — здесь только забег.
##
## Пользовательские файлы читаются ТОЛЬКО через JSON.parse: ResourceLoader,
## ConfigFile и str_to_var исполняют встроенный код и на пользовательском
## файле это дыра (docs/02 §10).

const RUN_PATH: String = "user://save_run.json"
const SAVE_VERSION: int = 1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Иначе окно закроется ДО нашего обработчика и забег потеряется.
	get_tree().set_auto_accept_quit(false)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			save_run()
			get_tree().quit()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			save_run()
			get_tree().quit()
		NOTIFICATION_APPLICATION_PAUSED:
			# На iOS на всё про всё около пяти секунд: пишем синхронно.
			save_run()

func has_save() -> bool:
	return FileAccess.file_exists(RUN_PATH)

func delete_run() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUN_PATH))

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
	return true

func saved_ui() -> Dictionary:
	var d: Dictionary = SaveIO.read_json(RUN_PATH)
	return d.get("ui", {}) as Dictionary
