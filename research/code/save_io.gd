class_name SaveIO
extends RefCounted
## Атомарное чтение/запись JSON для сейвов. Переносить в res://autoload/save_io.gd
## или встроить в save_service.gd (этап 11).
##
## Почему так, а не FileAccess.store_string напрямую — research/18 §4:
## обрыв записи (закрытие игры, разряд батареи) оставляет обрезанный файл.
##
## БЕЗОПАСНОСТЬ (docs/02 §6, §10): пользовательские файлы читаются ТОЛЬКО через
## JSON.parse. Никаких ResourceLoader / ConfigFile / get_var(true) / str_to_var.

const TMP_SUFFIX: String = ".tmp"

## full_precision=true ОБЯЗАТЕЛЕН для сейва: дефолт false усекает float,
## и продолжение симуляции после загрузки разойдётся с непрерывным прогоном.
static func write_json(path: String, data: Dictionary) -> Error:
	var text: String = JSON.stringify(data, "", true, true)
	var tmp: String = path + TMP_SUFFIX
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		var e: Error = FileAccess.get_open_error()
		push_error("сейв: не открыт %s (%d)" % [tmp, e])
		return e
	f.store_string(text)
	f.flush()
	f.close()                       # обязательно ДО переименования
	var err: Error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(tmp),
		ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("сейв: rename %s -> %s не удался (%d)" % [tmp, path, err])
	return err

## Возвращает пустой словарь при любой проблеме. Битый файл уводится в карантин:
## удалять его нельзя — он нужен для баг-репорта.
static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("сейв не читается: %d" % FileAccess.get_open_error())
		return {}
	var text: String = f.get_as_text()
	f.close()

	# Инстанс-версия JSON (не parse_string): даёт номер строки и текст ошибки.
	var p := JSON.new()
	if p.parse(text) != OK:
		push_warning("битый сейв %s, строка %d: %s" % [path, p.get_error_line(), p.get_error_message()])
		quarantine(path)
		return {}
	if typeof(p.data) != TYPE_DICTIONARY:
		push_warning("сейв %s: корень не словарь" % path)
		quarantine(path)
		return {}
	return p.data as Dictionary

static func quarantine(path: String) -> void:
	var dst: String = path.get_basename() + ".corrupt" + path.get_extension().insert(0, ".")
	DirAccess.rename_absolute(
		ProjectSettings.globalize_path(path),
		ProjectSettings.globalize_path(dst))

# --- Хелперы сериализации Godot-типов ------------------------------------
# JSON не знает Vector2i, NAN и int: всё приводится вручную.

static func v2i_to_arr(v: Vector2i) -> Array:
	return [v.x, v.y]

static func arr_to_v2i(a: Variant) -> Vector2i:
	if typeof(a) != TYPE_ARRAY or (a as Array).size() < 2:
		return Vector2i.ZERO
	return Vector2i(int((a as Array)[0]), int((a as Array)[1]))

## NAN/INF не сериализуются в JSON ("non-finite numbers are not supported").
static func f_or_null(v: float) -> Variant:
	return null if not is_finite(v) else v

static func null_or_f(v: Variant, fallback: float = NAN) -> float:
	return fallback if v == null else float(v)

## JSON.parse возвращает ВСЕ числа как float. Любой int надо приводить явно.
static func to_int_array(v: Variant) -> Array[int]:
	var out: Array[int] = []
	if typeof(v) != TYPE_ARRAY:
		return out
	for x: Variant in (v as Array):
		out.append(int(x))
	return out

## Рекурсивная проверка на NAN/INF — страховка для теста этапа 19.
static func find_non_finite(d: Variant, path: String = "") -> Array[String]:
	var bad: Array[String] = []
	match typeof(d):
		TYPE_FLOAT:
			if not is_finite(d):
				bad.append(path)
		TYPE_DICTIONARY:
			for k: Variant in (d as Dictionary):
				bad.append_array(find_non_finite((d as Dictionary)[k], path + "/" + str(k)))
		TYPE_ARRAY:
			for i: int in (d as Array).size():
				bad.append_array(find_non_finite((d as Array)[i], path + "[%d]" % i))
	return bad
