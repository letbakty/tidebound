class_name HintCard
extends Control
## Карточка-урок при первом столкновении с механикой (docs/01 §3, docs/03 §6).
##
## Правый ВЕРХ: тосты и кнопка отзыва живут в правом низу, перекрывать их
## нельзя (research/22 §6).

signal shown_hint(id: String)

## Триггеры первых событий. Ключ — id подсказки, значение — ключ текста.
##
## Первые четыре — уроки ЯДРА, а не реакции на беду: цель забега, политики,
## Отзыв и высота. Их нельзя узнать наблюдением, поэтому они показываются по
## расписанию первого забега, а не по первому столкновению (RETENTION-pass §2.2).
##
## Ещё два — «Жадность» и «пути нет» — объясняют то, что первый живой игрок
## принял за баг: колонисты не спускаются вниз. Поведение при этом верное,
## молчала игра (FIX-playtest-01 §1).
const HINTS: Dictionary[String, String] = {
	"first_goal": "HINT_GOAL",
	"first_policies": "HINT_POLICIES",
	"first_greed": "HINT_GREED",
	"first_no_path": "HINT_NO_PATH",
	"first_signal": "HINT_SIGNAL",
	"first_below_zero": "HINT_HEIGHT",
	"first_storm": "HINT_STORM",
	"first_visit": "HINT_VISIT",
	"first_spring": "HINT_SPRING",
	"final_spring": "HINT_FINAL_SPRING",
	"first_spoil": "HINT_SPOIL",
	"first_washed": "HINT_WASHED",
	"first_wet_wood": "HINT_WET_WOOD",
}
## Уроки ядра — только на ПЕРВОМ забеге профиля: на втором игрок уже знает
## правила, и карточка в первую же секунду читается как шум. note_hint и так
## не повторяет показанное, но профиль, где подсказки были выключены и потом
## включены обратно, иначе получил бы их посреди десятого забега.
const FIRST_RUN_ONLY: Array[String] = ["first_goal", "first_policies",
	"first_signal", "first_below_zero"]
## Как часто спрашивать sim, почему человек стоит, мс. Ответ стоит обхода
## задач с поиском пути, а урок нужен один раз за профиль — поэтому опрос
## идёт не чаще раза в две секунды и только пока хоть один урок не показан.
const IDLE_POLL_MS: int = 2000
## Как часто проверять, свободен ли экран от модального окна (драфт, итог
## цикла). Сигнала «модальное открылось/закрылось» в контракте нет, и заводить
## его ради подсказки дороже, чем раз в полсекунды спросить. Таймер живёт
## только пока карточка на руках.
const WATCH_SEC: float = 0.5

var _panel: PixelPanel = null
var _text: Label = null
var _queue: Array[String] = []
var _showing: bool = false
## Общая очередь уведомлений HUD. Урок встаёт в неё, а не открывается поверх:
## на скриншоте первого живого игрока разом висели банер «Приход», драфт
## «План вылазки» и карточка урока — три текста читает ноль человек
## (FIX-playtest-01 §4).
var _notices: NoticeQueue = null
## Callable() -> bool: занят ли экран модальным окном. Ставит Main; пустой
## вызов значит «не занят».
var _busy_check: Callable = Callable()
var _watch: Timer = null
var _idle_polled_ms: int = -IDLE_POLL_MS
## Сколько отступить сверху, чтобы не накрыть верхнюю строку HUD. Ставит
## Main по её высоте: карточка живёт на своём слое и о TopBar не знает.
var _top_offset: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_watch = Timer.new()
	_watch.name = "ScreenWatch"
	_watch.wait_time = WATCH_SEC
	_watch.timeout.connect(_on_watch)
	add_child(_watch)
	Events.crisis_announced.connect(_on_crisis)
	Events.cycle_ended.connect(_on_cycle_ended)
	Events.phase_changed.connect(_on_phase_changed)
	_watch_resources()
	_watch_agents()
	Events.run_started.connect(_on_run_started)

func _build() -> void:
	_panel = PixelPanel.new()
	_panel.name = "Card"
	_panel.custom_minimum_size = Vector2(320.0, 0.0)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.visible = false
	_panel.position.y = _top_offset
	add_child(_panel)
	_panel.setup("HINT_TITLE", true)
	_text = Label.new()
	UILayout.wrap(_text, 280.0)
	_panel.add_content(_text)
	var ok: PixelButton = PixelButton.new()
	ok.setup("HINT_OK", PixelButton.Variant.PRIMARY)
	ok.pressed.connect(_close_current)
	_panel.add_content(ok)
	_panel.closed.connect(_close_current)

## ⚠️ Помечаем показанной в момент постановки в очередь, а не показа: иначе
## выход из игры с непоказанной подсказкой повторит её при следующем запуске
## (research/22 §6).
func trigger(id: String) -> void:
	if not Settings.hints_enabled or not HINTS.has(id):
		return
	if FIRST_RUN_ONLY.has(id) and Meta.runs_played > 0:
		return
	if _queue.has(id) or not Meta.note_hint(id):
		return
	_queue.append(id)
	if _notices != null:
		# Место урока в очереди HUD занимает ОДИН слот на все накопленные
		# карточки: очередь самих карточек ведёт этот узел. Заявка подаётся
		# только на первую — вторая заявка при занятом слоте дала бы пустой
		# показ после закрытия последней карточки.
		if not _showing and _queue.size() == 1:
			_notices.push(NoticeQueue.Kind.HINT, {})
		return
	if not _showing:
		_show_next()

## Очередь уведомлений сообщила, что место урока свободно.
func show_from_queue(_payload: Dictionary) -> void:
	_show_next()

## Кто решает, занят ли экран модальным окном (драфт, итог цикла). Ставит Main.
func set_busy_check(check: Callable) -> void:
	_busy_check = check

func _screen_busy() -> bool:
	return _busy_check.is_valid() and bool(_busy_check.call())

func _show_next() -> void:
	if _queue.is_empty():
		_showing = false
		_panel.visible = false
		_watch.stop()
		if _notices != null:
			_notices.release(NoticeQueue.Kind.HINT)
		return
	_showing = true
	var id: String = _queue.pop_front()
	_text.text = _format(id, tr(HINTS[id]))
	_panel.position.y = _top_offset
	# Поверх драфта урок не лезет: он ждёт, пока окно закроют, и появляется
	# сам — читать три текста разом невозможно (FIX-playtest-01 §4).
	_panel.visible = not _screen_busy()
	_watch.start()
	shown_hint.emit(id)

## Модальное окно открылось или закрылось — карточка прячется и возвращается.
func _on_watch() -> void:
	if not _showing:
		_watch.stop()
		return
	_panel.visible = not _screen_busy()

## Числа в уроках берутся из Balance и из мира, а не из строки: балансный
## проход правит шкалу Жадности, длину забега и стартовые лестницы, и урок
## обязан поехать вместе с ними.
func _format(id: String, text: String) -> String:
	match id:
		"first_goal":
			return text.format({"n": Balance.CYCLES_PER_RUN})
		"first_greed":
			var value: int = int(Game.query_policies().get(
				SimTypes.Policy.GREED, Balance.POLICY_DEFAULTS[SimTypes.Policy.GREED]))
			return text.format({"n": Balance.GREED_LADDER_LIMIT[
				clampi(value, 0, Balance.GREED_LADDER_LIMIT.size() - 1)]})
		"first_no_path":
			return text.format({"mark": Game.query_deepest_reachable_mark()})
	return text

## Карточка живёт ПОД верхней строкой. Иначе первый же урок первого забега
## накрывает ровно ту кнопку, на которую сам и показывает, — и заодно чипы
## колонистов (docs/03 §6: правый ВЕРХ, но не поверх постоянных зон).
func set_top_offset(px: float) -> void:
	_top_offset = px
	if _panel != null:
		_panel.position.y = px

## Очередь уведомлений HUD. Ставит Main сразу после сборки HUD.
func set_notice_queue(queue: NoticeQueue) -> void:
	_notices = queue
	if queue != null:
		queue.show_hint.connect(show_from_queue)

## Тап игрока по миру (зовёт Main). Клетка ниже конца лестницы — это и есть
## «попытка дойти ниже»: приказов в игре нет, и другого способа спросить
## «почему туда никто не идёт» у игрока не осталось (FIX-playtest-01 §1).
func note_world_cell(cell: Vector2i) -> void:
	if not Settings.hints_enabled or Meta.hint_shown("first_no_path"):
		return
	if Balance.cell_to_mark(cell) < Game.query_deepest_reachable_mark():
		trigger("first_no_path")

func _close_current() -> void:
	_show_next()

func _on_run_started(_seed_value: int) -> void:
	_queue.clear()
	_showing = false
	_panel.visible = false
	_watch.stop()
	_idle_polled_ms = -IDLE_POLL_MS
	_watch_resources()          # подсказки могли включить в настройках
	_watch_agents()
	# ПЕРВОЙ — цель. До неё игра не говорила о себе ни строчки: «Цикл 1/12»
	# и всё, а «цель не хорошо понятна» стало первой претензией первого
	# живого игрока (FIX-playtest-01 §4).
	trigger("first_goal")
	# Главное правило игры — «приказов нет» — нельзя узнать наблюдением:
	# шесть колонистов работают сами, и без этой карточки игрок первые минуты
	# смотрит на скринсейвер (RETENTION-pass §2.2).
	trigger("first_policies")

## Колокол Сигнала — момент, когда «Отзыв» впервые нужен; спуск ниже нуля —
## момент, когда шкала слева впервые что-то значит.
func _on_phase_changed(phase: int, _cycle: int) -> void:
	if phase == int(SimTypes.Phase.SIGNAL):
		trigger("first_signal")

func _on_crisis(type: int, cycle: int) -> void:
	match type:
		int(SimTypes.CrisisType.STORM): trigger("first_storm")
		int(SimTypes.CrisisType.VISIT): trigger("first_visit")
		int(SimTypes.CrisisType.SPRING_TIDE):
			# Сизигия последнего цикла — то самое финальное испытание из
			# docs/00 §11.2: ценное надо заранее поднять на +3 и выше.
			if cycle >= Balance.CYCLES_PER_RUN:
				trigger("final_spring")
			else:
				trigger("first_spring")

## Событий «первая порча» и «первый смытый склад» в контракте нет — берём их
## из отчёта цикла, а не расширяем шину ради подсказок (research/22 §6).
func _on_cycle_ended(report: Dictionary) -> void:
	if not (report.get("spoiled", {}) as Dictionary).is_empty():
		trigger("first_spoil")
	if int(report.get("washed", 0)) > 0:
		trigger("first_washed")

## Урок про мокрый плавник — единственный, ради которого нужен сторож на
## resources_changed. Подписка снимается, как только он показан: два обхода
## складов на КАЖДОЕ изменение ресурсов до конца сессии — чистая трата
## (аудит B3).
func _watch_resources() -> void:
	var need: bool = Settings.hints_enabled and not Meta.hint_shown("first_wet_wood")
	var on: bool = Events.resources_changed.is_connected(_on_resources_bound)
	if need and not on:
		Events.resources_changed.connect(_on_resources_bound)
	elif not need and on:
		Events.resources_changed.disconnect(_on_resources_bound)

## Отдельный именованный обработчик: unbind-обёртку не отсоединить обратно —
## каждый вызов .unbind() даёт НОВЫЙ Callable.
func _on_resources_bound(_totals: Dictionary) -> void:
	_on_resources()

## Сторож «первый спуск ниже нуля» снимается сразу после показа — по той же
## причине, что и сторож мокрого плавника: срез агента на КАЖДОЕ обновление
## до конца сессии не нужен никому. На том же стороже висит и урок Жадности:
## оба смотрят на одно — где сейчас люди и чем они заняты.
func _watch_agents() -> void:
	var need_below: bool = Meta.runs_played == 0 \
		and not Meta.hint_shown("first_below_zero")
	var need: bool = Settings.hints_enabled and (need_below
		or not Meta.hint_shown("first_greed")
		or not Meta.hint_shown("first_no_path"))
	var on: bool = Events.agent_updated.is_connected(_on_agent_updated)
	if need and not on:
		Events.agent_updated.connect(_on_agent_updated)
	elif not need and on:
		Events.agent_updated.disconnect(_on_agent_updated)

func _on_agent_updated(id: int) -> void:
	var a: Dictionary = Game.query_agent_look(id)
	if a.is_empty() or bool(a["dead"]):
		return
	if int(a["state"]) == int(SimTypes.AgentState.IDLE):
		_check_idle()
	if float(a["mark"]) < 0.0 and Meta.runs_played == 0:
		trigger("first_below_zero")
	_watch_agents()

## Человек стоит без дела — и вопрос ровно один: почему. Ответ даёт sim, и
## ответов два: «мешает Жадность» (ползунок двигается мгновенно) и «нет пути»
## (нужна лестница). Это и есть та самая претензия «не опускаются вниз, баг»
## (FIX-playtest-01 §1) — и урок обязан назвать ПРАВИЛЬНУЮ причину.
##
## Замер на стартовой карте: из 15.3 свободных задач до простаивающего
## доходят 0.17, и отсекает их достижимость, а не политика. Поэтому
## «нет пути» здесь не запасной случай, а основной.
##
## Опрос дорогой (обход задач с поиском пути), поэтому не чаще IDLE_POLL_MS
## и только пока хоть один из двух уроков не показан.
func _check_idle() -> void:
	if Meta.hint_shown("first_greed") and Meta.hint_shown("first_no_path"):
		return
	var now: int = Time.get_ticks_msec()
	if now - _idle_polled_ms < IDLE_POLL_MS:
		return
	_idle_polled_ms = now
	match Game.query_idle_reason():
		"greed": trigger("first_greed")
		"path": trigger("first_no_path")

## Мокрый плавник виден как расхождение общего и сухого остатка.
func _on_resources() -> void:
	var total: int = int(Game.query_totals().get("driftwood", 0))
	var dry: int = int(Game.query_dry_totals().get("driftwood", 0))
	if total > dry:
		trigger("first_wet_wood")
	_watch_resources()
