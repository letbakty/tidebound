class_name ErrorGuard
extends Logger
## Ловит ошибки движка и рантайм-ошибки скриптов за прогон тестов.
## Регистрируется в run_all.gd ДО первого сьюта.
##
## Зачем: buffer_take падал на КАЖДОМ вызове одиннадцать этапов подряд —
## 365 SCRIPT ERROR за прогон при полностью зелёном отчёте. TestCtx проверяет
## только свои check(), stderr для него невидим (docs/BUG-salt-chain.md,
## research/43 §3).
##
## ⚠️ Логгер движок зовёт ИЗ ЛЮБОГО ПОТОКА. Внутри — только счётчики и строки:
## ни дерева нод, ни Game.world, ни сцен.

## Рантайм GDScript и шейдеры — всегда дефект, валят прогон.
static var script_errors: int = 0
## push_error: им пользуются и мягкие отказы кода, и TestCtx.check при провале,
## и тесты, которые эти отказы проверяют. Считаем, но прогон не валим.
static var user_errors: int = 0
static var warnings: int = 0
static var samples: Array[String] = []

const MAX_SAMPLES: int = 8

static func reset() -> void:
	script_errors = 0
	user_errors = 0
	warnings = 0
	samples.clear()

## Регистрация. false — версия движка класс не поддерживает (нужен 4.5+),
## тогда прогон полагается на грепалку в tools/run_tests.sh.
static func install() -> bool:
	if not ClassDB.class_exists("Logger"):
		push_warning("ErrorGuard: класс Logger недоступен, нужен Godot 4.5+")
		return false
	OS.add_logger(ErrorGuard.new())
	return true

func _log_error(function: String, file: String, line: int, code: String,
		rationale: String, _editor_notify: bool, error_type: int,
		_script_backtraces: Array) -> void:
	match error_type:
		Logger.ERROR_TYPE_WARNING:
			warnings += 1
			return
		Logger.ERROR_TYPE_ERROR:
			user_errors += 1
			return
		_:
			script_errors += 1
	if samples.size() >= MAX_SAMPLES:
		return
	var detail: String = rationale if not rationale.is_empty() else code
	samples.append("%s:%d %s() — %s" % [file, line, function, detail])

## Отчёт для раннера. Пустая строка = рантайм-ошибок не было.
static func report() -> String:
	if script_errors == 0:
		return ""
	var out: PackedStringArray = [
		"ОШИБОК РАНТАЙМА: %d (SCRIPT/SHADER)" % script_errors]
	for s: String in samples:
		out.append("   " + s)
	if script_errors > samples.size():
		out.append("   … и ещё %d" % (script_errors - samples.size()))
	return "\n".join(out)
