class_name SimDump
extends RefCounted
## Плоский снимок мира и читаемый дифф. Переносить в res://tests/sim_dump.gd
## (нужен и тестам, и дебаг-панели).
##
## Зачем: to_dict() даёт полный снимок, но глазами его не сравнить — несколько
## сотен строк, из которых на каждом тике меняются десятки шумовых полей
## (research/43 §2.1). Здесь снимок разворачивается в плоские пути и
## сравнивается с маской шума.

## Пути, которые дифф игнорирует по умолчанию. "*" — любой сегмент.
## Это ровно те поля, что меняются каждый тик и топят полезное.
const NOISE: Array[String] = [
	"agents/*/x", "agents/*/target_x", "agents/*/goto_x",
	"agents/*/need_rem/*", "agents/*/state_ticks", "agents/*/last_update",
	"agents/*/work_ticks", "agents/*/climb_t", "agents/*/path/*",
	"clock/total_ticks", "clock/tick_in_phase",
	"tide/ticks_since_emit", "tide/last_emitted",
	"rng/state",
]

## Изменения float меньше этого не показываются: всё квантовано до 1e-4
## (Balance.quant), поэтому порог безопасен.
const FLOAT_EPS: float = 0.01

# --- Снимок ---------------------------------------------------------------

## Мир -> {"buildings/4/buffer/salt": 1, ...}
static func flat(world: Object) -> Dictionary:
	var out: Dictionary = {}
	_walk(world.call("to_dict"), "", out)
	return out

static func _walk(v: Variant, path: String, out: Dictionary) -> void:
	match typeof(v):
		TYPE_DICTIONARY:
			for k: Variant in (v as Dictionary):
				_walk((v as Dictionary)[k], _join(path, str(k)), out)
		TYPE_ARRAY:
			var arr: Array = v as Array
			for i: int in arr.size():
				# Массивы объектов индексируются по полю id, если оно есть:
				# иначе вставка в середину сдвигает все пути и дифф врёт.
				var key: String = str(i)
				if typeof(arr[i]) == TYPE_DICTIONARY and (arr[i] as Dictionary).has("id"):
					key = str((arr[i] as Dictionary)["id"])
				_walk(arr[i], _join(path, key), out)
		_:
			out[path] = v

static func _join(a: String, b: String) -> String:
	return b if a.is_empty() else a + "/" + b

# --- Дифф -----------------------------------------------------------------

## Возвращает {path: [было, стало]}. full=true отключает маску шума.
static func diff(a: Dictionary, b: Dictionary, full: bool = false) -> Dictionary:
	var out: Dictionary = {}
	var keys: Dictionary = {}
	for k: Variant in a:
		keys[k] = true
	for k2: Variant in b:
		keys[k2] = true
	var sorted: Array[String] = []
	sorted.assign(keys.keys())
	sorted.sort()
	for path: String in sorted:
		if not full and _is_noise(path):
			continue
		var was: Variant = a.get(path, null)
		var now: Variant = b.get(path, null)
		if _same(was, now):
			continue
		out[path] = [was, now]
	return out

static func _same(x: Variant, y: Variant) -> bool:
	if typeof(x) == TYPE_FLOAT and typeof(y) == TYPE_FLOAT:
		return absf(float(x) - float(y)) < FLOAT_EPS
	return x == y

static func _is_noise(path: String) -> bool:
	for pattern: String in NOISE:
		if _match_path(path, pattern):
			return true
	return false

## Сравнение по сегментам: "*" — любой ОДИН сегмент.
static func _match_path(path: String, pattern: String) -> bool:
	var p: PackedStringArray = path.split("/")
	var q: PackedStringArray = pattern.split("/")
	if p.size() != q.size():
		return false
	for i: int in q.size():
		if q[i] != "*" and q[i] != p[i]:
			return false
	return true

# --- Печать ---------------------------------------------------------------

## Дифф, сгруппированный по системам: сразу видно, ГДЕ изменилось,
## ещё до чтения строк.
static func diff_text(a: Dictionary, b: Dictionary, full: bool = false) -> String:
	var d: Dictionary = diff(a, b, full)
	if d.is_empty():
		return "(различий нет)"
	var groups: Dictionary = {}
	var paths: Array[String] = []
	paths.assign(d.keys())
	paths.sort()
	for path: String in paths:
		var head: String = path.split("/")[0]
		if not groups.has(head):
			groups[head] = [] as Array[String]
		var rest: String = path.substr(head.length() + 1) if path.length() > head.length() else path
		(groups[head] as Array[String]).append("  %-28s %s → %s" % [
			rest, _fmt(d[path][0]), _fmt(d[path][1])])
	var out: PackedStringArray = []
	var heads: Array[String] = []
	heads.assign(groups.keys())
	heads.sort()
	for h: String in heads:
		out.append("[%s]" % h)
		out.append_array(groups[h] as Array[String])
	return "\n".join(out)

static func _fmt(v: Variant) -> String:
	if v == null:
		return "—"
	if typeof(v) == TYPE_FLOAT:
		return "%.4f" % float(v)
	return str(v)
