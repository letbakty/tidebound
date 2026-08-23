extends SceneTree
## Headless-раннер TIDEBOUND. Переносить в res://tests/run_all.gd (этап 00).
##
##   godot --headless --import --quit        # обязательно перед первым прогоном
##   godot --headless -s res://tests/run_all.gd
##   echo $?                                  # 0 = все зелёные
##
## Отсутствующие сьюты пропускаются (SKIP), а не роняют прогон: раннер пишется
## на этапе 00, когда ни одного теста ещё нет.

const SUITES: Array[String] = [
	"res://tests/test_data.gd",        # первым: битые .tres валят всё остальное
	"res://tests/test_clock.gd",
	"res://tests/test_terrain.gd",
	"res://tests/test_storage.gd",
	"res://tests/test_agents.gd",
	"res://tests/test_jobs.gd",
	"res://tests/test_buildings.gd",
	"res://tests/test_production.gd",
	"res://tests/test_crises.gd",
	"res://tests/test_cards.gd",
	"res://tests/test_save.gd",
	"res://tests/test_game.gd",
	"res://tests/test_signals.gd",
	"res://tests/test_ui.gd",
	"res://tests/test_hud.gd",
	"res://tests/test_panels.gd",
	"res://tests/test_screens.gd",
	"res://tests/test_input_bindings.gd",
	"res://tests/test_golden.gd",
	"res://tests/test_touch_targets.gd",
	"res://tests/test_audio.gd",
	"res://tests/test_visual.gd",
	"res://tests/test_edge_cases.gd",
]

## Фильтр сьютов из командной строки: `-s res://tests/run_all.gd -- production`
## гоняет только test_production. Нужен ремонту дефектов: полный прогон идёт
## больше трёх минут, и чинить по одному сьюту в разы быстрее.
static func _filters() -> PackedStringArray:
	return OS.get_cmdline_user_args()

static func _matches(path: String, filters: PackedStringArray) -> bool:
	if filters.is_empty():
		return true
	for f: String in filters:
		if path.contains(f):
			return true
	return false

func _initialize() -> void:
	# ДО первого сьюта: иначе рантайм-ошибки самой загрузки останутся невидимы.
	ErrorGuard.reset()
	var guard_installed: bool = ErrorGuard.install()
	var ctx := TestCtx.new()
	var t0: int = Time.get_ticks_msec()
	var ran: int = 0
	var filters: PackedStringArray = _filters()
	for path: String in SUITES:
		if not _matches(path, filters):
			continue
		if not ResourceLoader.exists(path):
			print("SKIP  ", path)
			continue
		ran += 1
		ctx.run_suite(load(path) as GDScript)
	if ran == 0:
		print("TESTS OK")               # этап 00: ни одного сьюта ещё нет
		quit(0)
		return
	ctx.print_report(Time.get_ticks_msec() - t0)
	# ⚠️ SCRIPT ERROR валит прогон наравне с провалом check(). Именно из-за
	# отсутствия этой проверки 365 ошибок жили при зелёном отчёте.
	var guard: String = ErrorGuard.report()
	if not guard.is_empty():
		print(guard)
		print("TESTS FAILED")
	elif not guard_installed:
		print("⚠️  ErrorGuard не установлен: рантайм-ошибки ловит только tools/run_tests.sh")
	quit(0 if ctx.failed == 0 and guard.is_empty() else 1)
