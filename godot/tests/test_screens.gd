extends RefCounted
## Тесты экранов (этап 15): роутер по видимости, настройки, итоги, профиль.
##
## Автолоадов в headless-раннере нет, поэтому Settings и Meta проверяем как
## обычные скрипты: их сериализация — чистая функция.

const SETTINGS_SCRIPT: String = "res://autoload/settings.gd"
const META_SCRIPT: String = "res://autoload/meta.gd"

## Роутер переключает ВИДИМОСТЬ, а не сцены: пересоздание игровой сцены убило
## бы состояние забега (research/22 §1).
static func test_router_switches_by_visibility(t: TestCtx) -> void:
	var router: ScreenRouter = ScreenRouter.new()
	var menu: ScreenBase = ScreenBase.new()
	var journal: ScreenBase = ScreenBase.new()
	router.register(ScreenRouter.Screen.MAIN_MENU, menu)
	router.register(ScreenRouter.Screen.JOURNAL, journal)
	t.check(not menu.visible and not journal.visible, "до перехода скрыты все")
	router.goto(ScreenRouter.Screen.MAIN_MENU)
	t.check(menu.visible and not journal.visible, "меню показано, журнал скрыт")
	t.check_eq(int(router.current), int(ScreenRouter.Screen.MAIN_MENU),
		"роутер помнит текущий экран")
	router.goto(ScreenRouter.Screen.JOURNAL)
	t.check(journal.visible and not menu.visible, "переход прячет предыдущий экран")
	# Ноды остаются в дереве — состояние экрана переживает переход.
	t.check(menu.get_parent() == router, "экран не пересоздаётся при переходе")
	router.free()

## Возврат из настроек: они открываются и из меню, и из паузы.
static func test_settings_return_point(t: TestCtx) -> void:
	var router: ScreenRouter = ScreenRouter.new()
	router.register(ScreenRouter.Screen.SETTINGS, ScreenBase.new())
	router.register(ScreenRouter.Screen.GAME, ScreenBase.new())
	router.open_settings_from(ScreenRouter.Screen.GAME)
	t.check_eq(int(router.settings_return()), int(ScreenRouter.Screen.GAME),
		"из игры настройки возвращают в игру")
	router.free()

static func test_settings_round_trip(t: TestCtx) -> void:
	var s: Node = (load(SETTINGS_SCRIPT) as GDScript).new()
	s.set("locale", "en")
	s.set("ui_scale", 1.25)
	s.set("pause_on_cycle", false)
	s.set("toast_seconds", 0.0)
	var d: Dictionary = s.call("to_dict")
	var s2: Node = (load(SETTINGS_SCRIPT) as GDScript).new()
	s2.call("from_dict", d)
	t.check_eq(str(s2.get("locale")), "en", "язык пережил round-trip")
	t.check_eq(float(s2.get("ui_scale")), 1.25, "масштаб UI пережил round-trip")
	t.check_eq(bool(s2.get("pause_on_cycle")), false, "флажок автопаузы сохранён")
	t.check_eq(float(s2.get("toast_seconds")), 0.0, "«не закрывать сами» сохранено")
	# Мусор в файле не должен ломать игру: значения зажимаются.
	var s3: Node = (load(SETTINGS_SCRIPT) as GDScript).new()
	s3.call("from_dict", {"ui_scale": 99.0, "default_speed": 42, "world_zoom": 0})
	t.check(float(s3.get("ui_scale")) <= 1.5, "масштаб UI зажат сверху")
	t.check(int(s3.get("default_speed")) <= 3, "скорость зажата")
	t.check(int(s3.get("world_zoom")) >= 2, "зум мира зажат снизу")
	s.free()
	s2.free()
	s3.free()

## Профиль: подсветка новых разблокировок и показанные подсказки переживают
## запись — иначе после перезапуска игрок увидит все уроки заново.
static func test_profile_keeps_seen_and_hints(t: TestCtx) -> void:
	var m: Node = (load(META_SCRIPT) as GDScript).new()
	(m.get("unlocked") as Array).append("u_winch")
	t.check(bool(m.call("is_unlock_new", "u_winch")), "купленное и не просмотренное — новое")
	m.call("mark_unlocks_seen")
	t.check(not bool(m.call("is_unlock_new", "u_winch")), "после просмотра не светится")
	t.check(bool(m.call("note_hint", "first_storm")), "подсказка показывается один раз")
	t.check(not bool(m.call("note_hint", "first_storm")), "повторно — нет")
	var d: Dictionary = m.call("to_dict")
	var m2: Node = (load(META_SCRIPT) as GDScript).new()
	m2.call("from_dict", d)
	t.check(not bool(m2.call("is_unlock_new", "u_winch")), "просмотренное пережило запись")
	t.check(not bool(m2.call("note_hint", "first_storm")), "показанная подсказка пережила запись")
	m.free()
	m2.free()

## У каждого исхода забега свой заголовок: без этого проигрыш и победа
## выглядели бы одинаково.
static func test_run_outcomes_have_keys(t: TestCtx) -> void:
	var seen: Dictionary[String, bool] = {}
	for kind: int in SimTypes.RunEnd.values():
		var key: String = RunSummary._outcome_key(kind)
		t.check(not key.is_empty(), "исход %d без ключа" % kind)
		t.check(not seen.has(key), "исходы делят один ключ: %s" % key)
		seen[key] = true
	t.check_eq(seen.size(), SimTypes.RunEnd.values().size(), "по ключу на исход")

## Колонка потерь собирается из разных полей отчёта — это главная колонка
## итога цикла (docs/03 §4.3).
static func test_cycle_losses_merge(t: TestCtx) -> void:
	var report: Dictionary = {
		"spoiled": {"catch": 3, "rations": 1},
		"stolen": {"catch": 2},
	}
	var lost: Dictionary = CycleSummary._losses(report)
	t.check_eq(int(lost["catch"]), 5, "порча и кража складываются по предмету")
	t.check_eq(int(lost["rations"]), 1, "предмет без кражи тоже в колонке")
	t.check_eq(CycleSummary._losses({}).size(), 0, "пустой отчёт — пустая колонка")

## Подсказки-уроки: у каждой должен быть текст, иначе игрок увидит сырой ключ.
static func test_hints_have_texts(t: TestCtx) -> void:
	var csv: String = FileAccess.get_file_as_string("res://assets/i18n/strings.csv")
	for id: String in HintCard.HINTS:
		var key: String = HintCard.HINTS[id]
		t.check(csv.contains("%s," % key), "нет текста подсказки %s" % key)
	# Финальная сизигия обещана в docs/00 §11.2 — без неё испытание немое.
	t.check(HintCard.HINTS.has("final_spring"),
		"нет подсказки про сизигию последнего цикла")
