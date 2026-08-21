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
	"res://tests/test_signals.gd",
	"res://tests/test_ui.gd",
	"res://tests/test_golden.gd",
	"res://tests/test_touch_targets.gd",
]

func _initialize() -> void:
	var ctx := TestCtx.new()
	var t0: int = Time.get_ticks_msec()
	var ran: int = 0
	for path: String in SUITES:
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
	quit(0 if ctx.failed == 0 else 1)
