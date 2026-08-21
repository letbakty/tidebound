class_name Telemetry
extends Node
## Локальная телеметрия плейтеста. Переносить в res://autoload/telemetry.gd
## и включать ТОЛЬКО в пресете с feature-тегом "playtest" (research/37 §5.3).
##
## Сервера нет и не будет: пишем CSV в user://, тестер присылает файлом.
## Формат колонок совпадает с sweep-раннером баланса (research/30 §4), чтобы
## данные людей и ботов сравнивались одной строкой в pandas.
##
## ⚠️ Ничего не отправляется автоматически. Согласие спрашивается один раз
## и запоминается в Settings.

const DIR: String = "user://telemetry/"
const KEEP_FILES: int = 20
const HEADER: String = "t_unix,tick,cycle,phase,event,a,b,c"

var enabled: bool = false
var _path: String = ""
var _file: FileAccess = null
var _started_unix: int = 0

# --- Жизненный цикл --------------------------------------------------------

func _ready() -> void:
	if not OS.has_feature("playtest"):
		queue_free()                      # в релизной сборке телеметрии нет
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	enabled = bool(Settings.get("telemetry_enabled")) if Settings != null else false
	if enabled:
		_open()
	_connect_events()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		log_event("session_end", "quit", str(_session_seconds()), "")
		_close()

func set_enabled(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	if on:
		_open()
	else:
		_close()

func _open() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_prune()
	_started_unix = int(Time.get_unix_time_from_system())
	var seed_str: String = "0" if Game.world == null else str(Game.world.rng.seed_value)
	_path = "%ssession_%d_%s.csv" % [DIR, _started_unix, seed_str]
	_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file == null:
		enabled = false
		return
	_file.store_line(HEADER)
	log_event("session_start",
		str(ProjectSettings.get_setting("application/config/version", "0.0.0")),
		OS.get_name(),
		"%dx%d" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y])

func _close() -> void:
	if _file != null:
		_file.flush()
		_file.close()
		_file = null

func _session_seconds() -> int:
	return int(Time.get_unix_time_from_system()) - _started_unix

# --- Запись ---------------------------------------------------------------

## Три обобщённых поля вместо схемы на каждое событие: иначе CSV превращается
## в разреженную матрицу из сорока колонок (research/37 §2.1).
func log_event(event: String, a: String = "", b: String = "", c: String = "") -> void:
	if not enabled or _file == null:
		return
	var tick: int = 0
	var cycle: int = 0
	var phase: int = 0
	if Game.world != null:
		tick = Game.world.clock.total_ticks()
		cycle = Game.world.clock.cycle
		phase = int(Game.world.clock.phase)
	_file.store_line("%d,%d,%d,%d,%s,%s,%s,%s" % [
		int(Time.get_unix_time_from_system()), tick, cycle, phase,
		event, _csv(a), _csv(b), _csv(c)])
	# ⚠️ flush на каждой строке: последние строки перед крашем — самые ценные.
	_file.flush()

static func _csv(s: String) -> String:
	if s.contains(",") or s.contains("\"") or s.contains("\n"):
		return "\"%s\"" % s.replace("\"", "\"\"")
	return s

# --- Подписки -------------------------------------------------------------

func _connect_events() -> void:
	Events.run_started.connect(func(sv: int) -> void:
		log_event("run_start", str(sv), str(Meta.unlocked.size()), ""))
	Events.run_ended.connect(func(r: Dictionary) -> void:
		log_event("run_end", str(r.get("end", -1)), str(r.get("cycles", 0)),
			str(r.get("score", 0))))
	Events.cycle_ended.connect(func(r: Dictionary) -> void:
		log_event("cycle_end", str(r.get("agents_alive", 0)),
			str(r.get("gathered", {})), str(r.get("produced", {}))))
	Events.agent_died.connect(func(id: int, cause: String) -> void:
		log_event("agent_died", str(id), cause, ""))
	Events.policy_changed.connect(func(p: int, v: int) -> void:
		log_event("policy_changed", str(p), str(v), ""))
	Events.beacon_moved.connect(func(cell: Vector2i) -> void:
		log_event("beacon_moved", str(cell.x), str(cell.y), ""))
	Events.building_placed.connect(func(id: int) -> void:
		var b: Dictionary = Game.query_building(id)
		log_event("building_placed", str(b.get("def_id", "")), str(id), ""))
	Events.card_picked.connect(func(card: String) -> void:
		log_event("card_picked", card, "", ""))
	Events.recall_issued.connect(func(hard: bool) -> void:
		log_event("recall_issued", str(hard), "", ""))
	Events.speed_changed.connect(func(m: int) -> void:
		log_event("speed_changed", str(m), "", ""))
	Events.ui_panel_opened.connect(func(name: String) -> void:
		log_event("panel_opened", name, "", ""))

# --- Файлы ----------------------------------------------------------------

func _prune() -> void:
	var dir: DirAccess = DirAccess.open(DIR)
	if dir == null:
		return
	var names: PackedStringArray = dir.get_files()
	if names.size() <= KEEP_FILES:
		return
	names.sort()
	for i: int in names.size() - KEEP_FILES:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + names[i]))

## Кнопка «Отправить данные плейтеста» в настройках.
func reveal() -> void:
	_close()
	DisplayServer.clipboard_set("TIDEBOUND playtest: %s" % _path.get_file())
	if not OS.has_feature("mobile"):
		OS.shell_open(ProjectSettings.globalize_path(DIR))
	if enabled:
		_open()
