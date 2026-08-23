extends RefCounted
## Приёмка первой волны контента (prompts/CONTENT-wave-1): география ресурсов
## и Верша.
##
## Два вопроса, на которые сьют отвечает и которых не задавали прежние тесты:
## 1) новый вид депозита — это ДАННЫЕ, и молча разъехаться они могут четырьмя
##    способами (нет предмета, нет строки, нет слота на карте, отметка вне
##    диапазона), причём ни один не роняет игру;
## 2) верша отдаёт улов РОВНО раз за фазу. Постройка, отдающая его каждый тик,
##    выглядит в игре точно так же — разницу видно только в цифрах груза.

const CLIFF: String = "res://data/cliffs/cliff_01.tres"
const CSV_PATH: String = "res://assets/i18n/strings.csv"
## Волна добавила четыре вида; кладём в один список, чтобы «новые» не
## приходилось выискивать глазами при следующей правке.
const NEW_KINDS: Array[String] = ["brine_pool", "fresh_seep", "bone_shoal", "shipwreck"]

static func _cliff() -> CliffDef:
	return load(CLIFF) as CliffDef

static func _world(seed_value: int) -> SimWorld:
	var w: SimWorld = SimWorld.new()
	w.new_run(seed_value, _cliff())
	w.events_out.clear()
	return w

# --- Данные ---------------------------------------------------------------

static func test_new_deposit_kinds_are_complete(t: TestCtx) -> void:
	var known: Dictionary[String, bool] = _csv_keys()
	t.check(known.has("DEPOSIT_RUINS_NEAR"), "csv читается")
	for kind: String in Balance.DEPOSIT_KINDS:
		var d: Dictionary = Balance.DEPOSIT_KINDS[kind] as Dictionary
		t.check(DB.has_item(str(d["item"])),
			"депозит %s даёт несуществующий предмет '%s'" % [kind, str(d["item"])])
		t.check(int(d["capacity"]) > 0, "у депозита %s ненулевая ёмкость" % kind)
		t.check(int(d["refill"]) >= 0, "восполнение %s не отрицательное" % kind)
		t.check(int(d["mark_lo"]) <= int(d["mark_hi"]),
			"диапазон отметок %s не вывернут" % kind)
		t.check(int(d["mark_lo"]) >= Balance.BOTTOM_MARK,
			"%s не уходит ниже дна карты" % kind)
		# Тултип депозита собирает ключ как DEPOSIT_<ВИД> — без строки игрок
		# увидит на экране сырой ключ (ui/panels/deposit_tooltip.gd).
		t.check(known.has("DEPOSIT_%s" % kind.to_upper()),
			"нет строки локализации DEPOSIT_%s" % kind.to_upper())

## Вид депозита без слота на карте — мёртвые данные: он есть в таблице, его
## видно в диффе, и он не встречается в игре ни разу.
static func test_new_kinds_are_on_the_map(t: TestCtx) -> void:
	var slots: Array = _cliff().deposit_slots
	var by_kind: Dictionary[String, int] = {}
	for v: Variant in slots:
		var k: String = str((v as Dictionary)["kind"])
		by_kind[k] = int(by_kind.get(k, 0)) + 1
	for kind: String in NEW_KINDS:
		t.check(int(by_kind.get(kind, 0)) > 0, "вид %s не стоит на утёсе №1" % kind)

## Цель волны, названная числом (CONTENT-wave-1 §0 п.3): до неё карта давала
## ТРИ предмета из тринадцати, и где бы игрок ни собирал, он получал одно и
## то же.
static func test_map_yields_six_items(t: TestCtx) -> void:
	var items: Dictionary[String, bool] = {}
	for kind: String in Balance.DEPOSIT_KINDS:
		items[str((Balance.DEPOSIT_KINDS[kind] as Dictionary)["item"])] = true
	t.check_eq(items.size(), 6, "с карты добываются шесть предметов из тринадцати")
	for id: String in ["scrap", "catch", "kelp", "salt", "freshwater", "part"]:
		t.check(items.has(id), "предмет '%s' добывается с карты" % id)

# --- Восполнение ----------------------------------------------------------

## Восполнение не имеет права перелить через ёмкость: депозит с refill > 0
## наливался бы каждый цикл и стал бы бесконечным складом на дне.
static func test_refill_never_exceeds_capacity(t: TestCtx) -> void:
	var w: SimWorld = _world(11)
	for i: int in w.terrain.deposits.size():
		var d: Dictionary = w.terrain.deposits[i]
		var cap: int = int((Balance.DEPOSIT_KINDS[str(d["kind"])] as Dictionary)["capacity"])
		t.check_eq(int(d["amount"]), cap, "депозит %d начинается полным" % i)
	# Полные депозиты + десять отливов подряд: перелива быть не должно.
	for c: int in 10:
		w.terrain.on_cycle_started(w.rng)
	for i2: int in w.terrain.deposits.size():
		var d2: Dictionary = w.terrain.deposits[i2]
		var cap2: int = int((Balance.DEPOSIT_KINDS[str(d2["kind"])] as Dictionary)["capacity"])
		t.check(int(d2["amount"]) <= cap2,
			"депозит %s перелит: %d при ёмкости %d" % [str(d2["kind"]),
				int(d2["amount"]), cap2])

## И обратное: восполнение вообще происходит. Без этой половины тест зелен
## и на депозите, который просто ничего не делает.
static func test_refill_actually_refills(t: TestCtx) -> void:
	var w: SimWorld = _world(12)
	var seen_refillable: int = 0
	for i: int in w.terrain.deposits.size():
		w.terrain.deposits[i]["amount"] = 0
	for c: int in 3:
		w.terrain.on_cycle_started(w.rng)
	for i2: int in w.terrain.deposits.size():
		var d: Dictionary = w.terrain.deposits[i2]
		var kd: Dictionary = Balance.DEPOSIT_KINDS[str(d["kind"])] as Dictionary
		var refill: int = int(kd["refill"])
		if refill <= 0:
			t.check_eq(int(d["amount"]), 0,
				"%s без восполнения так и остался пустым" % str(d["kind"]))
			continue
		seen_refillable += 1
		t.check_eq(int(d["amount"]), mini(int(kd["capacity"]), refill * 3),
			"%s налился на три отлива" % str(d["kind"]))
	t.check(seen_refillable >= 6, "восполняемых депозитов на карте мало: %d"
		% seen_refillable)

# --- Вода -----------------------------------------------------------------

## Затопленный депозит не собирают. Правило старое (job_system), но с новыми
## видами оно стало важнее: brine_pool стоит на −1..−2 и под водой почти весь
## цикл, и «собирают под водой» выглядело бы просто как щедрая соль.
static func test_flooded_deposit_is_not_gathered(t: TestCtx) -> void:
	var w: SimWorld = _world(13)
	w.tide.level_override = Balance.HIGH_LEVEL      # всё дно под водой
	var before: int = _deposit_total(w)
	t.run_ticks(w, 900)
	t.check_eq(_deposit_total(w), before, "под водой с депозитов не взяли ничего")

	var w2: SimWorld = _world(13)
	w2.tide.level_override = Balance.LOW_LEVEL      # дно открыто
	t.run_ticks(w2, 900)
	t.check(_deposit_total(w2) < before,
		"на сухом дне добыча идёт (иначе первая половина теста ничего не значит)")

# --- Верша ----------------------------------------------------------------

## Главная проверка постройки: улов РОВНО раз за фазу, в которой её накрыло.
## Считаем прибавки на клетке, а не остаток: носильщик уносит стак, и
## «сколько лежит» ответило бы на другой вопрос.
static func test_weir_gives_catch_once_per_cycle(t: TestCtx) -> void:
	var w: SimWorld = _world(14)
	var cell: Vector2i = Vector2i(15, Balance.mark_to_floor_cell_y(-1))
	var id: int = w.buildings.place("weir", Vector2i(15,
		Balance.mark_to_floor_cell_y(-1) - 1), w, true)
	t.check(id > 0, "верша встала на отметке −1")
	t.check_eq(int(w.buildings.buildings[id]["mark"]), -1, "и считает свою отметку")
	var gained: int = 0
	for i: int in Balance.TICKS_PER_CYCLE * 2:
		var before: int = _catch_on(w, cell)
		w.tick()
		w.events_out.clear()
		gained += maxi(0, _catch_on(w, cell) - before)
	t.check_eq(gained, Balance.WEIR_CATCH * 2, "за два цикла — ровно два улова")

## Отдельно от предыдущего: та же постройка не должна сыпать улов, пока
## стоит под водой. Разница между «раз за фазу» и «каждый тик» в игре не
## видна ничем, кроме цифр груза.
static func test_weir_does_not_yield_every_tick(t: TestCtx) -> void:
	var w: SimWorld = _world(15)
	var cell: Vector2i = Vector2i(15, Balance.mark_to_floor_cell_y(-1))
	w.tide.level_override = Balance.LOW_LEVEL
	t.run_ticks(w, 2)
	var id: int = w.buildings.place("weir", Vector2i(15,
		Balance.mark_to_floor_cell_y(-1) - 1), w, true)
	t.check(id > 0, "верша встала")
	t.check(not bool(w.buildings.buildings[id]["flooded"]), "и стоит на сухом")

	w.tide.level_override = Balance.HIGH_LEVEL
	t.run_ticks(w, 300)
	t.check(bool(w.buildings.buildings[id]["flooded_in_phase"]),
		"вода накрыла вершу")
	t.check_eq(_catch_on(w, cell), 0, "под водой верша не кладёт ничего")

	w.tide.level_override = Balance.LOW_LEVEL
	t.run_ticks(w, 1)
	t.check_eq(_catch_on(w, cell), Balance.WEIR_CATCH,
		"на срезе воды — ровно один улов")
	var peak: int = 0
	for i: int in 300:
		t.run_ticks(w, 1)
		peak = maxi(peak, _catch_on(w, cell))
	t.check_eq(peak, Balance.WEIR_CATCH, "и больше не прибавилось ни разу")

## Верша, которую не накрывало, не даёт ничего: улов привязан к воде, а не
## к самому факту постройки. Флаг снимаем руками — так же, как сьют испарителя
## (tests/test_panels.gd), потому что «фаза, в которой не накрыло» на отметках
## −3..−1 в живом забеге не встречается.
static func test_weir_without_flood_gives_nothing(t: TestCtx) -> void:
	var w: SimWorld = _world(16)
	var cell: Vector2i = Vector2i(15, Balance.mark_to_floor_cell_y(-1))
	w.tide.level_override = Balance.LOW_LEVEL
	t.run_ticks(w, 2)
	var id: int = w.buildings.place("weir", Vector2i(15,
		Balance.mark_to_floor_cell_y(-1) - 1), w, true)
	t.check(id > 0, "верша встала")
	w.tide.level_override = Balance.HIGH_LEVEL
	t.run_ticks(w, 100)
	w.buildings.buildings[id]["flooded_in_phase"] = false   # «в этой фазе не накрывало»
	w.tide.level_override = Balance.LOW_LEVEL
	t.run_ticks(w, 5)
	t.check_eq(_catch_on(w, cell), 0, "без затопления улова нет")

## Недостроенная верша — это план, а не снасть: улов до конца стройки был бы
## бесплатной постройкой (материалы в буфере, а рыба уже идёт).
static func test_planned_weir_gives_nothing(t: TestCtx) -> void:
	var w: SimWorld = _world(17)
	var cell: Vector2i = Vector2i(15, Balance.mark_to_floor_cell_y(-1))
	w.tide.level_override = Balance.HIGH_LEVEL
	t.run_ticks(w, 2)
	var id: int = w.buildings.place("weir", Vector2i(15,
		Balance.mark_to_floor_cell_y(-1) - 1), w)
	t.check(id > 0, "план верши размещён")
	t.check(int(w.buildings.buildings[id]["state"]) != int(SimTypes.BuildState.ACTIVE),
		"и это именно план")
	t.run_ticks(w, 100)
	w.tide.level_override = Balance.LOW_LEVEL
	t.run_ticks(w, 5)
	t.check_eq(_catch_on(w, cell), 0, "план улова не даёт")

# --- Утилиты --------------------------------------------------------------

static func _catch_on(w: SimWorld, cell: Vector2i) -> int:
	var n: int = 0
	for s: Dictionary in w.storage.ground_at(cell):
		if str(s["item_id"]) == "catch":
			n += int(s["count"])
	return n

static func _deposit_total(w: SimWorld) -> int:
	var n: int = 0
	for d: Dictionary in w.terrain.deposits:
		n += int(d["amount"])
	return n

static func _csv_keys() -> Dictionary[String, bool]:
	var out: Dictionary[String, bool] = {}
	var f: FileAccess = FileAccess.open(CSV_PATH, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line: PackedStringArray = f.get_csv_line()
		if line.size() > 0 and not line[0].is_empty():
			out[line[0]] = true
	f.close()
	return out
