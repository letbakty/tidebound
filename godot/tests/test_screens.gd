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

# --- Блок 1 аудита: пять блокеров (audit/01-minuses.md §B1) ----------------

## B1.2 · чёрный экран на старте. `current` был инициализирован BOOT, и первый
## же goto(BOOT) выходил по ветке «уже там»: on_enter не звался, полоса стояла,
## finished не эмитился. Проверяем сентинел NONE.
static func test_first_goto_enters_screen(t: TestCtx) -> void:
	var router: ScreenRouter = ScreenRouter.new()
	t.check_eq(int(router.current), int(ScreenRouter.Screen.NONE),
		"до первого перехода экрана нет")
	var boot: ScreenBase = ScreenBase.new()
	router.register(ScreenRouter.Screen.BOOT, boot)
	router.goto(ScreenRouter.Screen.BOOT)
	t.check(boot.visible, "первый экран показан, а не пропущен")
	t.check_eq(int(router.current), int(ScreenRouter.Screen.BOOT), "роутер это помнит")
	router.free()

## B1.4 · итог цикла проглатывался драфтом. sim эмитит cycle_ended и draft_ready
## одним батчем; open_modal(DRAFT) молча закрывал Итог, и единственный pop_pause
## того уровня не нажимался — после драфта игра стояла на паузе навсегда.
static func test_second_modal_waits_in_queue(t: TestCtx) -> void:
	var router: ScreenRouter = ScreenRouter.new()
	router.register(ScreenRouter.Screen.GAME, ScreenBase.new())
	var summary: Control = Control.new()
	var draft: Control = Control.new()
	router.register_modal(ScreenRouter.Modal.CYCLE_SUMMARY, summary)
	router.register_modal(ScreenRouter.Modal.DRAFT, draft)
	router.goto(ScreenRouter.Screen.GAME)
	router.open_modal(ScreenRouter.Modal.CYCLE_SUMMARY, {}, false)
	router.open_modal(ScreenRouter.Modal.DRAFT, {}, false)
	t.check(summary.visible and not draft.visible, "Итог показан, драфт ждёт")
	t.check_eq(router.queued_modals(), 1, "драфт в очереди, а не выброшен")
	router.close_modal()
	t.check(draft.visible and not summary.visible, "после Итога открылся драфт")
	t.check_eq(router.queued_modals(), 0, "очередь разобрана")
	router.close_modal()
	t.check(not draft.visible, "последнее окно закрылось")
	router.free()

## Счётчик автопаузы обязан сойтись, даже если окно закрыли не кнопкой:
## Итог забега вытесняет Итог цикла, и «унаследованная» пауза уходит с ним.
static func test_preempting_modal_releases_pause(t: TestCtx) -> void:
	var router: ScreenRouter = ScreenRouter.new()
	router.register(ScreenRouter.Screen.GAME, ScreenBase.new())
	router.register_modal(ScreenRouter.Modal.CYCLE_SUMMARY, Control.new())
	router.register_modal(ScreenRouter.Modal.DRAFT, Control.new())
	router.register_modal(ScreenRouter.Modal.RUN_SUMMARY, Control.new())
	router.goto(ScreenRouter.Screen.GAME)
	var depth0: int = Game.pause_depth()
	Game.push_pause()                       # так паузу ставит Game на границе
	Game.push_pause()                       # цикла и на драфте
	router.open_modal(ScreenRouter.Modal.CYCLE_SUMMARY, {}, false, true)
	router.open_modal(ScreenRouter.Modal.DRAFT, {}, false, true)
	router.open_modal(ScreenRouter.Modal.RUN_SUMMARY, {}, false)
	t.check_eq(int(router.modal), int(ScreenRouter.Modal.RUN_SUMMARY),
		"Итог забега вытесняет Итог цикла (docs/03 §8)")
	t.check_eq(router.queued_modals(), 0, "очередь забега очищена")
	t.check_eq(Game.pause_depth(), depth0,
		"обе автопаузы сняты вместе с окнами, а не зависли")
	router.close_modal()
	router.free()

## Окно забега не открывается поверх экрана: ждёт возвращения в игру.
## Так драфт переживает выход в меню и показывается снова (docs/03 §8).
static func test_game_modal_waits_for_game_screen(t: TestCtx) -> void:
	var router: ScreenRouter = ScreenRouter.new()
	router.register(ScreenRouter.Screen.MAIN_MENU, ScreenBase.new())
	router.register(ScreenRouter.Screen.GAME, ScreenBase.new())
	var draft: Control = Control.new()
	router.register_modal(ScreenRouter.Modal.DRAFT, draft)
	router.goto(ScreenRouter.Screen.MAIN_MENU)
	router.open_modal(ScreenRouter.Modal.DRAFT, {}, false)
	t.check(not draft.visible, "поверх меню модальное не открылось")
	t.check_eq(router.queued_modals(), 1, "и не потерялось")
	router.goto(ScreenRouter.Screen.GAME)
	t.check(draft.visible, "в игре драфт показан")
	router.close_modal()
	router.free()

## B1.5 · мир под меню и настройками продолжал тикать: агенты тонули в фоне,
## автосейв переписывал сейв, run_ended открывал Итог поверх меню.
##
## Гейт — отдельный флаг, а не автопауза: счётчик автопауз обнуляют cmd_new_run
## и restore_world, и «заявка» роутера поверх них разъезжается со счётчиком.
static func test_screen_stops_live_world(t: TestCtx) -> void:
	var router: ScreenRouter = ScreenRouter.new()
	router.register(ScreenRouter.Screen.GAME, ScreenBase.new())
	router.register(ScreenRouter.Screen.MAIN_MENU, ScreenBase.new())
	var depth0: int = Game.pause_depth()
	var speed_before: int = Game.speed
	router.goto(ScreenRouter.Screen.GAME)
	t.check(not Game.world_hidden, "в игре мир тикает")
	router.goto(ScreenRouter.Screen.MAIN_MENU)
	t.check(Game.world_hidden, "под экраном мир выключен")
	t.check_eq(Game.pause_depth(), depth0,
		"и счётчик автопауз при этом не тронут")
	t.check_eq(Game.speed, speed_before,
		"выбранная игроком скорость сохранена, а не сброшена")
	router.goto(ScreenRouter.Screen.GAME)
	t.check(not Game.world_hidden, "возврат в игру снова пускает время")
	router.free()
	t.check(not Game.world_hidden, "уходя, роутер снимает свой гейт")

## B1.3 · экран первого запуска был недостижим: Settings._ready -> apply ->
## mark_dirty писал файл в первом же кадре, и has_file() к концу заставки
## отвечал «да» на любом запуске. Флаг обязан сниматься ДО записи.
static func test_first_launch_flag_precedes_write(t: TestCtx) -> void:
	var src: String = FileAccess.get_file_as_string(SETTINGS_SCRIPT)
	var ready_at: int = src.find("func _ready()")
	var flag_at: int = src.find("first_launch = not has_file()")
	var apply_at: int = src.find("\tapply()", ready_at)
	t.check(flag_at > ready_at, "флаг снимается внутри _ready")
	t.check(flag_at < apply_at, "и ДО apply(), который порождает файл")

## B1.1 · зависание на пятом тосте: queue_free не убирает ноду из дерева до
## конца кадра, и `while get_child_count() > MAX` крутился вечно.
static func test_toast_overflow_terminates(t: TestCtx) -> void:
	var stack: ToastStack = ToastStack.new()
	var box: VBoxContainer = VBoxContainer.new()
	stack.add_child(box)
	stack.set("_box", box)
	for i: int in ToastStack.MAX_VISIBLE + 3:
		var toast: Toast = Toast.new()
		box.add_child(toast)
		# Ровно тело переполнения из push(): выйти из него обязан любой ввод.
		while box.get_child_count() > ToastStack.MAX_VISIBLE:
			var oldest: Node = box.get_child(0)
			box.remove_child(oldest)
			oldest.queue_free()
	t.check_eq(box.get_child_count(), ToastStack.MAX_VISIBLE,
		"лишние тосты вытеснены, а не накопились")
	stack.free()

## Одно снятие автопаузы на одну постановку. Драфт поверх банера кризиса не
## имеет права отпустить чужую паузу вместе со своей: игра пошла бы под
## открытым банером (регрессия ремонта B1.4).
static func test_draft_releases_only_its_own_pause(t: TestCtx) -> void:
	var router: ScreenRouter = ScreenRouter.new()
	router.register(ScreenRouter.Screen.GAME, ScreenBase.new())
	router.register_modal(ScreenRouter.Modal.DRAFT, Control.new())
	router.goto(ScreenRouter.Screen.GAME)
	var depth0: int = Game.pause_depth()
	Game.push_pause()                       # банер кризиса
	Game.push_pause()                       # драфт поверх него
	router.open_modal(ScreenRouter.Modal.DRAFT, {}, false, true)
	router.close_modal()
	t.check_eq(Game.pause_depth(), depth0 + 1,
		"после драфта пауза банера ещё держится")
	# Команда выбора карты автопаузу больше НЕ трогает — это работа роутера.
	var src: String = FileAccess.get_file_as_string("res://autoload/game.gd")
	var pick_at: int = src.find("func cmd_pick_card")
	var next_func: int = src.find("\nfunc ", pick_at + 1)
	t.check(not src.substr(pick_at, next_func - pick_at).contains("pop_pause()"),
		"cmd_pick_card снимает паузу второй раз — счётчик уедет в чужую")
	Game.pop_pause()
	router.free()

## ⚠️ Каркас экрана обязан быть прозрачным для мыши. Экраны лежат на самом
## верхнем слое (40), и прозрачный полноэкранный Margin/Box/Content на нём
## съедал клики у HUD, панелей и банеров: в забеге не нажималось ничего.
## Перехват оставлен только КОРНЮ экрана — он и не должен пропускать вглубь.
static func test_screen_frame_is_click_through(t: TestCtx) -> void:
	# _ready() зовём руками: в headless-раннере виджеты в дерево не кладём
	# (см. шапку tests/test_hud.gd).
	var screen: ScreenBase = ScreenBase.new()
	screen._ready()
	t.check_eq(int(screen.mouse_filter), int(Control.MOUSE_FILTER_STOP),
		"корень экрана перехватывает мышь сам")
	for path: String in ["Margin", "Margin/Box", "Margin/Box/Header",
			"Margin/Box/Content"]:
		var node: Control = screen.get_node_or_null(NodePath(path)) as Control
		t.check(node != null, "каркас содержит %s" % path)
		if node == null:
			continue
		t.check_eq(int(node.mouse_filter), int(Control.MOUSE_FILTER_IGNORE),
			"%s не перехватывает мышь" % path)
	screen.free()

## Экран забега — пустышка: ни узлов, ни прямоугольника. Каркас поверх живой
## игры не нужен и вреден (см. тест выше).
static func test_game_screen_has_no_frame(t: TestCtx) -> void:
	var screen: GameScreen = GameScreen.new()
	screen._ready()
	t.check_eq(screen.get_child_count(), 0, "у экрана игры нет ни одного узла")
	t.check_eq(int(screen.mouse_filter), int(Control.MOUSE_FILTER_IGNORE),
		"и он не перехватывает мышь")
	t.check(screen.content == null, "каркас не собран вовсе")
	screen.free()
