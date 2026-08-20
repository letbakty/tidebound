class_name TestCtx
extends RefCounted
## Мини-фреймворк тестов TIDEBOUND. Переносить в res://tests/test_ctx.gd (этап 00).
## Почему свой, а не GUT/GdUnit4 — docs/02 §7: ноль зависимостей, хватает для sim-ядра.
##
## ВАЖНО: не использовать assert() в тестах — он вырезается в release-сборках
## (док GDScript: "Ignored in non-debug builds"). Только check*().

var total: int = 0
var failed: int = 0
var failures: Array[String] = []

var _suite: String = ""
var _test: String = ""
var _suite_checks: int = 0

# --- Запуск ---------------------------------------------------------------

## Прогоняет все статические функции скрипта, чьё имя начинается с "test_".
func run_suite(script: GDScript) -> void:
	_suite = script.resource_path.get_file().trim_suffix(".gd")
	for m: Dictionary in script.get_script_method_list():
		var name: String = m["name"]
		if not name.begins_with("test_"):
			continue
		_test = name
		_suite_checks = 0
		var before: int = failed
		script.call(name, self)
		var mark: String = "OK  " if failed == before else "FAIL"
		print("[%s] %s %s %s (%d проверок)" % [
			_suite, name.trim_prefix("test_"),
			".".repeat(maxi(2, 34 - name.length())), mark, _suite_checks])

# --- Проверки -------------------------------------------------------------

func check(cond: bool, msg: String) -> void:
	total += 1
	_suite_checks += 1
	if cond:
		return
	failed += 1
	var line: String = "%s/%s :: %s" % [_suite, _test, msg]
	failures.append(line)
	push_error("FAIL " + line)

## Печатает ОБА значения: "не равно" без чисел — бесполезное сообщение.
func check_eq(a: Variant, b: Variant, msg: String) -> void:
	check(a == b, "%s (ожидалось %s, получено %s)" % [msg, str(b), str(a)])

func check_approx(a: float, b: float, eps: float, msg: String) -> void:
	check(absf(a - b) <= eps,
		"%s (ожидалось %.4f ±%.4f, получено %.4f)" % [msg, b, eps, a])

func check_hash(a: Object, b: Object, msg: String) -> void:
	check(state_hash(a) == state_hash(b), msg)

# --- Утилиты --------------------------------------------------------------

## sort_keys=true по умолчанию => порядок ключей нормализован;
## full_precision=false => гасит незначимый float-шум (для СЕЙВА нужно true, см. research/18 §2).
static func state_hash(world: Object) -> String:
	return JSON.stringify(world.call("to_dict")).sha256_text()

## Тикает мир и ЧИСТИТ events_out: иначе за 20 000 тиков накопятся сотни тысяч SimEvent.
func run_ticks(world: Object, n: int) -> void:
	for i: int in n:
		world.call("tick")
		(world.get("events_out") as Array).clear()

## Бинарный поиск тика расхождения. Тяжёлый — звать вручную при расследовании.
func find_divergence(make_world: Callable, max_ticks: int) -> int:
	var a: Object = make_world.call()
	var b: Object = make_world.call()
	for i: int in max_ticks:
		run_ticks(a, 1)
		run_ticks(b, 1)
		if state_hash(a) != state_hash(b):
			return i
	return -1

# --- Отчёт ----------------------------------------------------------------

func print_report(elapsed_ms: int) -> void:
	print("---")
	for f: String in failures:
		print("   " + f)
	print("%d проверок, провалено %d, %d мс" % [total, failed, elapsed_ms])
	print("TESTS OK" if failed == 0 else "TESTS FAILED")
