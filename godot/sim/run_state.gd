class_name RunState
extends RefCounted
## Состояние забега: драфт планов вылазки и разблокировки (docs/00 §10, §11).
## Очки, конец забега и Журнал наполняет этап 11.

## Разблокировки Журнала. На этом этапе наполняются тестом напрямую;
## этап 11 подключит сюда Meta через параметр new_run.
var unlocks: Array[String] = []
var draft: Array[String] = []
var active_card: String = ""
var drafted_this_cycle: bool = false

## Забег закончен и как именно (docs/00 §11.2).
var finished: bool = false
var end_kind: SimTypes.RunEnd = SimTypes.RunEnd.SHIP
## Досрочный уход: судно приходит в следующем цикле, очки ×0.75.
var leaving_early: bool = false
var ship_cycle: int = Balance.CYCLES_PER_RUN
var ship_arrived: bool = false
## Снимок очков на МОМЕНТ прибытия судна — пик Высокой воды
## (SimClock.high_peak_tick, docs/00 §11.2). Именно тогда вода стоит на плато
## фазы, в 12-м цикле — на сизигийном +2, и склады на +1..+2 под ней.
var score_snapshot: Dictionary = {}
## Эпитафии погибших — для Журнала.
var deaths: Array[Dictionary] = []

## Счётчики забега для отчёта run_ended (REL-09, research/27 §2.3). Собраны
## в одном месте намеренно: по ним строятся достижения Steam, экран итогов
## и баланс-CSV, а каждое поле, добавленное ПОСЛЕ релиза, — правка sim, сейва
## и миграции сейвов сразу. Пока сейвов у игроков нет, весь набор стоит
## одного коммита.
##
## Произведено станциями за ВЕСЬ забег: ProductionSystem копит своё за цикл
## и обнуляет на границе. Добыча из депозитов сюда не идёт — это «сделано»,
## а не «поднято».
var produced: Dictionary[String, int] = {}
## Карты вылазки в порядке выбора, по одной на цикл.
var cards_picked: Array[String] = []
## Типы кризисов (SimTypes.CrisisType), дожившие с колонией до конца цикла.
var crises_survived: Array[int] = []
## Достроено колонией (стартовые постройки не в счёт) и потеряно навсегда.
## Снос игроком — не потеря: это его решение, а не беда забега.
var buildings_built: int = 0
var buildings_lost: int = 0
## Самая низкая отметка, где побывал хоть один агент. Отметки растут вверх,
## поэтому глубина — это минимум; TOP_MARK значит «никто не спускался».
var deepest_mark: int = Balance.TOP_MARK
## Живые на МОМЕНТ снимка очков, а не на конец забега: между пиком Высокой
## воды и границей фазы кто-то ещё может утонуть, и тогда «живых» в отчёте
## стало бы меньше, чем оплачено строкой survivors. −1 = снимка не было.
var alive_snapshot: int = -1

const UNLOCK_DRAFT_PLUS: String = "u_draft_plus"
## Причины гибели: их читает и отчёт (drowned), и Журнал. Строкой в двух
## местах — верный способ разойтись на опечатке.
const CAUSE_DROWN: String = "drown"
const CAUSE_STORM: String = "storm"
const DRAFT_SIZE: int = 3
const DRAFT_SIZE_PLUS: int = 4

var _pending: Array[SimEvent] = []

func new_run(unlock_list: Array[String]) -> void:
	unlocks = unlock_list.duplicate()
	draft.clear()
	active_card = ""
	drafted_this_cycle = false
	finished = false
	end_kind = SimTypes.RunEnd.SHIP
	leaving_early = false
	ship_cycle = Balance.CYCLES_PER_RUN
	ship_arrived = false
	score_snapshot.clear()
	deaths.clear()
	produced.clear()
	cards_picked.clear()
	crises_survived.clear()
	buildings_built = 0
	buildings_lost = 0
	deepest_mark = Balance.TOP_MARK
	alive_snapshot = -1
	_pending.clear()

func has_unlock(id: String) -> bool:
	return unlocks.has(id)

# --- Драфт ----------------------------------------------------------------

## Драфт собирается на каждом Спаде. Базовые карты в пуле всегда, редкие —
## только после разблокировки (docs/00 §10).
func start_draft(w: SimWorld) -> void:
	draft.clear()
	drafted_this_cycle = false
	var pool: Array[String] = []
	for id: String in DB.card_ids():
		var c: CardDef = DB.card(id)
		if c.rarity == "rare" and not has_unlock(c.unlock_id):
			continue
		pool.append(id)
	var take: int = DRAFT_SIZE_PLUS if has_unlock(UNLOCK_DRAFT_PLUS) else DRAFT_SIZE
	# Выбор без повторов: тянем из копии пула, удаляя выбранное.
	for i: int in mini(take, pool.size()):
		var idx: int = w.rng.randi_range(0, pool.size() - 1)
		draft.append(pool[idx])
		pool.remove_at(idx)
	if draft.is_empty():
		return
	_pending.append(SimEvent.make("draft_ready", {"cards": draft.duplicate()}))

## Возвращает false, если карты нет в текущем драфте.
func pick_card(card_id: String, w: SimWorld) -> bool:
	if drafted_this_cycle or not draft.has(card_id):
		return false
	drafted_this_cycle = true
	active_card = card_id
	cards_picked.append(card_id)
	_apply(card_id, w)
	_pending.append(SimEvent.make("card_picked", {"card": card_id}))
	return true

## Защита от «игрок не выбрал за весь Спад»: автопауза этого не допускает,
## но без страховки цикл остался бы без карты и без объяснения.
func auto_pick_if_needed(w: SimWorld) -> void:
	if drafted_this_cycle or draft.is_empty():
		return
	pick_card(draft[0], w)

# --- Эффекты --------------------------------------------------------------

## Эффекты складываются в cycle_modifiers — общий «блокнот» цикла, который
## читают все системы. Прямых правок чужого состояния здесь ровно три:
## плато отлива, длительность фазы и метка реликвии.
func _apply(card_id: String, w: SimWorld) -> void:
	var c: CardDef = DB.card(card_id)
	if c == null:
		return
	for key: String in c.effects:
		if not CardKeys.is_known(key):
			push_error("карта %s: неизвестный ключ '%s'" % [card_id, key])
			continue
		w.cycle_modifiers[key] = float(c.effects[key])
	w.refresh_cycle_effects()
	if float(c.effects.get("next_spring_add", 0.0)) > 0.0:
		w.crisis.next_spring_bonus += float(c.effects["next_spring_add"])
	if float(c.effects.get("mark_relic", 0.0)) > 0.0:
		_mark_relic(w)

## «Находка»: помечает случайный глубокий депозит гарантированной реликвией.
func _mark_relic(w: SimWorld) -> void:
	var candidates: Array[int] = []
	for i: int in w.terrain.deposits.size():
		var d: Dictionary = w.terrain.deposits[i]
		if str(d["kind"]) != "ruins_deep" or bool(d["relic_taken"]):
			continue
		if Balance.cell_to_mark(d["cell"] as Vector2i) > Balance.RELIC_MARK_MAX:
			continue
		candidates.append(i)
	if candidates.is_empty():
		return
	var idx: int = int(w.rng.pick(candidates))
	w.terrain.deposits[idx]["relic_marked"] = true
	_pending.append(SimEvent.make("deposit_changed",
		{"id": int(w.terrain.deposits[idx]["id"])}))

## Эффект живёт ровно один цикл (docs/00 §10).
func end_cycle(w: SimWorld) -> Dictionary:
	var used: String = active_card
	w.cycle_modifiers.clear()
	w.refresh_cycle_effects()
	active_card = ""
	draft.clear()
	drafted_this_cycle = false
	return {"card": used}

# --- Конец забега ---------------------------------------------------------

## Досрочный уход доступен с 8-го цикла: судно вызывается на следующий,
## очки ×0.75 (docs/00 §11.2). Возвращает false, если рано.
func leave_early(w: SimWorld) -> bool:
	if finished or leaving_early or w.clock.cycle < Balance.EARLY_LEAVE_MIN_CYCLE:
		return false
	leaving_early = true
	ship_cycle = mini(w.clock.cycle + 1, Balance.CYCLES_PER_RUN)
	return true

## Немедленная сдача по решению игрока. Отдельный исход, а не WIPE: игрок,
## вышедший из паузы с шестью живыми, не должен читать «Колония погибла»
## (docs/00 §11.2, исход 4). Множитель тот же, что у гибели.
func surrender(w: SimWorld) -> void:
	_finish(SimTypes.RunEnd.SURRENDER, w)

## Эпитафия по docs/03 §3.5: имя, ЧЕРТЫ, ЦИКЛ и причина гибели. Черты и цикл
## заводятся здесь, а не в UI: после забега агента уже нет, а профиль без этих
## полей потом потребовал бы миграции (A1.5).
func note_death(a: SimAgent, cause: String, cycle: int) -> void:
	var traits: Array[String] = []
	traits.assign(a.trait_ids)
	deaths.append({"name": a.agent_name, "cause": cause, "bio": a.bio_key,
		"traits": traits, "cycle": cycle})

# --- Счётчики забега ------------------------------------------------------

## Станция выдала предмет (ProductionSystem._produce).
func note_produced(item_id: String, n: int) -> void:
	produced[item_id] = int(produced.get(item_id, 0)) + n

## Колония достроила постройку (BuildingSystem.advance_construction).
func note_building_built() -> void:
	buildings_built += 1

## Постройку уничтожило миром — сушилу сорвало штормом (BuildingSystem).
func note_building_lost() -> void:
	buildings_lost += 1

## Цикл с кризисом дожит до конца (CrisisSystem.on_cycle_ended). Вайп сюда
## не попадает: забег заканчивается раньше, чем цикл.
func note_crisis_survived(type: int) -> void:
	crises_survived.append(type)

## Глубина снимается каждый тик, а не по состоянию на конец забега: агент
## успевает спуститься и вернуться внутри одного отлива, и к финалу от этого
## похода не остаётся следов.
func _note_marks(w: SimWorld) -> void:
	for a: SimAgent in w.agents.agents:
		if not a.is_alive():
			continue
		var m: int = int(floor(w.agents.agent_mark_f(a, w)))
		if m < deepest_mark:
			deepest_mark = m

## Утонувшие считаются из эпитафий, а не своим счётчиком: причина уже
## записана в deaths, а два источника одних и тех же чисел разъезжаются.
func _deaths_with_cause(cause: String) -> int:
	var n: int = 0
	for d: Dictionary in deaths:
		if str(d["cause"]) == cause:
			n += 1
	return n

## Порядок ключей в сейве обязан быть стабильным: хеш состояния (golden-тест,
## TEST-05) считается по JSON, и порядок вставки в словарь сдвигал бы его
## без единой правки правил.
func produced_sorted() -> Dictionary:
	var out: Dictionary = {}
	var keys: Array[String] = []
	keys.assign(produced.keys())
	keys.sort()
	for k: String in keys:
		out[k] = int(produced[k])
	return out

func _crises_count(type: int) -> int:
	var n: int = 0
	for c: int in crises_survived:
		if c == type:
			n += 1
	return n

## Проверяется каждый тик: пустая колония — немедленно, судно — на пике
## Высокой воды. ПОРОГ живых сюда не входит: он считается только на границе
## цикла (см. on_phase_ended).
##
## ⚠️ Зовётся из SimWorld.tick ПОСЛЕ tide.update — иначе снимок очков считался
## бы по уровню прошлого тика. Это и есть контракт «момента» из docs/02 §4.1.
func tick(w: SimWorld) -> void:
	if finished:
		return
	_note_marks(w)
	# Ноль живых — ждать границы нечего: восстановиться колонии уже нечем,
	# и оставшиеся минуты цикла игрок смотрел бы на пустой утёс.
	if w.agents.alive_count() == 0:
		_finish(SimTypes.RunEnd.WIPE, w)
		return
	if w.clock.at_high_peak() and w.clock.cycle >= ship_cycle:
		_arrive(w)

func on_phase_ended(phase: int, w: SimWorld) -> void:
	if finished or phase != int(SimTypes.Phase.HIGH):
		return
	# ⚠️ Часы УЖЕ перевели счётчик: конец HIGH — это конец цикла, и здесь
	# clock.cycle указывает на следующий. Закончился cycle − 1.
	if not ship_arrived and w.clock.cycle - 1 >= ship_cycle:
		# Страховка на случай, когда пик не наблюдался ни на одном тике
		# (фаза короче окна подъёма): забег обязан закончиться.
		_arrive(w)
	if ship_arrived:
		_finish(SimTypes.RunEnd.SHIP, w)
		return
	# Порог колонии — ПОСЛЕ судна: доплывший забег засчитывается судном, даже
	# если до берега дошёл один человек. И только на границе цикла: смерть
	# посреди Высокой воды не обязана обрывать цикл, а новичок приходит именно
	# здесь, в agents.on_cycle_ended, то есть раньше этой проверки (docs/00
	# §11.2, исход 2).
	if w.agents.alive_count() < Balance.WIPE_THRESHOLD:
		_finish(SimTypes.RunEnd.WIPE, w)

## Прибытие судна: снимок очков по ТЕКУЩЕМУ уровню воды. Идемпотентно.
## Момент выбирает вызывающий — см. docs/02 §4.1.
func _arrive(w: SimWorld) -> void:
	if finished or ship_arrived:
		return
	ship_arrived = true
	score_snapshot = compute_score(w)
	alive_snapshot = w.agents.alive_count()
	_pending.append(SimEvent.make("ship_arrived", {}))

func _finish(kind: SimTypes.RunEnd, w: SimWorld) -> void:
	if finished:
		return
	finished = true
	end_kind = kind
	if score_snapshot.is_empty():
		score_snapshot = compute_score(w)
	if alive_snapshot < 0:
		alive_snapshot = w.agents.alive_count()
	var report: Dictionary = _final_report(w)
	_pending.append(SimEvent.make("run_ended", {"report": report}))

## Разбивка и итог считаются ИЗ ОДНОГО источника: сумма получается сложением
## разбивки, а не отдельной формулой — иначе они разъедутся на округлениях.
func compute_score(w: SimWorld) -> Dictionary:
	var cargo: int = 0
	var relics: int = 0
	for s: Dictionary in w.storage.storages:
		# Затопленный в момент судна склад не считается вовсе.
		if Balance.is_mark_flooded(Balance.cell_to_mark(s["cell"] as Vector2i),
				w.tide.level):
			continue
		for v: Variant in s["stacks"] as Array:
			var st: Dictionary = v as Dictionary
			var def: ItemDef = DB.item(str(st["item_id"]))
			if def == null:
				continue
			cargo += def.ship_points * int(st["count"])
			if str(st["item_id"]) == "relic":
				relics += int(st["count"])
	var alive: int = w.agents.alive_count()
	return {
		"cargo": cargo,
		"survivors": alive * Balance.POINTS_PER_SURVIVOR,
		"relics": relics * Balance.POINTS_PER_RELIC_BONUS,
	}

func _final_report(w: SimWorld) -> Dictionary:
	var breakdown: Dictionary = score_snapshot.duplicate()
	var raw: int = 0
	var keys: Array[String] = []
	keys.assign(breakdown.keys())
	keys.sort()
	for k: String in keys:
		raw += int(breakdown[k])
	var mult: float = 1.0
	if end_kind == SimTypes.RunEnd.WIPE or end_kind == SimTypes.RunEnd.SURRENDER:
		mult = Balance.SCORE_MULT_WIPE
	elif leaving_early:
		mult = Balance.SCORE_MULT_EARLY
	var total: int = int(float(raw) * mult)
	if mult < 1.0:
		breakdown["penalty"] = total - raw       # отрицательная строка разбивки
	# ⚠️ Не w.clock.cycle: забег кончается на границе HIGH→EBB, и часы к тому
	# моменту уже перевели счётчик на следующий цикл. Прожит — предыдущий.
	var lived: int = ship_cycle if end_kind == SimTypes.RunEnd.SHIP else w.clock.cycle
	return {
		"end": int(end_kind), "cycles": lived, "seed": w.rng.seed_value,
		"score": total, "raw_score": raw, "breakdown": breakdown,
		"early": leaving_early, "deaths": deaths.duplicate(true),
		"relics": int(score_snapshot.get("relics", 0)) / Balance.POINTS_PER_RELIC_BONUS,
		# REL-09. Ниже — поля, по которым считаются достижения Steam
		# (research/27 §2.3): предикаты читают отчёт и ничего больше.
		"alive": alive_snapshot,
		"dead": deaths.size(),
		"drowned": _deaths_with_cause(CAUSE_DROWN),
		"produced": produced_sorted(),
		"cards_picked": cards_picked.duplicate(),
		"deepest_mark": deepest_mark,
		"crises_survived": crises_survived.duplicate(),
		"storms_survived": _crises_count(int(SimTypes.CrisisType.STORM)),
		"buildings_built": buildings_built,
		"buildings_lost": buildings_lost,
	}

func drain_events() -> Array[SimEvent]:
	var out: Array[SimEvent] = _pending
	_pending = []
	return out

# --- Сериализация ---------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"unlocks": unlocks.duplicate(),
		"draft": draft.duplicate(),
		"active_card": active_card,
		"drafted": drafted_this_cycle,
		"finished": finished, "end_kind": int(end_kind),
		"leaving_early": leaving_early, "ship_cycle": ship_cycle,
		"ship_arrived": ship_arrived,
		"score_snapshot": score_snapshot.duplicate(),
		"deaths": deaths.duplicate(true),
		"produced": produced_sorted(),
		"cards_picked": cards_picked.duplicate(),
		"crises_survived": crises_survived.duplicate(),
		"buildings_built": buildings_built,
		"buildings_lost": buildings_lost,
		"deepest_mark": deepest_mark,
		"alive_snapshot": alive_snapshot,
	}

func from_dict(d: Dictionary) -> void:
	unlocks.clear()
	for v: Variant in d.get("unlocks", []) as Array:
		unlocks.append(str(v))
	draft.clear()
	for c: Variant in d.get("draft", []) as Array:
		draft.append(str(c))
	active_card = str(d.get("active_card", ""))
	drafted_this_cycle = bool(d.get("drafted", false))
	finished = bool(d.get("finished", false))
	end_kind = int(d.get("end_kind", 0)) as SimTypes.RunEnd
	leaving_early = bool(d.get("leaving_early", false))
	ship_cycle = int(d.get("ship_cycle", Balance.CYCLES_PER_RUN))
	ship_arrived = bool(d.get("ship_arrived", false))
	score_snapshot.clear()
	for k: Variant in d.get("score_snapshot", {}) as Dictionary:
		score_snapshot[str(k)] = int((d["score_snapshot"] as Dictionary)[k])
	deaths.clear()
	for v: Variant in d.get("deaths", []) as Array:
		var dd: Dictionary = v as Dictionary
		var tr: Array[String] = []
		for tv: Variant in dd.get("traits", []) as Array:
			tr.append(str(tv))
		deaths.append({"name": str(dd["name"]), "cause": str(dd["cause"]),
			"bio": str(dd.get("bio", "")), "traits": tr,
			"cycle": int(dd.get("cycle", 0))})
	# Отсутствующие ключи — это сейв, записанный до REL-09: он честно грузится
	# с нулевыми счётчиками, потому что менять save_version ради добавленных
	# полей значило бы выбросить сейв целиком.
	produced.clear()
	for pk: Variant in d.get("produced", {}) as Dictionary:
		produced[str(pk)] = int((d["produced"] as Dictionary)[pk])
	cards_picked.clear()
	for cv: Variant in d.get("cards_picked", []) as Array:
		cards_picked.append(str(cv))
	crises_survived.clear()
	for xv: Variant in d.get("crises_survived", []) as Array:
		crises_survived.append(int(xv))
	buildings_built = int(d.get("buildings_built", 0))
	buildings_lost = int(d.get("buildings_lost", 0))
	deepest_mark = int(d.get("deepest_mark", Balance.TOP_MARK))
	alive_snapshot = int(d.get("alive_snapshot", -1))
	_pending.clear()
