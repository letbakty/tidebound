extends RefCounted
## Приёмка RETENTION-pass, блок 1: поражение как исход забега.
##
## До этой правки проигрыш в игре не существовал ни для одной стратегии:
## забег кончался только при ПОЛНОМ вымирании, а приток новичков делал его
## недостижимым — 0 вайпов на 100 забегов (docs/balance.md, итерация 1).
## Здесь проверяется ровно то, что этого больше нельзя сказать: порог живых,
## его момент, гейт новичка и честные исходы «сдался» и «ушёл досрочно».

const CLIFF: String = "res://data/cliffs/cliff_01.tres"

static func _world(seed_value: int) -> SimWorld:
	var w: SimWorld = SimWorld.new()
	w.new_run(seed_value, load(CLIFF) as CliffDef, [] as Array[String])
	w.events_out.clear()
	return w

## Оставляет в колонии ровно n живых, остальных убивает.
static func _keep_alive(w: SimWorld, n: int) -> void:
	var left: int = n
	for a: SimAgent in w.agents.agents.duplicate():
		if not a.is_alive():
			continue
		if left > 0:
			left -= 1
			continue
		w.agents.kill(a, "test", w)

## Тикает мир, вылавливая отчёт конца забега. events_out чистим сами:
## TestCtx.run_ticks выбрасывает события, а нам нужно именно run_ended.
static func _tick_until_end(w: SimWorld, max_ticks: int) -> Dictionary:
	var report: Dictionary = {}
	for i: int in max_ticks:
		w.tick()
		for e: SimEvent in w.events_out:
			if e.type == "run_ended":
				report = e.data["report"] as Dictionary
		w.events_out.clear()
		if not report.is_empty():
			return report
	return report

## Через одну границу цикла — или до конца забега, что случится раньше.
static func _tick_past_cycle_edge(w: SimWorld) -> Dictionary:
	var was: int = w.clock.cycle
	var report: Dictionary = {}
	for i: int in Balance.TICKS_PER_CYCLE * 2:
		w.tick()
		for e: SimEvent in w.events_out:
			if e.type == "run_ended":
				report = e.data["report"] as Dictionary
		w.events_out.clear()
		if not report.is_empty() or w.clock.cycle > was:
			return report
	return report

# --- Порог живых ----------------------------------------------------------

## Главная проверка блока: забег заканчивается НА ГРАНИЦЕ цикла, а не в тот
## тик, когда упал последний человек. Смерть посреди Высокой воды не обязана
## обрывать цикл: у колонии есть остаток цикла, и именно на границе решается,
## жива она или нет (docs/00 §11.2, исход 2).
static func test_threshold_fires_only_at_cycle_edge(t: TestCtx) -> void:
	var w: SimWorld = _world(5101)
	t.run_ticks(w, 100)
	_keep_alive(w, Balance.WIPE_THRESHOLD - 1)
	t.check_eq(w.agents.alive_count(), Balance.WIPE_THRESHOLD - 1,
		"в колонии осталось меньше порога")
	t.run_ticks(w, 50)
	t.check(not w.run_state.finished,
		"посреди цикла забег продолжается, хотя живых уже меньше порога")
	_tick_past_cycle_edge(w)
	t.check(w.run_state.finished, "на границе цикла забег провален")
	t.check_eq(int(w.run_state.end_kind), int(SimTypes.RunEnd.WIPE),
		"исход — гибель колонии")

## Ровно порог — ещё не поражение: на этом числе показывается предупреждение,
## а не итог. Иначе тост «колония на грани» появлялся бы вместе с экраном
## конца забега и не значил бы ничего.
static func test_threshold_is_exclusive(t: TestCtx) -> void:
	var w: SimWorld = _world(5102)
	t.run_ticks(w, 100)
	_keep_alive(w, Balance.WIPE_THRESHOLD)
	_tick_past_cycle_edge(w)
	t.check(not w.run_state.finished,
		"с %d живыми колония переживает границу цикла" % Balance.WIPE_THRESHOLD)

## Пустая колония — исключение: ждать границы нечего, восстановиться нечем.
static func test_empty_colony_ends_at_once(t: TestCtx) -> void:
	var w: SimWorld = _world(5103)
	t.run_ticks(w, 100)
	_keep_alive(w, 0)
	t.run_ticks(w, 1)
	t.check(w.run_state.finished, "ноль живых заканчивает забег в тот же тик")
	t.check_eq(int(w.run_state.end_kind), int(SimTypes.RunEnd.WIPE),
		"исход — гибель всех")

## Отчёт проигрыша обязан быть ПОЛНЫМ: экран итога, Журнал и достижения
## Steam читают одни и те же поля, и отсутствие любого из них при поражении
## — это пустой экран ровно в тот момент, когда игроку нужнее всего понять,
## что он получил.
static func test_threshold_report_has_same_fields_as_ship(t: TestCtx) -> void:
	var ship_report: Dictionary = _tick_until_end(_world(5104),
		Balance.TICKS_PER_CYCLE * 20)
	t.check(not ship_report.is_empty(), "эталонный забег дошёл до судна")

	var w: SimWorld = _world(5104)
	t.run_ticks(w, 100)
	_keep_alive(w, Balance.WIPE_THRESHOLD - 1)
	var lost: Dictionary = _tick_past_cycle_edge(w)
	t.check(not lost.is_empty(), "пороговое поражение отдало отчёт")
	if lost.is_empty():
		return
	var keys: Array = ship_report.keys()
	keys.sort()
	for k: Variant in keys:
		t.check(lost.has(k), "в отчёте поражения нет поля «%s»" % str(k))
	t.check_eq(int(lost["end"]), int(SimTypes.RunEnd.WIPE), "исход записан")
	t.check(int(lost["score"]) <= int(lost["raw_score"]),
		"очки урезаны множителем гибели")

# --- Новичок --------------------------------------------------------------

## Приток людей помогает растущей колонии и не воскрешает умирающую. Раньше
## работало наоборот: единственное условие — «живых больше нуля», то есть
## механика тем сильнее, чем хуже дела.
static func test_newcomer_needs_min_alive(t: TestCtx) -> void:
	# Гейт новичка не ниже порога поражения. Равенство допустимо и даже
	# желанно: колония ровно на пороге ещё может добрать человека — это и
	# есть «до конца цикла ИЛИ до прихода человека» из текста тоста. А вот
	# гейт НИЖЕ порога был бы бессмыслицей: пополнение приходило бы к тем,
	# кого забег уже похоронил на ближайшей границе.
	t.check(Balance.NEWCOMER_MIN_ALIVE >= Balance.WIPE_THRESHOLD,
		"гейт новичка (%d) не ниже порога поражения (%d)"
		% [Balance.NEWCOMER_MIN_ALIVE, Balance.WIPE_THRESHOLD])
	# Ниже гейта: двести попыток подряд, все препятствия кроме численности
	# сняты — колония обязана остаться прежней.
	var edge: SimWorld = _cheerful_colony(5105, Balance.NEWCOMER_MIN_ALIVE - 1)
	var before: int = edge.agents.alive_count()
	for i: int in 200:
		edge.agents.set("_last_newcomer_cycle", -99)
		edge.agents.call("_try_newcomer", edge)
	t.check_eq(edge.agents.alive_count(), before,
		"с %d живыми новичок не приходит и за двести попыток"
		% (Balance.NEWCOMER_MIN_ALIVE - 1))

	# И ровно на гейте механика обязана работать: правка сужает условие,
	# а не выключает пополнение вовсе.
	var ok: SimWorld = _cheerful_colony(5105, Balance.NEWCOMER_MIN_ALIVE)
	var grew: bool = false
	for i2: int in 200:
		ok.agents.set("_last_newcomer_cycle", -99)
		if int(ok.agents.call("_try_newcomer", ok)) >= 0:
			grew = true
			break
	t.check(grew, "с %d живыми новичок приходить умеет"
		% Balance.NEWCOMER_MIN_ALIVE)

## Колония из n довольных людей: дух выше порога, кулдаун снят — для
## _try_newcomer остаётся ровно одно препятствие, численность.
static func _cheerful_colony(seed_value: int, n: int) -> SimWorld:
	var w: SimWorld = _world(seed_value)
	_keep_alive(w, n)
	for a: SimAgent in w.agents.agents:
		if a.is_alive():
			a.needs["mood"] = Balance.NEED_MAX_MILLI
	return w

# --- Исходы «сдался» и «ушёл досрочно» ------------------------------------

## Сдача и досрочный уход — РАЗНЫЕ решения игрока с разной ценой, и экран
## итога обязан называть их по-разному. До правки сдача отображалась в WIPE,
## и игрок, вышедший из паузы с шестью живыми, читал «Колония погибла».
static func test_surrender_and_leave_early_differ(t: TestCtx) -> void:
	var quit_report: Dictionary = _surrendered_report(5106)
	t.check_eq(int(quit_report.get("end", -1)), int(SimTypes.RunEnd.SURRENDER),
		"сдача — свой исход")
	t.check(not bool(quit_report.get("early", true)),
		"и не выдаёт себя за досрочный уход")

	var early: SimWorld = _world(5106)
	for i: int in Balance.TICKS_PER_CYCLE * 30:
		early.tick()
		early.events_out.clear()
		if early.clock.cycle >= Balance.EARLY_LEAVE_MIN_CYCLE:
			break
	t.check(early.run_state.leave_early(early), "с 8-го цикла уйти можно")
	var early_report: Dictionary = {}
	for i2: int in Balance.TICKS_PER_CYCLE * 4:
		early.tick()
		for e: SimEvent in early.events_out:
			if e.type == "run_ended":
				early_report = e.data["report"] as Dictionary
		early.events_out.clear()
		if not early_report.is_empty():
			break
	t.check_eq(int(early_report.get("end", -1)), int(SimTypes.RunEnd.SHIP),
		"досрочный уход — всё-таки судно")
	t.check(bool(early_report.get("early", false)), "и помечен досрочным")
	t.check(int(early_report.get("end", -2)) != int(quit_report.get("end", -1)),
		"исходы разные")

## Сдача через ту же команду, что и у игрока, вместе с её отчётом.
static func _surrendered_report(seed_value: int) -> Dictionary:
	var w: SimWorld = _world(seed_value)
	for i: int in 100:
		w.tick()
		w.events_out.clear()
	w.apply_command({"kind": "surrender"})
	return _tick_until_end(w, 2)

## Множители тоже разные, и это единственное место, где они сравниваются
## между собой: 0.3 против 0.75 — разница в цене решения.
static func test_surrender_and_early_multipliers_differ(t: TestCtx) -> void:
	t.check(Balance.SCORE_MULT_WIPE < Balance.SCORE_MULT_EARLY,
		"сдача обязана стоить дороже досрочного ухода")
	var report: Dictionary = _surrendered_report(5107)
	var raw: int = int(report.get("raw_score", 0))
	t.check_eq(int(report.get("score", -1)),
		int(float(raw) * Balance.SCORE_MULT_WIPE),
		"сдача считается по множителю гибели")

## Каждый исход обязан иметь свой человеческий заголовок — иначе четвёртый
## исход молча читался бы как «Колония погибла».
static func test_every_outcome_is_named(t: TestCtx) -> void:
	var seen: Dictionary[String, bool] = {}
	for kind: int in SimTypes.RunEnd.values():
		var key: String = RunSummary._outcome_key(kind)
		t.check(not seen.has(key), "исход %d делит ключ %s" % [kind, key])
		seen[key] = true
	t.check_eq(seen.size(), SimTypes.RunEnd.values().size(),
		"по заголовку на исход")
