class_name CrashReport
extends RefCounted
## Пакет для баг-репорта: версия + сид + цикл + последние события + лог.
## Переносить в res://autoload/crash_report.gd (этап 15), кнопка — в меню паузы
## и в настройках.
##
## Почему не Sentry: для соло-проекта «одна кнопка → файл, который игрок сам
## пришлёт» покрывает почти ту же пользу, не требует сервера, согласия и
## обязательств перед площадками (research/36 §3).
##
## ⚠️ Ничего не отправляется по сети. Отправку решает игрок.

const DIR: String = "user://reports/"
const EVENT_BUFFER: int = 30
const LOG_TAIL_LINES: int = 100

static var _events: Array[String] = []

# --- Сбор ------------------------------------------------------------------

## Кольцевой буфер последних событий Events. Заполняет дебаг-панель (этап 03)
## или отдельный подписчик; здесь только хранение.
static func note_event(line: String) -> void:
	_events.append(line)
	if _events.size() > EVENT_BUFFER:
		_events.remove_at(0)

static func build(user_text: String = "") -> Dictionary:
	var d: Dictionary = {
		"kind": "tidebound_report",
		"report_version": 1,
		"game_version": str(ProjectSettings.get_setting("application/config/version", "0.0.0")),
		"engine": Engine.get_version_info(),
		"platform": {
			"os": OS.get_name(),
			"cpu": OS.get_processor_name(),
			"gpu": RenderingServer.get_video_adapter_name(),
			"window": SimTypes.v2i_to_arr(DisplayServer.window_get_size()),
			"locale": TranslationServer.get_locale(),
		},
		"user_text": user_text,
		"events": _events.duplicate(),
		"log_tail": _log_tail(),
	}
	d.merge(_run_section(), true)
	return d

## Состояние забега — самая ценная часть: сид + тик воспроизводят ситуацию.
static func _run_section() -> Dictionary:
	if Game.world == null:
		return {"run": null}
	var w: SimWorld = Game.world
	return {
		"run": {
			"seed": str(w.rng.seed_value),          # строкой: 64 бита не переживают JSON-число
			"tick": w.clock.total_ticks(),
			"cycle": w.clock.cycle,
			"phase": SimTypes.phase_name(int(w.clock.phase)),
			"water": w.tide.level,
			"agents_alive": w.agents.alive_count(),
			"buildings": w.buildings.order.size(),
			"policies": w.policies.to_dict(),
			"speed": Game.speed,
			"error_count": Game.error_count(),
			# ⚠️ Журнал команд — то, чего нет ни у одного стороннего сервиса:
			# сид + журнал = полное воспроизведение забега (research/25 §2.1).
			"command_log": w.command_log.duplicate(true),
		}
	}

## Хвост встроенного лога Godot (debug/file_logging/*).
static func _log_tail() -> Array[String]:
	var out: Array[String] = []
	var path: String = str(ProjectSettings.get_setting(
		"debug/file_logging/log_path", "user://logs/godot.log"))
	if not FileAccess.file_exists(path):
		return out
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var all: PackedStringArray = f.get_as_text().split("\n")
	f.close()
	var from: int = maxi(0, all.size() - LOG_TAIL_LINES)
	for i: int in range(from, all.size()):
		out.append(_scrub(all[i]))
	return out

## ⚠️ Абсолютные пути содержат имя пользователя ОС — это персональные данные
## (research/36 §4.2). Вырезаем домашнюю папку из любой строки.
static func _scrub(line: String) -> String:
	var home: String = OS.get_environment("HOME")
	if home.is_empty():
		home = OS.get_environment("USERPROFILE")
	if not home.is_empty():
		line = line.replace(home, "~")
	var user_dir: String = ProjectSettings.globalize_path("user://")
	if not user_dir.is_empty():
		line = line.replace(user_dir, "user://")
	return line

# --- Отдача игроку ---------------------------------------------------------

## Пишет файл, открывает папку, кладёт короткую сводку в буфер обмена.
## Возвращает путь к файлу или "" при ошибке.
static func save_and_reveal(user_text: String = "") -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var d: Dictionary = build(user_text)
	var stamp: int = int(Time.get_unix_time_from_system())
	var path: String = "%sreport_%d.json" % [DIR, stamp]
	# indent="\t": файл читаемый — игрок должен иметь возможность его открыть.
	var text: String = JSON.stringify(d, "\t", true, true)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("CrashReport: не записан %s (%d)" % [path, FileAccess.get_open_error()])
		return ""
	f.store_string(text)
	f.close()

	DisplayServer.clipboard_set(summary(d))
	# ⚠️ На мобилках папку не открыть — там остаётся только буфер обмена.
	if not OS.has_feature("mobile"):
		OS.shell_open(ProjectSettings.globalize_path(DIR))
	return path

## Короткая сводка для вставки в Discord: длинный JSON туда не влезет.
static func summary(d: Dictionary) -> String:
	var run: Variant = d.get("run", null)
	var head: String = "TIDEBOUND %s / %s / %s" % [
		str(d["game_version"]),
		str((d["platform"] as Dictionary)["os"]),
		str((d["platform"] as Dictionary)["gpu"]),
	]
	if run == null:
		return head + "\n(вне забега)"
	var r: Dictionary = run as Dictionary
	return "%s\nсид %s, цикл %d, фаза %s, тик %d\nживых %d, построек %d, ошибок %d" % [
		head, str(r["seed"]), int(r["cycle"]), str(r["phase"]), int(r["tick"]),
		int(r["agents_alive"]), int(r["buildings"]), int(r["error_count"]),
	]

## Есть ли свежий лог с падением, о котором стоит спросить при запуске.
## ⚠️ Автоматически показывать репорт ПОСЛЕ краша нельзя — процесс уже мёртв;
## спрашиваем при следующем старте.
static func has_unreported_crash() -> bool:
	var log_path: String = str(ProjectSettings.get_setting(
		"debug/file_logging/log_path", "user://logs/godot.log"))
	if not FileAccess.file_exists(log_path):
		return false
	var log_time: int = FileAccess.get_modified_time(log_path)
	var last: int = 0
	var dir: DirAccess = DirAccess.open(DIR)
	if dir != null:
		for f: String in dir.get_files():
			last = maxi(last, FileAccess.get_modified_time(DIR + f))
	return log_time > last
