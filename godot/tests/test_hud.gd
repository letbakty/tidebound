extends RefCounted
## Тесты HUD (этап 13): очередь уведомлений, геометрия шкалы, оверлеи и —
## главное — сигнатуры подписок на Events.
##
## Автолоадов в headless-раннере нет (Godot не поднимает их при --script),
## поэтому виджеты здесь не инстанцируются в дерево: проверяем чистую логику
## и статический разбор исходников.

const EVENTS_PATH: String = "res://autoload/events.gd"
## Где ищем подписки на шину. debug/ тоже: там их больше всего.
## autoload/ тоже: с этапа 17 там живёт AudioService, и подписок у него больше,
## чем у любого виджета.
const SCAN_DIRS: Array[String] = ["res://ui/", "res://game/", "res://debug/",
	"res://autoload/"]

## Приоритеты: банер важнее подсказки, подсказка важнее тоста. Без единой
## очереди три источника начинают накладываться друг на друга (research/25 §4).
static func test_notice_queue_priority(t: TestCtx) -> void:
	var q: NoticeQueue = NoticeQueue.new()
	var order: Array[String] = []
	q.show_toast.connect(func(_p: Dictionary) -> void: order.append("toast"))
	q.show_banner.connect(func(_p: Dictionary) -> void: order.append("banner"))
	q.show_hint.connect(func(_p: Dictionary) -> void: order.append("hint"))
	q.push(NoticeQueue.Kind.TOAST, {})
	q.push(NoticeQueue.Kind.HINT, {})
	q.push(NoticeQueue.Kind.BANNER, {})
	t.check_eq(order, ["toast", "hint", "banner"] as Array[String],
		"порядок показа: каждый уходит сразу, пока место свободно")

	# Место банера занято — следующий ждёт освобождения, а не лезет поверх.
	order.clear()
	q.push(NoticeQueue.Kind.BANNER, {"n": 2})
	t.check(order.is_empty(), "второй банер не должен показаться поверх первого")
	q.release(NoticeQueue.Kind.BANNER)
	t.check_eq(order, ["banner"] as Array[String], "после release банер показан")
	q.free()

static func test_notice_queue_toasts_never_block(t: TestCtx) -> void:
	var q: NoticeQueue = NoticeQueue.new()
	# Счётчик — в массиве: лямбды GDScript захватывают локальные значения
	# по КОПИИ, и обычный int из замыкания наружу не вернётся.
	var shown: Array[int] = [0]
	q.show_toast.connect(func(_p: Dictionary) -> void: shown[0] += 1)
	for i: int in 5:
		q.push(NoticeQueue.Kind.TOAST, {"i": i})
	t.check_eq(shown[0], 5, "тосты не занимают место друг друга")
	q.free()

## Геометрия шкалы: единственный сложный _draw в проекте.
static func test_tide_gauge_geometry(t: TestCtx) -> void:
	var gauge: TideGauge = TideGauge.new()
	gauge.size = Vector2(float(UITokens.TIDE_WIDTH), 600.0)
	var y_top: float = gauge.call("_mark_to_y", float(TideGauge.MARK_TOP))
	var y_zero: float = gauge.call("_mark_to_y", 0.0)
	var y_bottom: float = gauge.call("_mark_to_y", float(TideGauge.MARK_BOTTOM))
	t.check(y_top < y_zero and y_zero < y_bottom,
		"шкала растёт вниз: +6 выше 0, 0 выше −12")
	# roundf обязателен: дробный Y даёт полупрозрачную линию и дрожь рисок.
	t.check_eq(y_zero, roundf(y_zero), "Y отметки не на целом пикселе")
	t.check(TideGauge.MARK_FLOOR == Balance.BOTTOM_MARK,
		"дно шкалы должно совпадать с дном карты из Balance")
	t.check(TideGauge.MARK_BOTTOM < TideGauge.MARK_FLOOR,
		"ниже дна карты ярусы рисуются выключенными (кит, исправление №7)")
	t.check(TideGauge.MARK_TOP == Balance.TOP_MARK, "верх шкалы — из Balance")
	# Ширина линий задаётся явно: в 4.7 нет AA-feather (research/06 §9).
	t.check(TideGauge.W_TICK > 0.0 and TideGauge.W_MARK > 0.0
		and TideGauge.W_PLATEAU > 0.0, "ширина линий должна быть задана явно")
	gauge.free()

## Оверлей занятий обязан знать КАЖДОЕ состояние агента: пропущенное даёт
## молчаливую точку вместо иконки.
static func test_overlay_covers_all_states(t: TestCtx) -> void:
	for state: int in SimTypes.AgentState.values():
		var letter: String = GameOverlay._letter_for(state)
		t.check(not letter.is_empty(), "состояние %d без буквы в оверлее" % state)
	t.check_eq(GameOverlay._letter_for(int(SimTypes.AgentState.DROWNING)), "!!",
		"тонущий должен читаться с первого взгляда")

## ⚠️ Обработчик с несовместимой сигнатурой просто НЕ вызывается, а warning
## виден только в debug-сборке (docs/02 §10). Этот тест — тот самый «смоук
## подписок»: считает аргументы сигнала и параметры обработчика.
static func test_event_handler_arity(t: TestCtx) -> void:
	var arity: Dictionary[String, int] = _signal_arity()
	t.check(arity.size() > 20, "не разобрался events.gd")
	var checked: int = 0
	var re: RegEx = RegEx.new()
	re.compile(r"Events\.([a-z_]+)\.connect\(([^\n]*?)\)\s*$")
	for path: String in _gd_files_multi(SCAN_DIRS):
		var src: String = FileAccess.get_file_as_string(path)
		for line: String in src.split("\n"):
			var m: RegExMatch = re.search(line.strip_edges())
			if m == null:
				continue
			var sig: String = m.get_string(1)
			t.check(arity.has(sig), "%s: подписка на несуществующий сигнал %s"
				% [path.get_file(), sig])
			if not arity.has(sig):
				continue
			var params: int = _callable_arity(m.get_string(2), src)
			if params < 0:
				continue                # многострочная лямбда — считать нечего
			checked += 1
			t.check_eq(params, int(arity[sig]),
				"%s: обработчик %s принимает %d аргументов, сигнал даёт %d"
					% [path.get_file(), sig, params, int(arity[sig])])
	t.check(checked > 15, "подписок нашлось подозрительно мало (%d)" % checked)

# --- Утилиты --------------------------------------------------------------

static func _signal_arity() -> Dictionary[String, int]:
	var out: Dictionary[String, int] = {}
	var re: RegEx = RegEx.new()
	re.compile(r"^signal\s+([a-z_]+)\(([^)]*)\)")
	for line: String in FileAccess.get_file_as_string(EVENTS_PATH).split("\n"):
		var m: RegExMatch = re.search(line)
		if m == null:
			continue
		out[m.get_string(1)] = _count_params(m.get_string(2))
	return out

static func _count_params(text: String) -> int:
	var body: String = text.strip_edges()
	if body.is_empty():
		return 0
	return body.split(",").size()

## Возвращает число аргументов, которое реально примет обработчик, или −1,
## если посчитать нельзя (многострочная лямбда).
static func _callable_arity(target: String, src: String) -> int:
	var text: String = target.strip_edges()
	var bonus: int = 0
	var unbind: RegEx = RegEx.new()
	unbind.compile(r"\.unbind\((\d+)\)$")
	var m: RegExMatch = unbind.search(text)
	if m != null:
		bonus = int(m.get_string(1))
		text = text.substr(0, m.get_start())
	if text.begins_with("func("):
		var close: int = text.find(")")
		if close < 0:
			return -1
		return _count_params(text.substr(5, close - 5)) + bonus
	if text.contains("func(") or text.contains("(") or text.contains(" "):
		return -1                       # лямбда или выражение
	var name: String = text.get_slice(".", text.get_slice_count(".") - 1)
	var decl: RegEx = RegEx.new()
	decl.compile(r"func\s+%s\(([^)]*)\)" % name)
	var d: RegExMatch = decl.search(src)
	if d == null:
		return -1                       # встроенный метод вроде queue_redraw
	return _count_params(d.get_string(1)) + bonus

static func _gd_files_multi(dirs: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for d: String in dirs:
		out.append_array(_gd_files(d))
	return out

static func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while not name.is_empty():
		var full: String = dir_path.path_join(name)
		if dir.current_is_dir():
			out.append_array(_gd_files(full))
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out
