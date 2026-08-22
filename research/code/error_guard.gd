class_name ErrorGuard
extends Logger
## Ловит ошибки движка и рантайм-ошибки скриптов. Переносить в
## res://tests/error_guard.gd и регистрировать в run_all.gd ДО прогона сьютов.
##
## Зачем: buffer_take падал на КАЖДОМ вызове одиннадцать этапов подряд —
## 365 SCRIPT ERROR за прогон при полностью зелёном отчёте. Раннер проверяет
## только свои check(); stderr для него невидим (docs/BUG-salt-chain.md).
##
## Требует Godot 4.5+ (класс Logger, OS.add_logger).
## ⚠️ Сигнатуры _log_error/_log_message уточнялись между 4.5 и 4.6 —
## сверить по class reference своей версии перед переносом.
##
## ⚠️ Док прямо предупреждает: логгер вызывается ИЗ ДРУГИХ ПОТОКОВ.
## Внутри — только инкремент и запись строки. Никаких обращений к дереву нод,
## к Game.world и к сценам.

static var errors: int = 0
static var warnings: int = 0
static var first: String = ""
static var samples: Array[String] = []

const MAX_SAMPLES: int = 5

static func reset() -> void:
	errors = 0
	warnings = 0
	first = ""
	samples.clear()

## Регистрация. Возвращает false, если версия движка класс не поддерживает.
static func install() -> bool:
	if not ClassDB.class_exists("Logger"):
		push_warning("ErrorGuard: Logger недоступен, нужен Godot 4.5+")
		return false
	OS.add_logger(ErrorGuard.new())
	return true

func _log_error(function: String, file: String, line: int, code: String,
		rationale: String, _editor_notify: bool, _error_type: int,
		_script_backtraces: Array) -> void:
	errors += 1
	var line_text: String = "%s:%d %s() — %s %s" % [file, line, function, code, rationale]
	if first.is_empty():
		first = line_text
	if samples.size() < MAX_SAMPLES:
		samples.append(line_text)

## Отчёт для раннера. Пустая строка = ошибок не было.
static func report() -> String:
	if errors == 0:
		return ""
	var out: PackedStringArray = ["ОШИБОК ДВИЖКА: %d" % errors]
	for s: String in samples:
		out.append("   " + s)
	if errors > samples.size():
		out.append("   … и ещё %d" % (errors - samples.size()))
	return "\n".join(out)
