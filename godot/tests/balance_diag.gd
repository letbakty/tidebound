extends SceneTree
## Разовая диагностика под конкретный вопрос итерации 4. НЕ прибор: sweep живёт
## в balance_probe.gd, эти числа в CSV не попадают и в вилку приёмки не входят.
##
##   godot --headless -s res://tests/balance_diag.gd -- 3 balanced
##
## Отвечает на два вопроса, на которые sweep ответить не может:
##   1. Простой по ФАЗАМ — где именно колония стоит (итерация 3 меряла так же).
##   2. Приход — есть ли у существ вообще цель: сколько построек затоплено
##      в момент их прихода и сколько из них склады. Ноль краж за 300 забегов
##      это либо мёртвые числа, либо отсутствие мишени, и различить их можно
##      только здесь.

## Профили и размещение построек берутся у самого прибора: разойдись они —
## и фазовые числа перестали бы быть сравнимы со sweep.
const Probe = preload("res://tests/balance_probe.gd")

const CLIFF: String = "res://data/cliffs/cliff_01.tres"
const MAX_TICKS: int = 60000
const SEED_STEP: int = 7919
const SEED_BASE: int = 1000
const SAMPLE_EVERY: int = 10

func _initialize() -> void:
	ErrorGuard.reset()
	ErrorGuard.install()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var runs: int = clampi(int(args[0]) if args.size() > 0 else 3, 1, 50)
	var only: String = str(args[1]) if args.size() > 1 else ""
	var cliff: CliffDef = load(CLIFF) as CliffDef

	# Фазовый простой: phase -> [idle, samples, idle_with_bag]
	var by_phase: Dictionary[int, Array] = {}
	for ph: int in SimTypes.PHASE_ORDER:
		by_phase[ph] = [0, 0, 0]
	# Приход: строки «цикл, существ, затоплено построек, из них складов, марки».
	var visit_lines: Array[String] = []
	## Снимок судна: плато сизигии 12-го цикла и склады с их отметками.
	var ship_lines: Array[String] = []

	for p: Dictionary in Probe.PROFILES:
		if not only.is_empty() and str(p["id"]) != only:
			continue
		for i: int in runs:
			_run_one(p, SEED_BASE + i * SEED_STEP, cliff, by_phase, visit_lines,
				ship_lines)
		print("профиль %s: готово" % str(p["id"]))

	print("---")
	print("простой по фазам (доля тиков агента в IDLE):")
	print("%-8s %8s %10s %8s" % ["фаза", "простой", "с грузом", "замеров"])
	for ph: int in SimTypes.PHASE_ORDER:
		var a: Array = by_phase[ph]
		var n: float = float(maxi(int(a[1]), 1))
		print("%-8s %7.1f%% %9.1f%% %8d" % [SimTypes.phase_name(ph),
			100.0 * float(int(a[0])) / n,
			100.0 * float(int(a[2])) / float(maxi(int(a[0]), 1)), int(a[1])])
	print("")
	print("приход: цикл / существ / затопленных построек / из них складов / отметки")
	for s: String in visit_lines:
		print("  " + s)
	print("")
	print("снимок судна: плато / склады (отметка:стаков, ! = затоплен) / очки груза")
	for s2: String in ship_lines:
		print("  " + s2)
	var guard: String = ErrorGuard.report()
	if not guard.is_empty():
		print(guard)
	quit(1 if ErrorGuard.script_errors > 0 else 0)

func _run_one(p: Dictionary, seed_value: int, cliff: CliffDef,
		by_phase: Dictionary[int, Array], visit_lines: Array[String],
		ship_lines: Array[String]) -> void:
	var w: SimWorld = SimWorld.new()
	w.new_run(seed_value, cliff)
	w.events_out.clear()
	var policies: Array = p["policies"] as Array
	for i: int in SimTypes.POLICY_ORDER.size():
		w.apply_command({"kind": "set_policy",
			"policy": SimTypes.POLICY_ORDER[i], "value": int(policies[i])})
	var st: Dictionary = {"build_idx": 0}
	var ticks: int = 0
	var done: bool = false
	var visit_logged: Dictionary[int, bool] = {}

	while ticks < MAX_TICKS and not done:
		w.tick()
		ticks += 1
		for e: SimEvent in w.events_out:
			if e.type == "run_ended":
				done = true
		# Момент судна: docs/00 §11.2 — пик Высокой воды 12-го цикла. Снимаем
		# то же, что считает compute_score, но с отметками складов: очки груза
		# у профилей падают до нуля именно здесь, и надо видеть, из-за чего.
		if w.clock.cycle == Balance.CYCLES_PER_RUN and w.clock.at_high_peak():
			var parts: PackedStringArray = []
			var pts: int = 0
			for stg: Dictionary in w.storage.storages:
				var mk: int = Balance.cell_to_mark(stg["cell"] as Vector2i)
				var flood: bool = Balance.is_mark_flooded(mk, w.tide.level)
				parts.append("%d:%d%s" % [mk, (stg["stacks"] as Array).size(),
					"!" if flood else ""])
				if flood:
					continue
				for v: Variant in stg["stacks"] as Array:
					var it: ItemDef = DB.item(str((v as Dictionary)["item_id"]))
					if it != null:
						pts += it.ship_points * int((v as Dictionary)["count"])
			ship_lines.append("%s c%d: плато %.1f, склады [%s], очки груза %d" % [
				str(p["id"]), seed_value, w.tide.high_plateau,
				" ".join(parts), pts])
		# Существа приходят в начале HIGH — там же и смотрим, есть ли им что
		# грабить. Пик воды ещё впереди, но цели существо ищет каждый тик,
		# поэтому считаем по плато фазы: до чего вода дойдёт за эту Высокую.
		if not w.crisis.creatures.is_empty() \
				and not visit_logged.get(w.clock.cycle, false):
			visit_logged[w.clock.cycle] = true
			var flooded: int = 0
			var stores: int = 0
			var marks: Array[int] = []
			for bid: int in w.buildings.order:
				var b: Dictionary = w.buildings.buildings[bid]
				if float(int(b["mark"])) >= w.tide.high_plateau:
					continue
				flooded += 1
				if not marks.has(int(b["mark"])):
					marks.append(int(b["mark"]))
				if DB.building(str(b["def_id"])).special == "storage":
					stores += 1
			marks.sort()
			visit_lines.append("%s c%d ц%d: существ %d, затоплено %d, складов %d, отметки %s" % [
				str(p["id"]), seed_value, w.clock.cycle,
				w.crisis.creatures.size(), flooded, stores, str(marks)])
		# Последний тик Высокой воды цикла Прихода: где существа и что делают.
		if not w.crisis.creatures.is_empty() \
				and w.clock.phase == SimTypes.Phase.HIGH \
				and w.clock.ticks_left_in_phase() == 1:
			for c: Dictionary in w.crisis.creatures:
				visit_lines.append("    %s c%d ц%d: существо на площадке %d (отм %d) x=%.1f, цель %d, грызёт %d, уходит %s" % [
					str(p["id"]), seed_value, w.clock.cycle, int(c["platform"]),
					int(w.terrain.platforms[int(c["platform"])]["mark"]),
					float(c["x"]), int(c["target_id"]), int(c["gnaw_ticks"]),
					str(bool(c["leaving"]))])
		w.events_out.clear()
		if ticks % SAMPLE_EVERY == 0:
			_act(p, w, st)
			var row: Array = by_phase[int(w.clock.phase)]
			for a: SimAgent in w.agents.agents:
				if not a.is_alive():
					continue
				row[1] = int(row[1]) + 1
				if a.state == SimTypes.AgentState.IDLE:
					row[0] = int(row[0]) + 1
					if not a.bag.is_empty():
						row[2] = int(row[2]) + 1

## Копия Probe._profile_act: он не static, а инстанцировать SceneTree ради
## двенадцати строк дороже, чем повторить их со ссылкой на общие статики.
static func _act(p: Dictionary, w: SimWorld, st: Dictionary) -> void:
	if not w.run_state.drafted_this_cycle and not w.run_state.draft.is_empty():
		var want: String = str(p["card"])
		var pick: String = want if w.run_state.draft.has(want) else w.run_state.draft[0]
		w.apply_command({"kind": "pick_card", "card": pick})
	if Probe._has_unfinished(w):
		return
	var order: Array = p["build"] as Array
	var idx: int = int(st["build_idx"])
	if idx >= order.size():
		return
	st["build_idx"] = idx + 1
	Probe._try_build(str(order[idx]), w)
