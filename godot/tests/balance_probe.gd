extends SceneTree
## Sweep баланса: профили стратегий × сиды (research/30 §2, §4) плюс
## диагностика давления — что убивает и добираются ли потребности до порогов.
##
##   godot --headless -s res://tests/balance_probe.gd            # 5 профилей × 20 сидов
##   godot --headless -s res://tests/balance_probe.gd -- 5       # 5 профилей × 5 сидов
##   godot --headless -s res://tests/balance_probe.gd -- 20 turtle
##
## Отличие от soak.gd: тот отвечает «не упало ли», этот — «кусается ли» и
## «есть ли доминирующая стратегия». Пишет три таблицы: по забегу
## (docs/balance_probe.csv), по каждой смерти (docs/balance_deaths.csv)
## и по каждому циклу (docs/balance_timeline.csv).
##
## ⚠️ Профиль подаёт команды через тот же `world.apply_command`, что и игрок
## (research/30 §2). Второго пути исполнения быть не должно: иначе баланс
## меряется не в той игре, в которую играют.
##
## ⚠️ Все профили гоняются на ОДНИХ И ТЕХ ЖЕ сидах. Сравнивать стратегии
## можно только на одинаковых мирах — иначе разница в очках это разница
## в картах, а не в решениях.

const RUNS: int = 20
const MAX_TICKS: int = 60000
const CLIFF: String = "res://data/cliffs/cliff_01.tres"
const OUT_RUNS: String = "res://../docs/balance_probe.csv"
const OUT_DEATHS: String = "res://../docs/balance_deaths.csv"
const OUT_TIMELINE: String = "res://../docs/balance_timeline.csv"
const SEED_STEP: int = 7919
const SEED_BASE: int = 1000
## Потребности меняются на десятки милли-единиц за тик — раз в секунду
## достаточно, а обход шести агентов каждый тик утроил бы время прогона.
## С той же частотой ходит и профиль: игрок тоже не кликает каждый тик.
const SAMPLE_EVERY: int = 10
## Трасса тонущего: отметка, лестница и счётчик погружения на каждом тике.
## Выключена — включать под конкретный вопрос, иначе она топит лог.
const TRACE_DROWNING: bool = false
const NO_SPOT: Vector2i = Vector2i(-9999, -9999)

# --- Профили стратегий (research/30 §2) -----------------------------------

## ⚠️ Профиль — это НЕ ИИ. Он не играет хорошо, он играет ПОСЛЕДОВАТЕЛЬНО:
## одни и те же политики, тот же порядок построек, то же предпочтение карты.
## Именно постоянство делает сравнение осмысленным.
##
## policies — в порядке SimTypes.POLICY_ORDER: жадность, осторожность, ремонт,
## стройка, заготовка, отдых.
## build — очередь `def_id`. Токен "ladder" означает «следующая недостающая
## лестница вниз»; повторы копают глубже.
## card — предпочтение драфта; если карты в раздаче нет, берётся первая.
const PROFILES: Array[Dictionary] = [
	{
		"id": "turtle",
		"policies": [0, 3, 2, 2, 2, 2],
		"build": ["storage", "dryer", "bunk", "forge", "workbench"],
		"card": "careful",
	},
	{
		"id": "greedy",
		"policies": [3, 0, 1, 1, 3, 0],
		"build": ["ladder", "ladder", "ladder", "ladder", "ladder", "ladder",
			"storage", "forge"],
		"card": "deep_dive",
	},
	{
		"id": "builder",
		"policies": [1, 2, 3, 3, 1, 1],
		"build": ["forge", "workbench", "evaporator", "saltery", "ropery",
			"dryer", "storage"],
		"card": "fast_haul",
	},
	{
		# ⚠️ Единственный профиль, строящий вершу (balance.md, итерация 4,
		# прогон F). Верша требует троса, поэтому перед ней в очереди стоит
		# вся цепочка: горн → сушила (волокно) → канатная (трос). Замена
		# очереди — смена прибора, и числа `gatherer` после неё сравнимы
		# только с прогонами F и дальше.
		"id": "gatherer",
		"policies": [2, 2, 1, 1, 3, 1],
		"build": ["ladder", "ladder", "ladder", "storage", "forge", "dryer",
			"ropery", "weir", "workbench"],
		"card": "deep_dive",
	},
	{
		"id": "balanced",
		"policies": [2, 2, 2, 2, 2, 2],
		"build": ["forge", "ladder", "ladder", "workbench", "evaporator",
			"saltery", "storage"],
		"card": "fast_haul",
	},
]

var _death_rows: Array[String] = []
var _timeline_rows: Array[String] = []
var _cause_counts: Dictionary[String, int] = {}
var _deaths_by_cycle: Dictionary[int, int] = {}

func _initialize() -> void:
	# CONVENTIONS 0a: зелёный отчёт без взгляда на SCRIPT ERROR ничего не значит.
	ErrorGuard.reset()
	ErrorGuard.install()
	var runs: int = _runs_from_args()
	var only: String = _profile_from_args()
	var cliff: CliffDef = load(CLIFF) as CliffDef
	if cliff == null:
		push_error("balance_probe: не загрузилась карта утёса")
		quit(2)
		return

	_death_rows = ["profile,seed,cycle,phase,cause,mark,recalled," \
		+ "satiety,warmth,mood,name,traits"]
	_timeline_rows = ["profile,seed,cycle,deaths,ebb_start_level,at_risk_at_ebb," \
		+ "submerged_samples,submerged_pct,avg_satiety,avg_warmth,avg_mood"]
	var rows: Array[String] = [_header()]
	var agg: Array[Dictionary] = []
	for p: Dictionary in PROFILES:
		if not only.is_empty() and str(p["id"]) != only:
			continue
		for i: int in runs:
			var seed_value: int = SEED_BASE + i * SEED_STEP
			var r: Dictionary = _run_one(p, seed_value, cliff)
			agg.append(r)
			rows.append(_row(r))
		print("профиль %s: готово" % str(p["id"]))

	_write(OUT_RUNS, rows)
	_write(OUT_DEATHS, _death_rows)
	_write(OUT_TIMELINE, _timeline_rows)
	_summary(agg)
	var guard: String = ErrorGuard.report()
	if not guard.is_empty():
		print(guard)
	quit(1 if ErrorGuard.script_errors > 0 else 0)

# --- Один забег -----------------------------------------------------------

func _run_one(p: Dictionary, seed_value: int, cliff: CliffDef) -> Dictionary:
	var w: SimWorld = SimWorld.new()
	w.new_run(seed_value, cliff)
	w.events_out.clear()
	var policies: Array = p["policies"] as Array
	for i: int in SimTypes.POLICY_ORDER.size():
		w.apply_command({"kind": "set_policy",
			"policy": SimTypes.POLICY_ORDER[i], "value": int(policies[i])})
	var st: Dictionary = {"build_idx": 0}

	var min_need: Dictionary[String, int] = {
		"satiety": Balance.NEED_MAX_MILLI,
		"warmth": Balance.NEED_MAX_MILLI,
		"mood": Balance.NEED_MAX_MILLI,
	}
	var low_samples: Dictionary[String, int] = {"satiety": 0, "warmth": 0, "mood": 0}
	var zero_hits: Dictionary[String, int] = {"satiety": 0, "warmth": 0, "mood": 0}
	var samples: int = 0
	var idle_samples: int = 0
	## Простой С ГРУЗОМ: агент в IDLE с непустой котомкой. Это ровно тот
	## случай, который описала итерация 3: `_start_self_haul` не нашёл склада
	## со свободным слотом и поставил человека стоять с добычей в руках.
	## Считается вместе с idle, чтобы не заводить второй проход по агентам.
	var idle_bag_samples: int = 0
	## Заполненность складов: стаки / вместимость, усреднённая по замерам.
	var fill_num: float = 0.0
	var fill_den: float = 0.0
	var sick_samples: int = 0
	var deepest_mark: float = 99.0
	var wet_samples: int = 0

	# Шторм: отметки агентов в момент пика.
	#
	# ⚠️ Пик шторма симуляция считает В НАЧАЛЕ Высокой воды (docs/00 §9.4,
	# crisis.on_phase_started) — и убивает всех ниже STORM_DEATH_MARK ВНУТРИ
	# того же w.tick(), до того как мы доберёмся до events_out. Считать полосу
	# гибели по выжившим бессмысленно: там уже никого нет по построению.
	# Отсюда «0.0 агентов в полосе гибели» итераций 1–3 при 48 смертях от
	# шторма в итерации 3. Снимаем на тик РАНЬШЕ (_storm_peak_next): позиции
	# те же (crisis.on_phase_started идёт до agents.tick), но полоса населена.
	var storm_min_mark: float = 99.0
	var storm_below_death: int = 0
	var storm_in_wet_band: int = 0
	var storm_damaged: int = 0
	var storm_buildings: int = 0

	## Добыто С КАРТЫ за забег: item_id -> сколько. Берётся из отчёта цикла
	## (jobs.on_cycle_ended), то есть считает ровно добычу из депозитов —
	## не производство и не плавник. Первая волна контента (CONTENT-wave-1 §1)
	## обещала, что география начнёт влиять на экономику; проверяется это здесь.
	var gathered: Dictionary[String, int] = {}
	var creatures_spawned: int = 0
	var damage_total: int = 0
	var stolen_total: int = 0
	var flooded_storages: int = 0
	var cards_picked: Array[String] = []
	var deaths: Array[Dictionary] = []
	var report: Dictionary = {}
	var ticks: int = 0
	var end_totals: Dictionary[String, int] = {}
	## Поцикловая строка timeline (research/30 §4): «кривая внутри забега».
	var cyc: Dictionary[int, Dictionary] = {}
	var ebb_seen: Dictionary[int, bool] = {}

	while ticks < MAX_TICKS:
		if _storm_peak_next(w):
			for ap: SimAgent in w.agents.agents:
				if not ap.is_alive():
					continue
				var mp: float = w.agents.agent_mark_f(ap, w)
				storm_min_mark = minf(storm_min_mark, mp)
				if mp < float(Balance.STORM_DEATH_MARK):
					storm_below_death += 1
				elif mp <= float(Balance.STORM_WET_MARK_HI):
					storm_in_wet_band += 1
		w.tick()
		ticks += 1
		var storm_peak_now: bool = false
		var cycle_now: int = w.clock.cycle
		var row: Dictionary = _cycle_row(cyc, cycle_now)
		for e: SimEvent in w.events_out:
			match e.type:
				"agent_died":
					var a: SimAgent = _agent_by_id(w, int(e.data.get("id", -1)))
					deaths.append(_death_record(w, a, str(e.data.get("cause", "?"))))
					row["deaths"] = int(row["deaths"]) + 1
				"creature_spawned":
					creatures_spawned += 1
				"card_picked":
					cards_picked.append(str(e.data.get("card", "")))
				"phase_changed":
					if int(e.data.get("phase", -1)) == int(SimTypes.Phase.HIGH) \
							and w.crisis.is_active(SimTypes.CrisisType.STORM):
						storm_peak_now = true
				"cycle_ended":
					for gk: Variant in e.data.get("gathered", {}) as Dictionary:
						var gid: String = str(gk)
						gathered[gid] = int(gathered.get(gid, 0)) \
							+ int((e.data["gathered"] as Dictionary)[gk])
					damage_total += int(e.data.get("damage", 0))
					for k: Variant in e.data.get("stolen", {}) as Dictionary:
						stolen_total += int((e.data["stolen"] as Dictionary)[k])
				"run_ended":
					report = e.data["report"] as Dictionary
		# Первый тик Спада: сюда смотрел разбор сизигии (docs/balance.md).
		if w.clock.phase == SimTypes.Phase.EBB and not ebb_seen.get(cycle_now, false):
			ebb_seen[cycle_now] = true
			row["ebb_level"] = w.tide.level
			for a4: SimAgent in w.agents.agents:
				if a4.is_alive() and Balance.is_markf_flooded(
						w.agents.agent_mark_f(a4, w), w.tide.level):
					row["at_risk"] = int(row["at_risk"]) + 1
		if storm_peak_now:
			# Постройки — наоборот, ПОСЛЕ тика: урон шторм наносит мимо
			# _damage_cycle (там только существа), и до пика флага ещё нет.
			for bid: int in w.buildings.order:
				storm_buildings += 1
				if bool((w.buildings.buildings[bid] as Dictionary)["damaged"]):
					storm_damaged += 1
		w.events_out.clear()

		if TRACE_DROWNING:
			for at: SimAgent in w.agents.agents:
				if at.is_alive() and at.state == SimTypes.AgentState.DROWNING:
					print("      т%d %s: отм %.2f x %.1f пл %d->%d t %.2f, под водой %d, уровень %.2f" % [
						ticks, at.agent_name, w.agents.agent_mark_f(at, w), at.x,
						at.platform_id, at.climb_to, at.climb_t,
						at.submerged_ticks, w.tide.level])

		if ticks % SAMPLE_EVERY == 0:
			_profile_act(p, w, st)
			row["samples"] = int(row["samples"]) + w.agents.alive_count()
			for a3: SimAgent in w.agents.agents:
				if not a3.is_alive():
					continue
				samples += 1
				row["satiety"] = float(row["satiety"]) + float(a3.needs["satiety"]) / 1000.0
				row["warmth"] = float(row["warmth"]) + float(a3.needs["warmth"]) / 1000.0
				row["mood"] = float(row["mood"]) + float(a3.needs["mood"]) / 1000.0
				if Balance.is_markf_flooded(w.agents.agent_mark_f(a3, w), w.tide.level):
					row["submerged"] = int(row["submerged"]) + 1
				for k2: String in min_need:
					var v: int = int(a3.needs[k2])
					min_need[k2] = mini(min_need[k2], v)
					if v < Balance.NEED_LOW_ENTER_MILLI:
						low_samples[k2] += 1
					if v <= 0:
						zero_hits[k2] += 1
				if a3.state == SimTypes.AgentState.IDLE:
					row["idle"] = int(row["idle"]) + 1
					idle_samples += 1
					if not a3.bag.is_empty():
						idle_bag_samples += 1
				if a3.sick:
					sick_samples += 1
				if a3.wet:
					wet_samples += 1
				deepest_mark = minf(deepest_mark, w.agents.agent_mark_f(a3, w))
			for stg: Dictionary in w.storage.storages:
				fill_num += float((stg["stacks"] as Array).size())
				fill_den += float(int(stg["capacity"]))
				if Balance.is_mark_flooded(Balance.cell_to_mark(stg["cell"] as Vector2i),
						w.tide.level):
					flooded_storages = maxi(flooded_storages, 1)

		if not report.is_empty():
			end_totals = w.storage.totals()
			break

	if report.is_empty():
		push_error("balance_probe: забег %d (%s) не завершился" % [seed_value, str(p["id"])])

	var pid: String = str(p["id"])
	var by_cause: Dictionary[String, int] = {}
	for d: Dictionary in deaths:
		var c: String = str(d["cause"])
		by_cause[c] = int(by_cause.get(c, 0)) + 1
		_cause_counts[c] = int(_cause_counts.get(c, 0)) + 1
		var dcycle: int = int(d["cycle"])
		_deaths_by_cycle[dcycle] = int(_deaths_by_cycle.get(dcycle, 0)) + 1
		_death_rows.append("%s,%d,%d,%s,%s,%.2f,%d,%d,%d,%d,%s,%s" % [
			pid, seed_value, dcycle, str(d["phase"]), c, float(d["mark"]),
			1 if bool(d["recalled"]) else 0,
			int(d["satiety"]), int(d["warmth"]), int(d["mood"]),
			str(d["name"]), str(d["traits"])])

	var cycle_ids: Array[int] = []
	cycle_ids.assign(cyc.keys())
	cycle_ids.sort()
	for ci: int in cycle_ids:
		var cr: Dictionary = cyc[ci]
		var n: float = float(maxi(int(cr["samples"]), 1))
		_timeline_rows.append("%s,%d,%d,%d,%.3f,%d,%d,%.1f,%.1f,%.1f,%.1f" % [
			pid, seed_value, ci, int(cr["deaths"]), float(cr["ebb_level"]),
			int(cr["at_risk"]), int(cr["submerged"]),
			100.0 * float(int(cr["submerged"])) / n,
			float(cr["satiety"]) / n, float(cr["warmth"]) / n, float(cr["mood"]) / n])

	var denom: int = maxi(samples, 1)
	var breakdown: Dictionary = report.get("breakdown", {}) as Dictionary
	return {
		"profile": pid,
		"seed": seed_value,
		"end": _end_name(int(report.get("end", -1))),
		"cycles": int(report.get("cycles", w.clock.cycle)),
		"score": int(report.get("score", 0)),
		# ⚠️ Не alive_count(): к моменту, когда мы разбираем run_ended, часы уже
		# начали следующий цикл и могли добавить новичка. Судно считало не его.
		"alive": int(breakdown.get("survivors", 0)) / Balance.POINTS_PER_SURVIVOR,
		"deaths": deaths.size(),
		"drown": int(by_cause.get("drown", 0)),
		"storm": int(by_cause.get("storm", 0)),
		"built": int(report.get("buildings_built", 0)),
		"lost": int(report.get("buildings_lost", 0)),
		"produced": _sum_values(report.get("produced", {}) as Dictionary),
		"cards": "|".join(cards_picked),
		"min_satiety": min_need["satiety"] / 1000,
		"min_warmth": min_need["warmth"] / 1000,
		"min_mood": min_need["mood"] / 1000,
		"low_satiety_pct": 100.0 * float(low_samples["satiety"]) / float(denom),
		"low_warmth_pct": 100.0 * float(low_samples["warmth"]) / float(denom),
		"low_mood_pct": 100.0 * float(low_samples["mood"]) / float(denom),
		"zero_satiety": zero_hits["satiety"],
		"zero_warmth": zero_hits["warmth"],
		"zero_mood": zero_hits["mood"],
		"sick_pct": 100.0 * float(sick_samples) / float(denom),
		"wet_pct": 100.0 * float(wet_samples) / float(denom),
		"idle_pct": 100.0 * float(idle_samples) / float(denom),
		# Доля ПРОСТОЯ (не всего времени), приходящаяся на стояние с грузом.
		"idle_bag_pct": 100.0 * float(idle_bag_samples) / float(maxi(idle_samples, 1)),
		"fill_pct": 100.0 * fill_num / maxf(fill_den, 1.0),
		"deepest_mark": int(deepest_mark),
		"storm_min_mark": storm_min_mark,
		"storm_below": storm_below_death,
		"storm_wet_band": storm_in_wet_band,
		"storm_damaged": storm_damaged,
		"storm_buildings": storm_buildings,
		"cargo": int(breakdown.get("cargo", 0)),
		"survivor_points": int(breakdown.get("survivors", 0)),
		"relics": int(report.get("relics", 0)),
		"creatures": creatures_spawned,
		"damage": damage_total,
		"stolen": stolen_total,
		"flooded_storages": flooded_storages,
		"rations": int(end_totals.get("rations", 0)),
		"catch": int(end_totals.get("catch", 0)),
		"scrap": int(end_totals.get("scrap", 0)),
		"kelp": int(end_totals.get("kelp", 0)),
		"driftwood": int(end_totals.get("driftwood", 0)),
		# --- Первая волна контента (CONTENT-wave-1) ---------------------------
		# Добыто С КАРТЫ, по предметам: до волны их было три (утиль, добыча,
		# водоросли), стало шесть.
		"got_scrap": int(gathered.get("scrap", 0)),
		"got_catch": int(gathered.get("catch", 0)),
		"got_kelp": int(gathered.get("kelp", 0)),
		"got_salt": int(gathered.get("salt", 0)),
		"got_water": int(gathered.get("freshwater", 0)),
		# «Обломки судна» — проба глубины. Считаем ОТДЕЛЬНО по двум отметкам:
		# −5 доходят два профиля из пяти, −6 не доходит ни один, и разницу
		# между «до глубины не добираются» и «глубина не нужна» видно только
		# так. Ноль здесь — тоже результат, и он записывается числом.
		"wreck5": _wreck_taken(w, -5),
		"wreck6": _wreck_taken(w, -6),
	}

## Следующий w.tick() откроет Высокую воду штормового цикла — тот самый тик,
## на котором сим считает пик шторма (docs/00 §9.4). Одна формула на проект:
## переход считается там же, где его считает SimClock.tick().
static func _storm_peak_next(w: SimWorld) -> bool:
	return w.clock.phase == SimTypes.Phase.SIGNAL \
		and w.clock.ticks_left_in_phase() == 1 \
		and w.crisis.is_active(SimTypes.CrisisType.STORM)

## Сколько вынесли из «Обломков судна» на указанной отметке: ёмкость минус
## остаток (восполнения у них нет, поэтому разница и есть добытое).
static func _wreck_taken(w: SimWorld, mark: int) -> int:
	var n: int = 0
	for d: Dictionary in w.terrain.deposits:
		if str(d["kind"]) != "shipwreck":
			continue
		if Balance.cell_to_mark(d["cell"] as Vector2i) != mark:
			continue
		n += int((Balance.DEPOSIT_KINDS["shipwreck"] as Dictionary)["capacity"]) \
			- int(d["amount"])
	return n

# --- Решения профиля ------------------------------------------------------

## Раз в секунду: выбрать карту, если раздача висит, и заложить следующую
## постройку, если предыдущая достроена.
func _profile_act(p: Dictionary, w: SimWorld, st: Dictionary) -> void:
	if not w.run_state.drafted_this_cycle and not w.run_state.draft.is_empty():
		var want: String = str(p["card"])
		var pick: String = want if w.run_state.draft.has(want) else w.run_state.draft[0]
		w.apply_command({"kind": "pick_card", "card": pick})
	# Одна стройка за раз. Игрок не закладывает пять фундаментов сразу, а
	# колония, размазанная по пяти недостроям, не достраивает ни одного:
	# материалы разъезжаются по буферам и лежат там до конца забега.
	if _has_unfinished(w):
		return
	var order: Array = p["build"] as Array
	var idx: int = int(st["build_idx"])
	if idx >= order.size():
		return
	st["build_idx"] = idx + 1
	_try_build(str(order[idx]), w)

static func _has_unfinished(w: SimWorld) -> bool:
	for id: int in w.buildings.order:
		var b: Dictionary = w.buildings.buildings[id]
		if int(b["state"]) != int(SimTypes.BuildState.ACTIVE):
			return true
	return false

static func _try_build(def_id: String, w: SimWorld) -> bool:
	var cell: Vector2i = _next_ladder_spot(w) if def_id == "ladder" \
		else _find_spot(def_id, w)
	if cell == NO_SPOT:
		return false
	w.apply_command({
		"kind": "place_building",
		"def_id": "ladder_wood" if def_id == "ladder" else def_id,
		"cell": SimTypes.v2i_to_arr(cell),
	})
	return true

## Первая сверху отметка, с которой лестницы вниз ещё нет. Копаем подряд:
## дырка в середине оставила бы нижние ярусы недостижимыми.
static func _next_ladder_spot(w: SimWorld) -> Vector2i:
	for mark_top: int in range(0, Balance.BOTTOM_MARK, -1):
		var has: bool = false
		for l: Dictionary in w.terrain.ladders:
			if int(l["mark_top"]) == mark_top:
				has = true
				break
		if has:
			continue
		var y: int = Balance.mark_to_floor_cell_y(mark_top)
		var pidx: int = w.terrain.platform_of_mark(mark_top)
		if pidx < 0:
			continue
		var pl: Dictionary = w.terrain.platforms[pidx]
		for x: int in range(int(pl["x0"]), int(pl["x1"]) + 1):
			if w.terrain.can_place_ladder(Vector2i(x, y)):
				return Vector2i(x, y)
	return NO_SPOT

## Ближайшая к дому клетка, куда постройка встаёт по всем правилам.
##
## ⚠️ Именно ближайшая, а не «первая сверху». Первая сверху — это отметка +6,
## дальний край утёса: постройка там встаёт, но материалы к ней носят через
## весь утёс, стройка не заканчивается никогда, и очередь профиля встаёт
## на первом же пункте (в первом прогоне turtle и builder так и не построили
## НИЧЕГО). Живой игрок строит от дома, и профиль обязан делать так же.
## Ярус дороже колонки втрое: подъём по лестнице медленнее ходьбы.
static func _find_spot(def_id: String, w: SimWorld) -> Vector2i:
	var d: BuildingDef = DB.building(def_id)
	if d == null:
		return NO_SPOT
	var home: Vector2i = w.cliff_spawn_cell()
	var home_mark: int = Balance.cell_to_mark(home)
	var best: Vector2i = NO_SPOT
	var best_cost: int = 1 << 30
	for mark: int in range(Balance.TOP_MARK, Balance.BOTTOM_MARK - 1, -1):
		var pidx: int = w.terrain.platform_of_mark(mark)
		if pidx < 0:
			continue
		var mark_cost: int = absi(mark - home_mark) * Balance.TILES_PER_MARK
		if mark_cost >= best_cost:
			continue
		var pl: Dictionary = w.terrain.platforms[pidx]
		# ⚠️ Постройка стоит НА полу, а не в нём: её нижний ряд — на клетку выше
		# пола яруса, иначе `place_error` ищет опору внутри следующего яруса
		# и возвращает ERR_NO_SUPPORT для любой клетки карты. Сверено со
		# стартовыми постройками cliff_01 (склад 2×2 на (9,12), пол марки +2 — 14).
		var y: int = Balance.mark_to_floor_cell_y(mark) - d.size.y
		for x: int in range(int(pl["x0"]), int(pl["x1"]) + 1):
			var cost: int = mark_cost + absi(x - home.x)
			if cost >= best_cost:
				continue
			if w.buildings.place_error(def_id, Vector2i(x, y), w).is_empty():
				best_cost = cost
				best = Vector2i(x, y)
	return best

# --- Записи ---------------------------------------------------------------

## Строка цикла заводится лениво: первый тик цикла её и создаёт.
static func _cycle_row(cyc: Dictionary[int, Dictionary], cycle: int) -> Dictionary:
	if not cyc.has(cycle):
		cyc[cycle] = {"deaths": 0, "samples": 0, "idle": 0, "submerged": 0,
			"at_risk": 0, "ebb_level": 0.0,
			"satiety": 0.0, "warmth": 0.0, "mood": 0.0}
	return cyc[cycle]

func _death_record(w: SimWorld, a: SimAgent, cause: String) -> Dictionary:
	if a == null:
		return {"cause": cause, "cycle": w.clock.cycle, "phase": "?", "mark": 0.0,
			"recalled": false, "satiety": 0, "warmth": 0, "mood": 0,
			"name": "?", "traits": ""}
	return {
		"cause": cause,
		"cycle": w.clock.cycle,
		"phase": SimTypes.phase_name(int(w.clock.phase)),
		"mark": w.agents.agent_mark_f(a, w),
		"recalled": a.recalled,
		"satiety": int(a.needs["satiety"]) / 1000,
		"warmth": int(a.needs["warmth"]) / 1000,
		"mood": int(a.needs["mood"]) / 1000,
		"name": a.agent_name,
		"traits": "|".join(a.trait_ids),
	}

static func _agent_by_id(w: SimWorld, id: int) -> SimAgent:
	for a: SimAgent in w.agents.agents:
		if a.id == id:
			return a
	return null

static func _sum_values(d: Dictionary) -> int:
	var n: int = 0
	for k: Variant in d:
		n += int(d[k])
	return n

# --- Вывод ----------------------------------------------------------------

static func _header() -> String:
	return "profile,seed,end,cycles,score,alive,deaths,drown,storm," \
		+ "built,lost,produced,relics,cards," \
		+ "min_satiety,min_warmth,min_mood," \
		+ "low_satiety_pct,low_warmth_pct,low_mood_pct," \
		+ "zero_satiety,zero_warmth,zero_mood,sick_pct,wet_pct,idle_pct," \
		+ "idle_bag_pct,fill_pct," \
		+ "deepest_mark,storm_min_mark,storm_below,storm_wet_band," \
		+ "storm_damaged,storm_buildings,cargo,survivor_points," \
		+ "creatures,damage,stolen,flooded_storages," \
		+ "rations,catch,scrap,kelp,driftwood," \
		+ "got_scrap,got_catch,got_kelp,got_salt,got_water,wreck5,wreck6"

static func _row(r: Dictionary) -> String:
	return "%s,%d,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%s,%d,%d,%d,%.2f,%.2f,%.2f,%d,%d,%d,%.2f,%.2f,%.2f,%.2f,%.2f,%d,%.2f,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d" % [
		str(r["profile"]), int(r["seed"]), str(r["end"]), int(r["cycles"]),
		int(r["score"]), int(r["alive"]), int(r["deaths"]),
		int(r["drown"]), int(r["storm"]),
		int(r["built"]), int(r["lost"]), int(r["produced"]), int(r["relics"]),
		str(r["cards"]),
		int(r["min_satiety"]), int(r["min_warmth"]), int(r["min_mood"]),
		float(r["low_satiety_pct"]), float(r["low_warmth_pct"]), float(r["low_mood_pct"]),
		int(r["zero_satiety"]), int(r["zero_warmth"]), int(r["zero_mood"]),
		float(r["sick_pct"]), float(r["wet_pct"]), float(r["idle_pct"]),
		float(r["idle_bag_pct"]), float(r["fill_pct"]),
		int(r["deepest_mark"]), float(r["storm_min_mark"]),
		int(r["storm_below"]), int(r["storm_wet_band"]),
		int(r["storm_damaged"]), int(r["storm_buildings"]),
		int(r["cargo"]), int(r["survivor_points"]),
		int(r["creatures"]), int(r["damage"]), int(r["stolen"]),
		int(r["flooded_storages"]),
		int(r["rations"]), int(r["catch"]), int(r["scrap"]),
		int(r["kelp"]), int(r["driftwood"]),
		int(r["got_scrap"]), int(r["got_catch"]), int(r["got_kelp"]),
		int(r["got_salt"]), int(r["got_water"]),
		int(r["wreck5"]), int(r["wreck6"])]

func _summary(agg: Array[Dictionary]) -> void:
	print("---")
	var ids: Array[String] = []
	for r: Dictionary in agg:
		if not ids.has(str(r["profile"])):
			ids.append(str(r["profile"]))
	print("забегов %d, профилей %d" % [agg.size(), ids.size()])

	print("")
	print("%-9s %6s %6s %6s %6s %6s %6s %6s %8s %8s %7s" % ["профиль", "очки",
		"груз", "вайпы", "смерт", "постр", "произв", "дно", "простой",
		"с грузом", "склады"])
	for id: String in ids:
		var g: Array[Dictionary] = _by_profile(agg, id)
		print("%-9s %6.1f %6.1f %6.0f %6.2f %6.1f %6.1f %6.1f %7.1f%% %7.1f%% %6.1f%%" % [
			id, _avg(g, "score"), _avg(g, "cargo"), _count_end(g, "wipe"),
			_avg(g, "deaths"), _avg(g, "built"), _avg(g, "produced"),
			_avg(g, "deepest_mark"), _avg(g, "idle_pct"),
			_avg(g, "idle_bag_pct"), _avg(g, "fill_pct")])

	# research/30 §5.2: доминирование считается на ОДИНАКОВЫХ сидах.
	if ids.size() > 1:
		print("")
		var best_counts: Dictionary[String, int] = {}
		var seeds: Array[int] = []
		for r2: Dictionary in agg:
			if not seeds.has(int(r2["seed"])):
				seeds.append(int(r2["seed"]))
		for s: int in seeds:
			var best: String = ""
			var best_score: int = -999999
			for r3: Dictionary in agg:
				if int(r3["seed"]) != s:
					continue
				if int(r3["score"]) > best_score:
					best_score = int(r3["score"])
					best = str(r3["profile"])
			best_counts[best] = int(best_counts.get(best, 0)) + 1
		print("лучший профиль на сиде (порог тревоги — больше 50%):")
		for id2: String in ids:
			var n: int = int(best_counts.get(id2, 0))
			print("  %-9s %d из %d (%.0f%%)" % [id2, n, seeds.size(),
				100.0 * float(n) / float(maxi(seeds.size(), 1))])

	print("")
	var total_deaths: int = 0
	for r4: Dictionary in agg:
		total_deaths += int(r4["deaths"])
	print("смертей всего %d" % total_deaths)
	var causes: Array[String] = []
	causes.assign(_cause_counts.keys())
	causes.sort()
	for c: String in causes:
		print("  причина %-8s : %d (%.0f%%)" % [c, int(_cause_counts[c]),
			100.0 * float(_cause_counts[c]) / float(maxi(total_deaths, 1))])
	var cycles: Array[int] = []
	cycles.assign(_deaths_by_cycle.keys())
	cycles.sort()
	var by_cycle: PackedStringArray = []
	for c2: int in cycles:
		by_cycle.append("ц%d:%d" % [c2, int(_deaths_by_cycle[c2])])
	print("  по циклам: %s" % " ".join(by_cycle))
	print("потребности (минимум за забег): сытость %.0f, тепло %.0f, дух %.0f" % [
		_avg(agg, "min_satiety"), _avg(agg, "min_warmth"), _avg(agg, "min_mood")])
	print("доля времени ниже порога 30: сытость %.1f%%, тепло %.1f%%, дух %.1f%%" % [
		_avg(agg, "low_satiety_pct"), _avg(agg, "low_warmth_pct"), _avg(agg, "low_mood_pct")])
	print("болезнь %.1f%% времени, мокрые %.1f%%" % [
		_avg(agg, "sick_pct"), _avg(agg, "wet_pct")])
	print("склады заполнены на %.1f%%, простоя с грузом в котомке %.1f%% от всего простоя" % [
		_avg(agg, "fill_pct"), _avg(agg, "idle_bag_pct")])
	print("шторм: минимальная отметка агента на пике %.1f (гибель ниже %d), " % [
		_avg(agg, "storm_min_mark"), Balance.STORM_DEATH_MARK]
		+ "в полосе гибели %.1f, в полосе намокания %.1f, " % [
		_avg(agg, "storm_below"), _avg(agg, "storm_wet_band")]
		+ "построек повреждено %.1f из %.1f" % [
		_avg(agg, "storm_damaged"), _avg(agg, "storm_buildings")])
	print("приход: существ %.1f, урона построек %.1f, украдено %.1f" % [
		_avg(agg, "creatures"), _avg(agg, "damage"), _avg(agg, "stolen")])
	print("склады на конец: провизия %.1f, добыча %.1f, утиль %.1f, водоросли %.1f, плавник %.1f" % [
		_avg(agg, "rations"), _avg(agg, "catch"), _avg(agg, "scrap"),
		_avg(agg, "kelp"), _avg(agg, "driftwood")])
	print("добыто С КАРТЫ за забег: утиль %.1f, добыча %.1f, водоросли %.1f, " % [
		_avg(agg, "got_scrap"), _avg(agg, "got_catch"), _avg(agg, "got_kelp")]
		+ "соль %.1f, вода %.1f" % [_avg(agg, "got_salt"), _avg(agg, "got_water")])
	var w5: float = 0.0
	var w6: float = 0.0
	var runs5: int = 0
	for r5: Dictionary in agg:
		w5 += float(r5["wreck5"])
		w6 += float(r5["wreck6"])
		if int(r5["wreck5"]) > 0 or int(r5["wreck6"]) > 0:
			runs5 += 1
	print("обломки судна: с −5 вынесено %.0f деталей, с −6 — %.0f; " % [w5, w6]
		+ "хоть одна деталь — в %d забегах из %d" % [runs5, agg.size()])

static func _by_profile(agg: Array[Dictionary], id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r: Dictionary in agg:
		if str(r["profile"]) == id:
			out.append(r)
	return out

static func _count_end(agg: Array[Dictionary], kind: String) -> float:
	var n: int = 0
	for r: Dictionary in agg:
		if str(r["end"]) == kind:
			n += 1
	return float(n)

static func _avg(agg: Array[Dictionary], key: String) -> float:
	if agg.is_empty():
		return 0.0
	var s: float = 0.0
	for r: Dictionary in agg:
		s += float(r[key])
	return s / float(agg.size())

static func _end_name(kind: int) -> String:
	match kind:
		SimTypes.RunEnd.SHIP: return "ship"
		SimTypes.RunEnd.WIPE: return "wipe"
		SimTypes.RunEnd.EARLY: return "early"
	return "unfinished"

static func _write(path: String, rows: Array[String]) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("balance_probe: не открыть %s" % path)
		return
	f.store_string("\n".join(rows) + "\n")
	f.close()
	print("CSV: %s" % path)

static func _runs_from_args() -> int:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		return RUNS
	return clampi(int(args[0]), 1, 200)

## Второй аргумент — гонять только один профиль: удобно, когда правишь его
## очередь построек и не хочешь ждать все пять.
static func _profile_from_args() -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	return str(args[1]) if args.size() > 1 else ""
