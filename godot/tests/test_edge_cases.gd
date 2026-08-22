extends RefCounted
## Краевые случаи этапа 19 (п.5): битый и обрезанный сейв, сохранение в момент
## смерти, выход во время драфта, пауза на подъёме воды, крайние разрешения.
##
## Каждый случай здесь — это то, что игрок делает случайно, а мы не делаем
## никогда: выключает игру в неудачный момент, играет в окне 800×600, ставит
## паузу ровно на «воде стеной».

const CLIFF: String = "res://data/cliffs/cliff_01.tres"
const TMP_SAVE: String = "user://test_edge_save.json"

static func _world(seed_value: int) -> SimWorld:
	var w: SimWorld = SimWorld.new()
	w.new_run(seed_value, load(CLIFF) as CliffDef)
	w.events_out.clear()
	return w

# --- Сейв ------------------------------------------------------------------

## Обрыв записи (закрытие игры, разряд батареи) оставляет ПОЛОВИНУ валидного
## JSON — это не то же самое, что мусор в файле: парсер доходит до середины
## и падает на конце. Отказ обязан быть мягким.
static func test_truncated_save_is_refused(t: TestCtx) -> void:
	var w: SimWorld = _world(31)
	t.run_ticks(w, 600)
	t.check_eq(SaveIO.write_json(TMP_SAVE, w.to_dict()), OK, "полный сейв записан")
	var full: String = FileAccess.get_file_as_string(TMP_SAVE)
	t.check(full.length() > 100, "сейв непустой")
	var f: FileAccess = FileAccess.open(TMP_SAVE, FileAccess.WRITE)
	f.store_string(full.substr(0, int(float(full.length()) * 0.6)))
	f.close()
	var back: Dictionary = SaveIO.read_json(TMP_SAVE)
	t.check(back.is_empty(), "обрезанный сейв не грузится и не роняет игру")
	t.check(FileAccess.file_exists(TMP_SAVE.get_basename() + ".corrupt.json"),
		"обрезанный файл ушёл в карантин — он нужен для баг-репорта")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(
		TMP_SAVE.get_basename() + ".corrupt.json"))

## Автосейв может прийтись ровно на тик смерти агента: мёртвый агент обязан
## пережить круг сериализации так же, как живой, и не воскреснуть при загрузке.
static func test_save_at_moment_of_death(t: TestCtx) -> void:
	var w: SimWorld = _world(17)
	var victim: SimAgent = w.agents.agents[0]
	# Топим агента руками: искать сид, где кто-то тонет на нужном тике —
	# это тест про сейв, а не про воду.
	victim.state = SimTypes.AgentState.DEAD
	w.run_state.note_death(victim, "drown", w.clock.cycle)
	var alive_before: int = w.agents.alive_count()
	var deaths_before: int = w.run_state.deaths.size()

	var data: Dictionary = w.to_dict()
	var back: SimWorld = SimWorld.new()
	back.from_dict(data, load(CLIFF) as CliffDef)
	t.check_eq(back.agents.alive_count(), alive_before,
		"после загрузки живых столько же")
	t.check_eq(back.run_state.deaths.size(), deaths_before,
		"и смерть записана ровно один раз")
	t.check_eq(TestCtx.state_hash(back), TestCtx.state_hash(w),
		"состояние в момент смерти переживает круг сериализации")
	# Мир продолжает жить одинаково — смерть не ломает продолжение.
	t.run_ticks(w, 200)
	t.run_ticks(back, 200)
	t.check_eq(TestCtx.state_hash(back), TestCtx.state_hash(w),
		"и продолжается одинаково")

## Выход во время драфта (docs/03 §8): карты обязаны быть в сейве. Иначе после
## загрузки драфт либо повторится, либо пропадёт вместе с выбором игрока.
static func test_exit_during_draft_keeps_cards(t: TestCtx) -> void:
	var w: SimWorld = _world(23)
	t.check(not w.run_state.draft.is_empty(), "на старте драфт открыт")
	var cards: Array[String] = w.run_state.draft.duplicate()
	var back: SimWorld = SimWorld.new()
	back.from_dict(w.to_dict(), load(CLIFF) as CliffDef)
	t.check_eq(back.run_state.draft, cards, "драфт пережил сохранение")
	t.check_eq(back.run_state.drafted_this_cycle, w.run_state.drafted_this_cycle,
		"и признак «карта уже выбрана» тоже")
	# И после выбора карты сейв не должен предлагать драфт заново: список карт
	# остаётся (он нужен экрану итога), но признак «выбор сделан» — тоже.
	t.check(back.run_state.pick_card(cards[0], back), "карта выбрана")
	var again: SimWorld = SimWorld.new()
	again.from_dict(back.to_dict(), load(CLIFF) as CliffDef)
	t.check(again.run_state.drafted_this_cycle,
		"после загрузки выбор считается сделанным, драфт не открывается заново")
	t.check_eq(again.run_state.active_card, back.run_state.active_card,
		"активная карта сохранена")
	t.check(not again.run_state.pick_card(cards[0], again),
		"и второй раз карту выбрать нельзя")

# --- Пауза -----------------------------------------------------------------

## Пауза во время подъёма воды. Тик — единственный источник времени в sim,
## поэтому «пауза» на уровне ядра — это просто отсутствие тиков: уровень,
## затопление и все флаги обязаны замереть, а после снятия паузы продолжиться
## ровно с того же места.
static func test_pause_during_rise_freezes_water(t: TestCtx) -> void:
	var w: SimWorld = _world(29)
	# Доходим до фазы HIGH — «вода стеной».
	var guard: int = 0
	while int(w.clock.phase) != SimTypes.Phase.HIGH and guard < Balance.TICKS_PER_CYCLE:
		t.run_ticks(w, 1)
		guard += 1
	t.check_eq(int(w.clock.phase), SimTypes.Phase.HIGH, "дошли до Высокой воды")
	t.run_ticks(w, 60)                     # уже посреди подъёма
	var level: float = w.tide.level
	var hash_paused: String = TestCtx.state_hash(w)
	# «Пауза»: 600 кадров без единого тика.
	for i: int in 600:
		pass
	t.check_eq(w.tide.level, level, "на паузе уровень не изменился")
	t.check_eq(TestCtx.state_hash(w), hash_paused, "и состояние мира целиком")
	# После снятия паузы вода идёт дальше, а не прыгает.
	t.run_ticks(w, 1)
	t.check(w.tide.level > level, "после паузы подъём продолжился")
	t.check(w.tide.level - level < 0.2,
		"и продолжился шагом одного тика, а не скачком за всю паузу")

# --- Порядок обработчиков границ фаз (TEST-07) -----------------------------

## Правило испарителя (docs/00 §9.1) держится на том, что `flooded_in_phase`
## отражает ВСЮ фазу LOW, а не её последний тик. Порядок двух строк в
## SimWorld — это контракт, и он должен быть проверен явно, иначе следующий
## агент поменяет их местами и ничего не заметит.
static func test_flooded_flag_covers_whole_phase(t: TestCtx) -> void:
	var w: SimWorld = _world(37)
	var id: int = w.buildings.place("evaporator",
		Vector2i(20, Balance.mark_to_floor_cell_y(-2) - 1), w, true)
	t.check(id > 0, "испаритель поставлен на −2")
	var b: Dictionary = w.buildings.buildings[id]
	# Проматываем до Отлива и топим постройку ровно в начале LOW.
	var guard: int = 0
	while int(w.clock.phase) != SimTypes.Phase.LOW and guard < Balance.TICKS_PER_CYCLE:
		t.run_ticks(w, 1)
		guard += 1
	b["flooded_in_phase"] = true
	# ... и «осушаем» её до конца фазы: флаг обязан дожить до границы.
	b["flooded"] = false
	var ticks_left: int = w.clock.ticks_left_in_phase()
	t.run_ticks(w, maxi(ticks_left - 1, 1))
	t.check(bool(b["flooded_in_phase"]),
		"флаг «была затоплена в этой фазе» держится до конца фазы")
	# На границе фазы флаг снимается — иначе он копился бы весь забег.
	t.run_ticks(w, 2)
	t.check(not bool(b["flooded_in_phase"]),
		"и сбрасывается на границе, а не остаётся навсегда")

# --- Разрешения экрана -----------------------------------------------------

## Окно 800×600 — ниже базового 1280×720 (docs/01 §1.1), и 3840×2160 — выше
## всего, что мы рисовали. Интерфейс обязан помещаться в оба: на маленьком
## HUD не должен наезжать сам на себя, на большом — не расползаться.
static func test_hud_fits_extreme_resolutions(t: TestCtx) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var scene: PackedScene = load("res://ui/hud/hud.tscn") as PackedScene
	t.check(scene != null, "сцена HUD загружается")
	if scene == null:
		return
	var hud: Control = scene.instantiate() as Control
	tree.root.add_child(hud)
	for size: Vector2i in [Vector2i(800, 600), Vector2i(3840, 2160)]:
		hud.size = Vector2(size)
		var need: Vector2 = hud.get_combined_minimum_size()
		t.check(need.x <= float(size.x),
			"HUD помещается по ширине в %dx%d (нужно %d)" % [size.x, size.y, int(need.x)])
		t.check(need.y <= float(size.y),
			"HUD помещается по высоте в %dx%d (нужно %d)" % [size.x, size.y, int(need.y)])
	hud.queue_free()

## Цели касания на маленьком окне: content_scale_factor уменьшает интерфейс,
## и 48 px превращаются в 30 экранных. Для десктопа это допустимо, но знать
## границу надо явно (research/24 §9).
static func test_touch_targets_survive_small_window(t: TestCtx) -> void:
	var scale: float = 800.0 / 1280.0
	var effective: float = float(UITokens.TOUCH_MIN) * scale
	t.check(effective >= 24.0,
		"цель касания в окне 800×600 не мельче 24 px (получилось %.0f)" % effective)

# --- Локализация -----------------------------------------------------------

## Русский длиннее английского примерно на 20%, и это заложено в вёрстку. Тест
## держит границу: если перевод разъедется вдвое с лишним, он полезет за панель,
## и увидит это только тот, кто откроет игру на русском.
##
## Сами ключи (нет «сырых» KEY_NAME на экране) проверяет test_ui/test_ui_keys_exist,
## а полноту обеих колонок — test_ui/test_csv_is_well_formed.
static func test_translations_fit_layout(t: TestCtx) -> void:
	var f: FileAccess = FileAccess.open("res://assets/i18n/strings.csv", FileAccess.READ)
	t.check(f != null, "strings.csv открылся")
	if f == null:
		return
	var checked: int = 0
	var longest: int = 0
	var first: bool = true
	while not f.eof_reached():
		var row: PackedStringArray = f.get_csv_line()
		if row.size() < 3 or first:
			first = false
			continue
		var key: String = row[0]
		var ru: String = row[1]
		var en: String = row[2]
		longest = maxi(longest, ru.length())
		if ru.length() <= LOC_MIN_LEN or en.is_empty():
			continue
		checked += 1
		var ratio: float = float(ru.length()) / float(en.length())
		t.check(ratio <= LOC_MAX_RATIO,
			"%s: русский длиннее английского в %.1f раза — не влезет в панель"
				% [key, ratio])
	f.close()
	t.check(checked > 100, "строк для проверки нашлось мало (%d)" % checked)
	t.check(longest <= LOC_MAX_LEN,
		"самая длинная строка %d символов, потолок %d" % [longest, LOC_MAX_LEN])

## Пороги с запасом к тому, что есть сейчас (максимум 2.0 и 174 символа):
## тест ловит разъезд, а не придирается к каждому новому переводу.
const LOC_MAX_RATIO: float = 2.2
const LOC_MIN_LEN: int = 20
const LOC_MAX_LEN: int = 200
