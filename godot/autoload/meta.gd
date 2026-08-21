extends Node
## Мета-профиль: Журнал забегов и разблокировки (docs/00 §11.3).
##
## ⚠️ Граница слоёв: sim НЕ читает Meta. Game берёт unlocked отсюда и передаёт
## в SimWorld.new_run; RunState хранит копию, и все проверки построек, карт
## и рецептов идут по ней.

const PROFILE_PATH: String = "user://profile.json"
const PROFILE_VERSION: int = 1

var points_total: int = 0
var unlocked: Array[String] = []
var relics_total: int = 0
## Статистика docs/00 §11.3.
var runs_played: int = 0
var runs_won: int = 0
var cycles_total: int = 0
var agents_lost: int = 0
var best_score: int = 0
## История забегов: {n, score, end, cycles, deaths: [{name, cause, bio}]}.
var history: Array[Dictionary] = []

var _dirty: bool = false

func _ready() -> void:
	# Автолоад с _notification должен работать и на паузе дерева.
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_profile()

func _process(_delta: float) -> void:
	# Дебаунс: без него экран итогов записал бы файл двадцать раз подряд.
	if _dirty:
		_dirty = false
		save_profile()

func mark_dirty() -> void:
	_dirty = true

# --- Разблокировки --------------------------------------------------------

func has_unlock(id: String) -> bool:
	return unlocked.has(id)

## Возвращает false, если уже куплено, нет такой разблокировки или не хватает
## очков.
func buy_unlock(id: String) -> bool:
	if unlocked.has(id) or not DB.has_unlock(id):
		return false
	var u: UnlockDef = DB.unlock(id)
	if points_total < u.cost:
		return false
	points_total -= u.cost
	unlocked.append(id)
	unlocked.sort()                 # детерминированный порядок в профиле
	mark_dirty()
	Events.unlock_gained.emit(id)
	return true

# --- Итог забега ----------------------------------------------------------

func record_run(report: Dictionary) -> void:
	runs_played += 1
	var score: int = int(report.get("score", 0))
	points_total += score
	best_score = maxi(best_score, score)
	cycles_total += int(report.get("cycles", 0))
	relics_total += int(report.get("relics", 0))
	var deaths: Array = report.get("deaths", []) as Array
	agents_lost += deaths.size()
	if int(report.get("end", 0)) == int(SimTypes.RunEnd.SHIP):
		runs_won += 1
	history.append({
		"n": runs_played, "score": score, "end": int(report.get("end", 0)),
		"cycles": int(report.get("cycles", 0)), "deaths": deaths.duplicate(true),
	})
	mark_dirty()

func stats() -> Dictionary:
	return {
		"runs_played": runs_played, "runs_won": runs_won,
		"cycles_total": cycles_total, "agents_lost": agents_lost,
		"best_score": best_score, "relics_total": relics_total,
		"points_total": points_total,
	}

# --- Файл -----------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"version": PROFILE_VERSION, "points_total": points_total,
		"unlocked": unlocked.duplicate(), "relics_total": relics_total,
		"runs_played": runs_played, "runs_won": runs_won,
		"cycles_total": cycles_total, "agents_lost": agents_lost,
		"best_score": best_score, "history": history.duplicate(true),
	}

func from_dict(d: Dictionary) -> void:
	# JSON отдаёт все числа как float — приводим каждое поле явно.
	points_total = int(d.get("points_total", 0))
	relics_total = int(d.get("relics_total", 0))
	runs_played = int(d.get("runs_played", 0))
	runs_won = int(d.get("runs_won", 0))
	cycles_total = int(d.get("cycles_total", 0))
	agents_lost = int(d.get("agents_lost", 0))
	best_score = int(d.get("best_score", 0))
	unlocked.clear()
	for v: Variant in d.get("unlocked", []) as Array:
		unlocked.append(str(v))
	history.clear()
	for h: Variant in d.get("history", []) as Array:
		var e: Dictionary = h as Dictionary
		history.append({
			"n": int(e.get("n", 0)), "score": int(e.get("score", 0)),
			"end": int(e.get("end", 0)), "cycles": int(e.get("cycles", 0)),
			"deaths": (e.get("deaths", []) as Array).duplicate(true),
		})

func save_profile() -> void:
	SaveIO.write_json(PROFILE_PATH, to_dict())

func load_profile() -> bool:
	var d: Dictionary = SaveIO.read_json(PROFILE_PATH)
	if d.is_empty():
		return false
	if int(d.get("version", 0)) != PROFILE_VERSION:
		push_warning("профиль версии %d, ожидалась %d — начинаем заново"
			% [int(d.get("version", 0)), PROFILE_VERSION])
		return false
	from_dict(d)
	return true

## Полный сброс профиля — только для дебага.
func wipe() -> void:
	points_total = 0
	relics_total = 0
	runs_played = 0
	runs_won = 0
	cycles_total = 0
	agents_lost = 0
	best_score = 0
	unlocked.clear()
	history.clear()
	save_profile()
