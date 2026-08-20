extends RefCounted
## Приёмка этапа 01: границы фаз, кривая воды, детерминизм, round-trip сейва.

## Мир для тестов: без записи журнала команд, с фиксированным сидом.
static func _world(seed_value: int) -> SimWorld:
	var w: SimWorld = SimWorld.new()
	w.new_run(seed_value)
	w.events_out.clear()
	return w

# --- Часы -----------------------------------------------------------------

static func test_phase_boundaries(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	t.check_eq(w.clock.phase, SimTypes.Phase.EBB, "забег начинается со Спада")
	t.check_eq(w.clock.cycle, 1, "первый цикл — №1")

	t.run_ticks(w, 449)
	t.check_eq(w.clock.phase, SimTypes.Phase.EBB, "тик 449 — ещё Спад")
	t.run_ticks(w, 1)
	t.check_eq(w.clock.phase, SimTypes.Phase.LOW, "тик 450 — Низкая вода")

	t.run_ticks(w, 1500 - 1)
	t.check_eq(w.clock.phase, SimTypes.Phase.LOW, "тик 1949 — ещё Низкая")
	t.run_ticks(w, 1)
	t.check_eq(w.clock.phase, SimTypes.Phase.SIGNAL, "тик 1950 — Сигнал")

	t.run_ticks(w, 300 - 1)
	t.check_eq(w.clock.phase, SimTypes.Phase.SIGNAL, "тик 2249 — ещё Сигнал")
	t.run_ticks(w, 1)
	t.check_eq(w.clock.phase, SimTypes.Phase.HIGH, "тик 2250 — Высокая вода")

	t.run_ticks(w, 750 - 1)
	t.check_eq(w.clock.cycle, 1, "тик 2999 — цикл ещё первый")
	t.run_ticks(w, 1)
	t.check_eq(w.clock.total_ticks(), Balance.TICKS_PER_CYCLE, "цикл = 3000 тиков")
	t.check_eq(w.clock.cycle, 2, "тик 3000 — начался второй цикл")
	t.check_eq(w.clock.phase, SimTypes.Phase.EBB, "новый цикл начинается со Спада")
	t.check_eq(w.clock.tick_in_phase, 0, "счётчик фазы обнулён на границе")

## Порядок событий на границе цикла — контракт автопаузы Итога цикла.
static func test_cycle_boundary_events(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	t.run_ticks(w, Balance.TICKS_PER_CYCLE - 1)
	w.tick()
	var kinds: Array[String] = []
	for e: SimEvent in w.events_out:
		if e.type == "water_level_changed" or e.type == "sim_ticked":
			continue
		kinds.append(e.type)
	t.check_eq(kinds, ["cycle_ended", "cycle_started", "phase_changed"] as Array[String],
		"порядок событий границы цикла")
	for e: SimEvent in w.events_out:
		if e.type == "phase_changed":
			t.check_eq(int(e.data["prev"]), int(SimTypes.Phase.HIGH),
				"phase_changed несёт предыдущую фазу")

## Шторм (этап 09) укорачивает LOW через phase_scale — формулу фаз он трогать
## не должен. Проверяем, что механизм работает уже сейчас.
static func test_phase_scale(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	w.clock.phase_scale[SimTypes.Phase.LOW] = Balance.STORM_LOW_SCALE
	t.check_eq(w.clock.phase_len(SimTypes.Phase.LOW), 1050, "LOW короче на 30%")
	t.run_ticks(w, 450 + 1050)
	t.check_eq(w.clock.phase, SimTypes.Phase.SIGNAL, "укороченная LOW сменяется вовремя")

# --- Вода -----------------------------------------------------------------

static func test_tide_curve(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	t.check_approx(w.tide.level, 0.0, 0.01, "тик 0: вода на отметке 0")

	t.run_ticks(w, 450 + 750)                       # середина Низкой воды
	t.check_approx(w.tide.level, -8.0, 0.01, "середина LOW: плато −8")

	t.run_ticks(w, 750 + 300)                       # конец Сигнала
	t.check_eq(w.clock.phase, SimTypes.Phase.HIGH, "дошли до Высокой воды")
	t.check_approx(w.tide.level, -6.0, 0.01, "конец SIGNAL: вода −6")

	t.run_ticks(w, 750)                             # конец Высокой воды
	t.check_approx(w.tide.level, 0.0, 0.01, "конец HIGH: вода вернулась к 0")

	# Спад — монотонное падение: если кривая где-то «дёрнется» вверх,
	# на шкале прилива это увидит игрок.
	var prev: float = w.tide.level
	for i: int in 449:
		t.run_ticks(w, 1)
		if w.tide.level > prev + 0.0001:
			t.check(false, "Спад не монотонен на тике %d фазы" % i)
			break
		prev = w.tide.level

## Троттлинг события воды — требование производительности, не косметика:
## без него за забег набегают десятки тысяч SimEvent.
static func test_water_event_throttle(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	var emits: int = 0
	for i: int in 450:
		w.tick()
		for e: SimEvent in w.events_out:
			if e.type == "water_level_changed":
				emits += 1
		w.events_out.clear()
	t.check(emits <= 150, "за 450 тиков Спада не больше 150 событий воды (было %d)" % emits)
	t.check(emits > 100, "но события всё же идут (было %d)" % emits)

## Плато — поля, а не константы: сизигия и карты вылазки меняют их.
static func test_tide_plateaus_are_mutable(t: TestCtx) -> void:
	var w: SimWorld = _world(1)
	w.tide.high_plateau = Balance.HIGH_LEVEL + Balance.SPRING_BONUS
	w.tide.low_plateau = -10.0
	t.run_ticks(w, 450 + 750)
	t.check_approx(w.tide.level, -10.0, 0.01, "карта «Глубокий заход»: плато LOW −10")
	t.run_ticks(w, 750 + 300 + 750)
	t.check_approx(w.tide.level, 2.0, 0.01, "сизигия: плато HIGH +2")

# --- Детерминизм и сериализация -------------------------------------------

static func test_determinism(t: TestCtx) -> void:
	var a: SimWorld = _world(12345)
	var b: SimWorld = _world(12345)
	for i: int in 10000:
		t.run_ticks(a, 1)
		t.run_ticks(b, 1)
		# Сверка каждые 500 тиков: расхождение «где-то за 10 000 тиков» ничего
		# не говорит, расхождение «сразу после cycle_ended» указывает на систему.
		if i % 500 == 0 and TestCtx.state_hash(a) != TestCtx.state_hash(b):
			t.check(false, "миры разошлись на тике %d" % i)
			return
	t.check_eq(TestCtx.state_hash(a), TestCtx.state_hash(b),
		"10 000 тиков с одним сидом дают одно состояние")

static func test_different_seeds_differ(t: TestCtx) -> void:
	var a: SimWorld = _world(1)
	var b: SimWorld = _world(2)
	t.check(TestCtx.state_hash(a) != TestCtx.state_hash(b),
		"разные сиды дают разное состояние RNG")

static func test_dict_roundtrip(t: TestCtx) -> void:
	var w: SimWorld = _world(777)
	t.run_ticks(w, 4321)
	var d1: Dictionary = w.to_dict()
	var restored: SimWorld = SimWorld.new()
	restored.from_dict(d1)
	t.check_eq(JSON.stringify(restored.to_dict()), JSON.stringify(d1),
		"to_dict → from_dict → to_dict совпадает")
	t.check_eq(restored.clock.total_ticks(), 4321, "счётчик тиков восстановлен")

## Ловит две фатальные ошибки: from_dict что-то не восстановил (обычно состояние
## RNG) или to_dict потерял точность float. Дешевле узнать сейчас, чем на этапе 11.
static func test_save_load_continues_identically(t: TestCtx) -> void:
	var live: SimWorld = _world(777)
	t.run_ticks(live, 5000)
	var snapshot: Dictionary = live.to_dict()

	var restored: SimWorld = SimWorld.new()
	restored.from_dict(snapshot)
	for i: int in 2000:
		t.run_ticks(live, 1)
		t.run_ticks(restored, 1)
	t.check_eq(TestCtx.state_hash(live), TestCtx.state_hash(restored),
		"продолжение после save/load совпадает с непрерывным прогоном")

## Проверяет ИМЕННО тот путь, которым пойдёт сейв этапа 11: словарь → текст
## JSON → разбор → словарь. full_precision=true обязателен, иначе float
## печатается усечённым и продолженная симуляция разойдётся (research/18 §2).
static func test_json_roundtrip(t: TestCtx) -> void:
	var w: SimWorld = _world(99)
	t.run_ticks(w, 1234)
	var text: String = JSON.stringify(w.to_dict(), "", true, true)
	var parsed: Variant = JSON.parse_string(text)
	t.check(parsed is Dictionary, "JSON состояния разбирается обратно")
	var restored: SimWorld = SimWorld.new()
	restored.from_dict(parsed as Dictionary)
	# JSON.parse отдаёт ВСЕ числа как float — без int() в from_dict счётчики
	# стали бы 12.0 и хеш перестал бы совпадать (research/11 §8).
	t.check_eq(typeof(restored.to_dict()["clock"]["cycle"]), TYPE_INT,
		"cycle остаётся int после JSON-round-trip")
	t.check_eq(JSON.stringify(restored.to_dict(), "", true, true), text,
		"состояние переживает JSON")

## Самая строгая проверка сейва: продолжение ПОСЛЕ прохода через текст JSON
## совпадает с непрерывным прогоном. Ловит потерю младших битов в 64-битных
## полях (состояние RNG) — обычное сравнение словарей её не видит.
static func test_json_save_continues_identically(t: TestCtx) -> void:
	var live: SimWorld = _world(4242)
	t.run_ticks(live, 3000)
	var text: String = JSON.stringify(live.to_dict(), "", true, true)

	var restored: SimWorld = SimWorld.new()
	restored.from_dict(JSON.parse_string(text) as Dictionary)
	for i: int in 500:
		restored.rng.randi_range(0, 1_000_000)
		live.rng.randi_range(0, 1_000_000)
		t.run_ticks(live, 1)
		t.run_ticks(restored, 1)
	t.check_eq(TestCtx.state_hash(live), TestCtx.state_hash(restored),
		"продолжение после сейва через JSON совпадает с непрерывным прогоном")

# --- Команды --------------------------------------------------------------

## Команды применяются только в начале тика, порядок сохраняется — на этом
## держится реплей по сиду и журналу.
## Известных команд на этапе 01 ещё нет, поэтому заодно проверяется ветка «_:»
## разбора: WARNING «неизвестная команда» в выводе теста — ожидаемый.
static func test_command_log_replay(t: TestCtx) -> void:
	var w: SimWorld = SimWorld.new(true)
	w.new_run(555)
	w.events_out.clear()
	t.run_ticks(w, 100)
	w.apply_command({"kind": "noop"})
	t.run_ticks(w, 100)
	t.check_eq(w.command_log.size(), 1, "команда попала в журнал")
	t.check_eq(int(w.command_log[0]["t"]), 100, "журнал помнит тик команды")

	var replayed: SimWorld = SimWorld.replay(555, w.command_log, 200)
	t.check_eq(TestCtx.state_hash(replayed), TestCtx.state_hash(w),
		"реплей по сиду и журналу воспроизводит состояние")

static func test_rng_state_survives_save(t: TestCtx) -> void:
	var w: SimWorld = _world(2024)
	for i: int in 50:
		w.rng.randi_range(0, 1000)
	var d: Dictionary = w.to_dict()
	var restored: SimWorld = SimWorld.new()
	restored.from_dict(d)
	t.check_eq(restored.rng.randi_range(0, 1000), w.rng.randi_range(0, 1000),
		"после загрузки RNG продолжает последовательность, а не начинает заново")
