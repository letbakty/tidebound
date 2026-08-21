extends SceneTree
## Автопилотный стресс этапа 19: двадцать забегов разными сидами без единой
## ошибки, плюс CSV со статистикой.
##
##   godot --headless -s res://tests/soak.gd
##   godot --headless -s res://tests/soak.gd -- 5      # быстрый прогон
##
## CSV — не побочный продукт, а заготовка баланс-данных: распределение очков
## и причин смерти по двадцати сидам сразу показывает, слишком ли легко или
## тяжело (research/30).
##
## ⚠️ Прогон валится не только по «упало», но и по любой рантайм-ошибке
## движка: ErrorGuard считает их из логгера. Именно этого не хватало проекту,
## когда 365 SCRIPT ERROR жили при зелёных тестах (docs/BUG-salt-chain.md).

const RUNS: int = 20
## Потолок тиков на забег. 12 циклов × 3000 = 36 000; всё, что дольше —
## зависший run_state, и без счётчика он повесил бы прогон навсегда.
const MAX_TICKS: int = 60000
const CLIFF: String = "res://data/cliffs/cliff_01.tres"
const OUT_CSV: String = "res://../docs/soak.csv"
## Разброс сидов: шаг простым числом, чтобы сиды не ложились в один класс
## по модулю и карты получались разными.
const SEED_STEP: int = 7919
const SEED_BASE: int = 1000

## Прирост нод между забегами, выше которого это уже утечка (research/24 §7).
const NODE_GROWTH_LIMIT: int = 50

func _initialize() -> void:
	ErrorGuard.reset()
	ErrorGuard.install()
	var runs: int = _runs_from_args()
	var cliff: CliffDef = load(CLIFF) as CliffDef
	if cliff == null:
		push_error("soak: не загрузилась карта утёса")
		quit(2)
		return

	var rows: Array[String] = ["seed,cycles,end,score,raw,alive,deaths,drowned,relics,ticks,ms"]
	var failures: int = 0
	var before: Dictionary = _memory_snapshot()
	var total_ms: int = 0

	for i: int in runs:
		var seed_value: int = SEED_BASE + i * SEED_STEP
		var t0: int = Time.get_ticks_msec()
		var row: Dictionary = _run_one(seed_value, cliff)
		var ms: int = Time.get_ticks_msec() - t0
		total_ms += ms
		if not bool(row["ok"]):
			failures += 1
		rows.append("%d,%d,%s,%d,%d,%d,%d,%d,%d,%d,%d" % [seed_value,
			int(row["cycles"]), str(row["end"]), int(row["score"]), int(row["raw"]),
			int(row["alive"]), int(row["deaths"]), int(row["drowned"]),
			int(row["relics"]), int(row["ticks"]), ms])
		print("  сид %d: %s, циклов %d, очков %d, выжило %d, погибло %d (%d мс)" % [
			seed_value, str(row["end"]), int(row["cycles"]), int(row["score"]),
			int(row["alive"]), int(row["deaths"]), ms])

	var after: Dictionary = _memory_snapshot()
	_write_csv(rows)
	_print_summary(runs, failures, total_ms, before, after)

	# Сравниваем ПРИРОСТ, а не абсолютные числа: на старте скриптового режима
	# уже висят автолоады, которые движок ещё не внёс в дерево, и их семь штук
	# в любом прогоне. Утечка — это когда после забегов их стало больше.
	var leaked: bool = int(after["nodes"]) - int(before["nodes"]) > NODE_GROWTH_LIMIT \
		or int(after["orphans"]) > int(before["orphans"])
	var bad: bool = failures > 0 or ErrorGuard.script_errors > 0 or leaked
	quit(1 if bad else 0)

## Один забег до конца. Возвращает строку статистики и признак «прошёл».
func _run_one(seed_value: int, cliff: CliffDef) -> Dictionary:
	var w: SimWorld = SimWorld.new()
	w.new_run(seed_value, cliff)
	w.events_out.clear()
	var ticks: int = 0
	var drowned: int = 0
	var report: Dictionary = {}
	while ticks < MAX_TICKS:
		w.tick()
		ticks += 1
		for e: SimEvent in w.events_out:
			if e.type == "agent_died" and str(e.data.get("cause", "")) == "drown":
				drowned += 1
			elif e.type == "run_ended":
				report = e.data["report"] as Dictionary
		w.events_out.clear()
		if not report.is_empty():
			break
	var ok: bool = not report.is_empty()
	if not ok:
		push_error("soak: забег %d не завершился за %d тиков" % [seed_value, MAX_TICKS])
	return {
		"ok": ok,
		"cycles": int(report.get("cycles", w.clock.cycle)),
		"end": _end_name(int(report.get("end", -1))),
		"score": int(report.get("score", 0)),
		"raw": int(report.get("raw_score", 0)),
		"alive": w.agents.alive_count(),
		"deaths": (report.get("deaths", []) as Array).size(),
		"drowned": drowned,
		"relics": int(report.get("relics", 0)),
		"ticks": ticks,
	}

static func _end_name(kind: int) -> String:
	match kind:
		SimTypes.RunEnd.SHIP: return "ship"
		SimTypes.RunEnd.WIPE: return "wipe"
		SimTypes.RunEnd.EARLY: return "early"
	return "unfinished"

## print_orphan_nodes() печатает список, но ничего не возвращает и работает
## только в debug — для проверки нужен именно счётчик Performance.
func _memory_snapshot() -> Dictionary:
	return {
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"static_mem": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
	}

func _write_csv(rows: Array[String]) -> void:
	var f: FileAccess = FileAccess.open(OUT_CSV, FileAccess.WRITE)
	if f == null:
		push_error("soak: не открыть %s" % OUT_CSV)
		return
	f.store_string("\n".join(rows) + "\n")
	f.close()
	print("CSV: %s" % OUT_CSV)

func _print_summary(runs: int, failures: int, total_ms: int,
		before: Dictionary, after: Dictionary) -> void:
	print("---")
	print("забегов %d, не завершились %d, ошибок движка %d, ошибок кода %d" % [
		runs, failures, ErrorGuard.script_errors, ErrorGuard.user_errors])
	print("время: %d мс всего, %d мс на забег" % [total_ms, total_ms / maxi(runs, 1)])
	print("память: ноды %d -> %d, орфаны %d -> %d, статика %.1f МБ" % [
		int(before["nodes"]), int(after["nodes"]),
		int(before["orphans"]), int(after["orphans"]),
		float(after["static_mem"]) / 1048576.0])
	var guard: String = ErrorGuard.report()
	if not guard.is_empty():
		print(guard)

static func _runs_from_args() -> int:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		return RUNS
	return clampi(int(args[0]), 1, 200)
