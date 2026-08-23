extends RefCounted
## Приёмка этапа 10: драфт на каждом Спаде и эффекты карт ровно на один цикл.

const CLIFF: String = "res://data/cliffs/cliff_01.tres"

static func _cliff() -> CliffDef:
	return load(CLIFF) as CliffDef

static func _world(seed_value: int, unlocks: Array[String] = []) -> SimWorld:
	var w: SimWorld = SimWorld.new()
	w.new_run(seed_value, _cliff(), unlocks)
	w.events_out.clear()
	return w

## Прокручивает до нужной фазы. Считать тики нельзя: карты меняют длину отлива.
static func _until(t: TestCtx, w: SimWorld, cycle: int, phase: SimTypes.Phase) -> void:
	var guard: int = 0
	while guard < Balance.TICKS_PER_CYCLE * 20:
		if w.clock.cycle == cycle and w.clock.phase == phase:
			return
		t.run_ticks(w, 1)
		guard += 1

## Заново начинает цикл с нужной картой: драфт подменяем напрямую.
static func _force_card(t: TestCtx, w: SimWorld, card_id: String) -> void:
	w.run_state.draft = [card_id]
	w.run_state.drafted_this_cycle = false
	w.apply_command({"kind": "pick_card", "card": card_id})
	t.run_ticks(w, 1)

# --- Данные ---------------------------------------------------------------

static func test_cards_match_spec(t: TestCtx) -> void:
	t.check_eq(DB.card_ids().size(), 12, "все 12 карт docs/00 §10")
	var careful: CardDef = DB.card("careful")
	t.check_approx(float(careful.effects["recall_earlier_sec"]), 30.0, 0.01,
		"«Осторожно»: возврат на 30 с раньше")
	t.check_approx(float(careful.effects["drown_bonus_sec"]), 3.0, 0.01,
		"и +3 с под водой")
	t.check_approx(float(careful.effects["gather_speed_mult"]), 0.8, 0.01,
		"и добыча на 20% медленнее")
	t.check_eq(DB.card("deep_dive").rarity, "base", "«Глубокий заход» базовая")
	t.check_eq(DB.card("great_ebb").unlock_id, "u_card_ebb", "«Великий отлив» под 🔒")
	t.check_eq(DB.card("calm_water").unlock_id, "u_card_calm", "«Тихая вода» под 🔒")
	t.check_eq(DB.card("the_find").unlock_id, "u_card_find", "«Находка» под 🔒")

static func test_card_keys_are_known(t: TestCtx) -> void:
	for id: String in DB.card_ids():
		for key: String in DB.card(id).effects:
			t.check(CardKeys.is_known(key), "карта %s: ключ '%s' не из CardKeys" % [id, key])

# --- Драфт ----------------------------------------------------------------

static func test_draft_every_ebb(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	t.check_eq(w.run_state.draft.size(), RunState.DRAFT_SIZE,
		"драфт из трёх карт есть уже на первом Спаде")
	for c: int in 3:
		_until(t, w, w.clock.cycle + 1, SimTypes.Phase.EBB)
		t.run_ticks(w, 1)
		t.check_eq(w.run_state.draft.size(), RunState.DRAFT_SIZE,
			"на Спаде цикла %d снова три карты" % w.clock.cycle)
	# Без разблокировок редкие карты в пул не попадают.
	for id: String in w.run_state.draft:
		t.check_eq(DB.card(id).rarity, "base", "в пуле только базовые карты")

static func test_draft_is_deterministic(t: TestCtx) -> void:
	var a: SimWorld = _world(777)
	var b: SimWorld = _world(777)
	t.check_eq(a.run_state.draft, b.run_state.draft, "один сид — один драфт")
	var c: SimWorld = _world(778)
	t.check(c.run_state.draft != a.run_state.draft or c.run_state.draft.size() < 3,
		"другой сид — другой драфт")

static func test_draft_has_no_duplicates(t: TestCtx) -> void:
	var w: SimWorld = _world(5, ["u_card_ebb", "u_card_calm", "u_card_find"])
	for c: int in 6:
		var seen: Dictionary[String, bool] = {}
		for id: String in w.run_state.draft:
			t.check(not seen.has(id), "карта %s не повторяется в драфте" % id)
			seen[id] = true
		_until(t, w, w.clock.cycle + 1, SimTypes.Phase.EBB)
		t.run_ticks(w, 1)

static func test_draft_plus_gives_four(t: TestCtx) -> void:
	var w: SimWorld = _world(7, [RunState.UNLOCK_DRAFT_PLUS,
		"u_card_ebb", "u_card_calm", "u_card_find"])
	t.check_eq(w.run_state.draft.size(), RunState.DRAFT_SIZE_PLUS,
		"с разблокировкой драфт из четырёх")

static func test_draft_ready_event(t: TestCtx) -> void:
	var w: SimWorld = SimWorld.new()
	w.new_run(9, _cliff())
	var found: bool = false
	# Событие драфта выгребается первым же тиком после старта забега.
	w.tick()
	for e: SimEvent in w.events_out:
		if e.type == "draft_ready":
			found = true
			t.check_eq((e.data["cards"] as Array).size(), 3, "в событии три карты")
	t.check(found, "draft_ready эмитится")

## Страховка: если игрок не выбрал за весь Спад, карта берётся сама.
static func test_auto_pick_at_end_of_ebb(t: TestCtx) -> void:
	var w: SimWorld = _world(11)
	t.check(w.run_state.active_card.is_empty(), "пока ничего не выбрано")
	_until(t, w, 1, SimTypes.Phase.LOW)
	t.run_ticks(w, 2)
	t.check(not w.run_state.active_card.is_empty(),
		"к концу Спада карта выбрана автоматически (%s)" % w.run_state.active_card)

static func test_pick_rejects_card_outside_draft(t: TestCtx) -> void:
	var w: SimWorld = _world(13)
	t.check(not w.run_state.pick_card("great_ebb", w),
		"карту не из драфта выбрать нельзя")
	var id: String = w.run_state.draft[0]
	t.check(w.run_state.pick_card(id, w), "а свою — можно")
	t.check(not w.run_state.pick_card(w.run_state.draft[1], w),
		"вторую за цикл — уже нет")

# --- Эффекты --------------------------------------------------------------

static func test_deep_dive(t: TestCtx) -> void:
	var w: SimWorld = _world(17)
	_force_card(t, w, "deep_dive")
	t.check_approx(w.tide.low_plateau, -10.0, 0.01, "плато отлива опустилось до −10")
	t.check_eq(w.clock.phase_len(SimTypes.Phase.LOW), 1125, "и отлив короче на 25%")
	_until(t, w, 1, SimTypes.Phase.LOW)
	t.run_ticks(w, 600)
	t.check_approx(w.tide.level, -10.0, 0.05, "вода реально уходит до −10")
	# Эффект живёт ровно один цикл.
	_until(t, w, 2, SimTypes.Phase.LOW)
	t.check_approx(w.tide.low_plateau, Balance.LOW_LEVEL, 0.01,
		"на следующем цикле плато вернулось")

static func test_great_ebb_raises_next_spring(t: TestCtx) -> void:
	var w: SimWorld = _world(19, ["u_card_ebb"])
	_force_card(t, w, "great_ebb")
	t.check_approx(w.tide.low_plateau, -12.0, 0.01, "«Великий отлив» — плато −12")
	t.check_eq(w.clock.phase_len(SimTypes.Phase.LOW), 2250, "и отлив в полтора раза длиннее")
	t.check_approx(w.crisis.next_spring_bonus, 1.0, 0.01,
		"следующая сизигия поднимется на отметку выше")

static func test_fast_haul_shrinks_bag(t: TestCtx) -> void:
	var w: SimWorld = _world(23)
	var a: SimAgent = w.agents.agents[0]
	var before: int = w.agents.bag_free(a, w)
	_force_card(t, w, "fast_haul")
	t.check_eq(w.agents.bag_free(a, w), before - 1, "котомка на слот меньше")

static func test_careful_extends_drowning(t: TestCtx) -> void:
	var w: SimWorld = _world(29)
	var a: SimAgent = w.agents.agents[0]
	a.trait_ids = []
	a.recompute_from_traits()
	_force_card(t, w, "careful")
	a.platform_id = w.terrain.platform_at(Vector2i(40, Balance.mark_to_floor_cell_y(-8)))
	a.x = 40.0
	a.target_x = 40.0
	w.tide.level_override = 0.0
	var ticks: int = 0
	while a.is_alive() and ticks < 400:
		t.run_ticks(w, 1)
		ticks += 1
	var base: int = int(Balance.DROWN_SEC * Balance.TICKS_PER_SEC)
	var bonus: int = int(3.0 * float(Balance.TICKS_PER_SEC))
	t.check_eq(ticks, base + bonus, "с «Осторожно» под водой держатся на 3 секунды дольше")

static func test_careful_recalls_earlier(t: TestCtx) -> void:
	var w: SimWorld = _world(31)
	_force_card(t, w, "careful")
	t.check_approx(float(w.cycle_modifiers.get("recall_earlier_sec", 0.0)), 30.0, 0.01,
		"модификатор раннего возврата на месте")
	t.check_approx(float(w.cycle_modifiers.get("gather_speed_mult", 1.0)), 0.8, 0.01,
		"и замедление добычи")

## «Тихая вода» отменяет Приход этого цикла.
static func test_calm_water_cancels_visit(t: TestCtx) -> void:
	var w: SimWorld = _world(37, ["u_card_calm"])
	_until(t, w, 4, SimTypes.Phase.EBB)
	t.run_ticks(w, 1)
	_force_card(t, w, "calm_water")
	_until(t, w, 4, SimTypes.Phase.HIGH)
	t.run_ticks(w, 10)
	t.check_eq(w.crisis.creatures.size(), 0, "в цикл Прихода никто не пришёл")
	# А без карты — приходят.
	var w2: SimWorld = _world(37, ["u_card_calm"])
	_until(t, w2, 4, SimTypes.Phase.HIGH)
	t.run_ticks(w2, 10)
	t.check_eq(w2.crisis.creatures.size(), 1, "без карты Приход состоялся")

## «Находка» помечает депозит: реликвия выпадает первой же добычей.
static func test_the_find_marks_relic(t: TestCtx) -> void:
	var w: SimWorld = _world(41, ["u_card_find"])
	_force_card(t, w, "the_find")
	var marked: int = -1
	for i: int in w.terrain.deposits.size():
		if bool(w.terrain.deposits[i].get("relic_marked", false)):
			marked = i
	t.check(marked >= 0, "депозит помечен")
	if marked < 0:
		return
	var dep: Dictionary = w.terrain.deposits[marked]
	t.check_eq(str(dep["kind"]), "ruins_deep", "и это глубокие руины")
	var a: SimAgent = w.agents.agents[0]
	a.bag.clear()
	w.agents._roll_relic(a, dep, Balance.cell_to_mark(dep["cell"] as Vector2i), w)
	t.check_eq(a.bag_count("relic"), 1, "первая же добыча даёт реликвию")

static func test_modifiers_reset_at_cycle_end(t: TestCtx) -> void:
	var w: SimWorld = _world(43)
	_force_card(t, w, "fast_haul")
	t.check(not w.cycle_modifiers.is_empty(), "модификаторы цикла выставлены")
	_until(t, w, 2, SimTypes.Phase.EBB)
	# На новом Спаде старые модификаторы сняты, новые ставит новая карта.
	t.check(not w.cycle_modifiers.has("haul_speed_mult")
		or is_equal_approx(float(w.cycle_modifiers["haul_speed_mult"]), 1.4) == false,
		"эффект прошлого цикла снят")
	t.check(w.run_state.active_card.is_empty() or w.run_state.active_card != "fast_haul"
		or w.clock.cycle == 1, "карта прошлого цикла больше не активна")

# --- Сериализация ---------------------------------------------------------

static func test_cards_survive_save(t: TestCtx) -> void:
	var w: SimWorld = _world(2024, ["u_card_ebb"])
	t.run_ticks(w, 1500)
	var text: String = JSON.stringify(w.to_dict(), "", true, true)
	var restored: SimWorld = SimWorld.new()
	restored.from_dict(JSON.parse_string(text) as Dictionary, _cliff())
	t.check_eq(JSON.stringify(restored.to_dict(), "", true, true), text,
		"драфт и разблокировки переживают JSON")
	t.check_eq(restored.run_state.unlocks, w.run_state.unlocks, "разблокировки на месте")
	for i: int in 2000:
		t.run_ticks(w, 1)
		t.run_ticks(restored, 1)
	t.check_eq(TestCtx.state_hash(w), TestCtx.state_hash(restored),
		"после загрузки мир с картами продолжается идентично")
