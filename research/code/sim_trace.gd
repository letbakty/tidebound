class_name SimTrace
extends RefCounted
## Трассировка решений симуляции: почему агент выбрал эту задачу и почему
## станция стоит. Переносить в res://sim/sim_trace.gd.
##
## ⚠️ Единственная уступка правилу «sim ничего не знает о внешнем мире»:
## sim зовёт статический приёмник. Допустима, потому что приёмник — чистые
## данные, без нод, без Time.* и без файлового ввода-вывода.
##
## ⚠️ Выключен по умолчанию. При выключенном НЕ ДОЛЖНО быть ни одного
## форматирования строки в горячем пути: `if SimTrace.enabled:` ставится
## ПЕРЕД конкатенацией, а не внутри функции (research/43 §4.3).

static var enabled: bool = false

## Кольцевой буфер, а не файл: за забег иначе набежит десяток мегабайт.
const CAPACITY: int = 500
static var _lines: Array[String] = []

static func clear() -> void:
	_lines.clear()

static func lines() -> Array[String]:
	return _lines.duplicate()

static func _push(s: String) -> void:
	_lines.append(s)
	if _lines.size() > CAPACITY:
		_lines.remove_at(0)

# --- Выбор задачи ---------------------------------------------------------

## candidates: [{id, kind, score, reject}] — reject пустой у победителя.
## Зовётся из JobSystem._best_job_for ТОЛЬКО при enabled.
static func job_choice(agent_id: int, tick: int, candidates: Array, chosen: int) -> void:
	if not enabled:
		return
	var head: String = "т%d агент %d " % [tick, agent_id]
	if chosen < 0:
		_push(head + "не выбрал ничего (кандидатов: %d)" % candidates.size())
	else:
		for c: Dictionary in candidates:
			if int(c["id"]) == chosen:
				_push(head + "выбрал job#%d (%s, score %d)" % [
					chosen, str(c["kind"]), int(c["score"])])
				break
	for c2: Dictionary in candidates:
		if int(c2["id"]) == chosen:
			continue
		var reason: String = str(c2.get("reject", ""))
		if reason.is_empty():
			continue
		_push("    отброшено job#%d %s score %d — %s" % [
			int(c2["id"]), str(c2["kind"]), int(c2["score"]), reason])

# --- Причины простоя станции ----------------------------------------------

## Пишется ТОЛЬКО на смену значения: idle_reason считается каждый тик,
## а интересен момент, когда он изменился (research/43 §4.2).
static func station(building_id: int, tick: int, reason: String) -> void:
	if not enabled:
		return
	_push("т%d станция %d: %s" % [tick, building_id, reason if not reason.is_empty() else "работает"])

# --- Смена состояния агента -----------------------------------------------

static func agent_state(agent_id: int, tick: int, from_state: int, to_state: int) -> void:
	if not enabled:
		return
	_push("т%d агент %d: %d → %d" % [tick, agent_id, from_state, to_state])

# --- Выгрузка -------------------------------------------------------------

static func dump(path: String = "user://trace.log") -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("SimTrace: не записан %s" % path)
		return
	f.store_string("\n".join(_lines))
	f.close()
