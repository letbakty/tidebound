extends RefCounted
## Приёмка этапа 04: стаки, склады, порча, сушка, затопление, плавник.

const CLIFF: String = "res://data/cliffs/cliff_01.tres"

static func _cliff() -> CliffDef:
	return load(CLIFF) as CliffDef

static func _world(seed_value: int) -> SimWorld:
	var w: SimWorld = SimWorld.new()
	w.new_run(seed_value, _cliff())
	w.events_out.clear()
	return w

## Пустой склад на нужной отметке — чтобы тесты не зависели от стартовых запасов.
static func _bare(w: SimWorld, mark: int) -> int:
	return w.storage.add_storage(Vector2i(4, Balance.mark_to_floor_cell_y(mark)))

# --- Стаки ----------------------------------------------------------------

static func test_stack_merge_rules(t: TestCtx) -> void:
	var a: Dictionary = StackUtil.make("catch", 3, false)
	var b: Dictionary = StackUtil.make("catch", 2, false)
	t.check(StackUtil.can_merge(a, b), "одинаковые стаки сливаются")
	b["spoil_left"] = int(b["spoil_left"]) - 1
	# Иначе свежая добыча «продлевала» бы старую — тихий эксплойт.
	t.check(not StackUtil.can_merge(a, b), "стаки с разным сроком порчи не сливаются")
	var dry: Dictionary = StackUtil.make("driftwood", 1, false)
	var wet: Dictionary = StackUtil.make("driftwood", 1, true)
	t.check(not StackUtil.can_merge(dry, wet), "мокрый и сухой не сливаются")

## Словари передаются по ссылке: склад обязан взять копию.
static func test_store_takes_ownership(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var id: int = _bare(w, 3)
	var stack: Dictionary = StackUtil.make("scrap", 5, false)
	w.storage.store(id, stack)
	stack["count"] = 9999
	t.check_eq(w.storage.count_in(id, "scrap"), 5, "правка исходного стака не трогает склад")

# --- Склад ----------------------------------------------------------------

static func test_store_and_overflow(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var id: int = w.storage.add_storage(Vector2i(4, Balance.mark_to_floor_cell_y(3)), 2)
	t.check_eq(w.storage.store(id, StackUtil.make("scrap", 10, false)), 0, "первый стак влез")
	t.check_eq(w.storage.store(id, StackUtil.make("scrap", 10, false)), 0, "второй тоже")
	# Два слота по 10 = 20; третий стак некуда положить.
	t.check_eq(w.storage.store(id, StackUtil.make("scrap", 7, false)), 7, "остаток вернулся весь")
	t.check_eq(w.storage.count_in(id, "scrap"), 20, "на складе ровно вместимость")
	# Неполный стак добивается, а не занимает новый слот.
	w.storage.take(id, "scrap", 4)
	t.check_eq(w.storage.store(id, StackUtil.make("scrap", 4, false)), 0,
		"добор в неполный стак не требует свободного слота")

static func test_take_shortage(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var id: int = _bare(w, 3)
	w.storage.store(id, StackUtil.make("scrap", 6, false))
	var got: Array[Dictionary] = w.storage.take(id, "scrap", 10)
	t.check_eq(_sum(got), 6, "выдано столько, сколько было")
	t.check_eq(w.storage.count_in(id, "scrap"), 0, "склад опустел")
	t.check_eq(_sum(w.storage.take(id, "scrap", 1)), 0, "из пустого ничего не берётся")
	t.check_eq(_sum(w.storage.take(9999, "scrap", 1)), 0, "несуществующий склад безопасен")

## Мокрый плавник не горит: брать его раньше сухого — значит гасить очаг.
static func test_prefer_dry(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var id: int = _bare(w, 3)
	w.storage.store(id, StackUtil.make("driftwood", 4, true))
	w.storage.store(id, StackUtil.make("driftwood", 4, false))
	var got: Array[Dictionary] = w.storage.take(id, "driftwood", 4, true)
	t.check_eq(_sum(got), 4, "выдано 4")
	for s: Dictionary in got:
		t.check(not bool(s["wet"]), "prefer_dry выдал сухой плавник")
	var got2: Array[Dictionary] = w.storage.take(id, "driftwood", 4, false)
	for s2: Dictionary in got2:
		t.check(bool(s2["wet"]), "без prefer_dry первым идёт мокрый")

static func _sum(stacks: Array[Dictionary]) -> int:
	var n: int = 0
	for s: Dictionary in stacks:
		n += int(s["count"])
	return n

static func test_start_stock(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var totals: Dictionary[String, int] = w.storage.totals()
	t.check_eq(int(totals.get("rations", 0)), 8, "старт: 8 провизии")
	t.check_eq(int(totals.get("driftwood", 0)), 6, "старт: 6 плавника")
	t.check_eq(int(totals.get("scrap", 0)), 4, "старт: 4 утиля")
	t.check_eq(w.storage.storages.size(), 1, "склад на старте один")

# --- Порча ----------------------------------------------------------------

static func test_spoilage(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var id: int = _bare(w, 3)
	w.storage.store(id, StackUtil.make("catch", 5, false))
	w.storage.store(id, StackUtil.make("scrap", 5, false))
	for c: int in 2:
		t.run_ticks(w, Balance.TICKS_PER_CYCLE)
	t.check_eq(w.storage.count_in(id, "catch"), 5, "через 2 цикла добыча ещё жива")
	t.run_ticks(w, Balance.TICKS_PER_CYCLE)
	t.check_eq(w.storage.count_in(id, "catch"), 0, "через 3 цикла добыча пропала")
	t.check_eq(w.storage.count_in(id, "scrap"), 5, "утиль не портится")

static func test_rations_spoil_at_12(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var id: int = _bare(w, 3)
	w.storage.store(id, StackUtil.make("rations", 3, false))
	for c: int in 11:
		t.run_ticks(w, Balance.TICKS_PER_CYCLE)
	t.check_eq(w.storage.count_in(id, "rations"), 3, "через 11 циклов провизия цела")
	t.run_ticks(w, Balance.TICKS_PER_CYCLE)
	t.check_eq(w.storage.count_in(id, "rations"), 0, "через 12 циклов пропала")

## Порча и вода попадают в отчёт итога цикла, а не теряются молча.
static func test_cycle_report(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var id: int = _bare(w, 3)
	w.storage.store(id, StackUtil.make("catch", 4, false))
	t.run_ticks(w, Balance.TICKS_PER_CYCLE * 3 - 1)
	w.tick()
	var report: Dictionary = {}
	for e: SimEvent in w.events_out:
		if e.type == "cycle_ended":
			report = e.data
	t.check(report.has("spoiled"), "в итоге цикла есть раздел порчи")
	t.check_eq(int((report["spoiled"] as Dictionary).get("catch", 0)), 4,
		"испортившаяся добыча посчитана")

# --- Затопление -----------------------------------------------------------

## docs/00 §7: соль растворяется, добыча теряет половину, плавник мокнет,
## слитки целы. И всё это ровно один раз на затопление.
static func test_flood_rules(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var id: int = w.storage.add_storage(Vector2i(20, Balance.mark_to_floor_cell_y(-2)))
	w.storage.store(id, StackUtil.make("salt", 6, false))
	w.storage.store(id, StackUtil.make("catch", 7, false))
	w.storage.store(id, StackUtil.make("driftwood", 3, false))
	w.storage.store(id, StackUtil.make("ingot", 2, false))

	# Отлив уводит воду ниже −2, подъём в HIGH снова накрывает склад.
	t.run_ticks(w, 450)
	t.check(w.storage.count_in(id, "salt") == 6, "на отливе склад цел")
	t.run_ticks(w, 1500 + 300 + 750)

	t.check_eq(w.storage.count_in(id, "salt"), 0, "соль растворилась")
	t.check_eq(w.storage.count_in(id, "catch"), 3, "добыча потеряла половину (7 → 3)")
	t.check_eq(w.storage.count_in(id, "ingot"), 2, "слитки целы")
	var wet_found: bool = false
	for s: Variant in w.storage.storages[w.storage.storage_index(id)]["stacks"] as Array:
		if str((s as Dictionary)["item_id"]) == "driftwood":
			wet_found = bool((s as Dictionary)["wet"])
	t.check(wet_found, "плавник стал мокрым")

	# Повторного применения при том же затоплении быть не должно.
	var catch_after: int = w.storage.count_in(id, "catch")
	t.run_ticks(w, 200)
	t.check_eq(w.storage.count_in(id, "catch"), catch_after,
		"пока склад под той же водой, правило не применяется снова")

static func test_flood_applies_once_per_crossing(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var id: int = w.storage.add_storage(Vector2i(20, Balance.mark_to_floor_cell_y(-2)))
	w.storage.store(id, StackUtil.make("catch", 16, false))
	t.run_ticks(w, Balance.TICKS_PER_CYCLE)
	t.check_eq(w.storage.count_in(id, "catch"), 8, "первый прилив: 16 → 8")
	t.run_ticks(w, Balance.TICKS_PER_CYCLE)
	t.check_eq(w.storage.count_in(id, "catch"), 4, "второй прилив: 8 → 4")

## Земля не защищает: предмет на затопленной клетке уносит водой.
static func test_ground_items_washed_away(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var deep: Vector2i = Vector2i(40, Balance.mark_to_floor_cell_y(-8))
	t.run_ticks(w, 450 + 100)                    # дно уже осушено
	w.storage.drop(deep, StackUtil.make("scrap", 3, false))
	t.check_eq(w.storage.ground_at(deep).size(), 1, "предмет лежит на дне")
	t.run_ticks(w, 1500 + 300 + 400)             # вода вернулась
	t.check_eq(w.storage.ground_at(deep).size(), 0, "предмет унесло водой")

static func test_pickup(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var cell: Vector2i = Vector2i(6, Balance.mark_to_floor_cell_y(3))
	w.storage.drop(cell, StackUtil.make("kelp", 2, false))
	w.storage.drop(cell, StackUtil.make("kelp", 3, false))
	t.check_eq(w.storage.ground_at(cell).size(), 1, "совместимые стаки на земле слились")
	var got: Array[Dictionary] = w.storage.pickup_at(cell)
	t.check_eq(_sum(got), 5, "подобрано 5")
	t.check_eq(w.storage.ground_at(cell).size(), 0, "клетка пуста после подбора")

# --- Сушка ----------------------------------------------------------------

static func test_drying(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var high: int = _bare(w, Balance.DRY_MIN_MARK)
	var low: int = w.storage.add_storage(Vector2i(6, Balance.mark_to_floor_cell_y(1)))
	w.storage.store(high, StackUtil.make("driftwood", 2, true))
	w.storage.store(low, StackUtil.make("driftwood", 2, true))
	t.run_ticks(w, Balance.TICKS_PER_CYCLE)
	t.check(_is_wet(w, high, "driftwood"), "за один цикл ещё не высох")
	t.run_ticks(w, Balance.TICKS_PER_CYCLE)
	t.check(not _is_wet(w, high, "driftwood"), "за два полных цикла высох")
	t.check(_is_wet(w, low, "driftwood"), "ниже +2 сушки нет")

static func _is_wet(w: SimWorld, storage_id: int, item_id: String) -> bool:
	var i: int = w.storage.storage_index(storage_id)
	for s: Variant in w.storage.storages[i]["stacks"] as Array:
		var cur: Dictionary = s as Dictionary
		if str(cur["item_id"]) == item_id:
			return bool(cur["wet"])
	return false

# --- Плавник --------------------------------------------------------------

static func test_driftwood_after_high(t: TestCtx) -> void:
	var w: SimWorld = _world(7)
	t.check_eq(_driftwood_on_ground(w), 0, "на старте плавника на земле нет")
	t.run_ticks(w, Balance.TICKS_PER_CYCLE)
	var n: int = _driftwood_on_ground(w)
	t.check(n >= Balance.DRIFTWOOD_MIN and n <= Balance.DRIFTWOOD_MAX,
		"после Высокой воды вынесло 3–6 стаков (было %d)" % n)
	for g: Dictionary in w.storage.ground:
		var mark: int = Balance.cell_to_mark(g["cell"] as Vector2i)
		t.check(mark >= Balance.DRIFTWOOD_MARK_LO and mark <= Balance.DRIFTWOOD_MARK_HI,
			"плавник лежит на отметке 0..+1, а не %d" % mark)
		t.check(not bool((g["stack"] as Dictionary)["wet"]), "вынесенный плавник сухой")

## Один сид — одни и те же клетки: без этого не воспроизвести баг-репорт.
static func test_driftwood_is_deterministic(t: TestCtx) -> void:
	var a: SimWorld = _world(99)
	var b: SimWorld = _world(99)
	t.run_ticks(a, Balance.TICKS_PER_CYCLE)
	t.run_ticks(b, Balance.TICKS_PER_CYCLE)
	t.check_eq(JSON.stringify(a.storage.to_dict()), JSON.stringify(b.storage.to_dict()),
		"позиции плавника совпадают при одном сиде")
	var c: SimWorld = _world(100)
	t.run_ticks(c, Balance.TICKS_PER_CYCLE)
	t.check(JSON.stringify(c.storage.to_dict()) != JSON.stringify(a.storage.to_dict()),
		"при другом сиде позиции другие")

static func _driftwood_on_ground(w: SimWorld) -> int:
	var n: int = 0
	for g: Dictionary in w.storage.ground:
		if str((g["stack"] as Dictionary)["item_id"]) == "driftwood":
			n += 1
	return n

# --- События и сериализация -----------------------------------------------

static func test_resources_changed_event(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var id: int = _bare(w, 3)
	w.storage.store(id, StackUtil.make("ingot", 2, false))
	w.tick()
	var found: bool = false
	for e: SimEvent in w.events_out:
		if e.type == "resources_changed":
			found = true
			t.check_eq(int((e.data["totals"] as Dictionary).get("ingot", 0)), 2,
				"агрегат посчитал слитки")
	t.check(found, "изменение склада породило resources_changed")
	w.events_out.clear()
	w.tick()
	for e2: SimEvent in w.events_out:
		t.check(e2.type != "resources_changed", "без изменений событие не шлётся")

static func test_storage_survives_save(t: TestCtx) -> void:
	var w: SimWorld = _world(4242)
	t.run_ticks(w, 3500)
	var id: int = w.storage.add_storage(Vector2i(20, Balance.mark_to_floor_cell_y(-2)))
	w.storage.store(id, StackUtil.make("catch", 5, false))
	w.storage.drop(Vector2i(40, Balance.mark_to_floor_cell_y(-8)),
		StackUtil.make("scrap", 2, false))

	var text: String = JSON.stringify(w.to_dict(), "", true, true)
	var restored: SimWorld = SimWorld.new()
	restored.from_dict(JSON.parse_string(text) as Dictionary, _cliff())
	t.check_eq(JSON.stringify(restored.to_dict(), "", true, true), text,
		"склады и земля переживают JSON")
	for i: int in 3000:
		t.run_ticks(w, 1)
		t.run_ticks(restored, 1)
	t.check_eq(TestCtx.state_hash(w), TestCtx.state_hash(restored),
		"после загрузки мир со складами продолжается идентично")
