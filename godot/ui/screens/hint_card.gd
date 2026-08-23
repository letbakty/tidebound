class_name HintCard
extends Control
## Карточка-урок при первом столкновении с механикой (docs/01 §3, docs/03 §6).
##
## Правый ВЕРХ: тосты и кнопка отзыва живут в правом низу, перекрывать их
## нельзя (research/22 §6).

signal shown_hint(id: String)

## Триггеры первых событий. Ключ — id подсказки, значение — ключ текста.
##
## Первые три — уроки ЯДРА, а не реакции на беду: политики, Отзыв и высота.
## Их нельзя узнать наблюдением, поэтому они показываются по расписанию
## первого забега, а не по первому столкновению (RETENTION-pass §2.2).
const HINTS: Dictionary[String, String] = {
	"first_policies": "HINT_POLICIES",
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
const FIRST_RUN_ONLY: Array[String] = ["first_policies", "first_signal",
	"first_below_zero"]

var _panel: PixelPanel = null
var _text: Label = null
var _queue: Array[String] = []
var _showing: bool = false
## Сколько отступить сверху, чтобы не накрыть верхнюю строку HUD. Ставит
## Main по её высоте: карточка живёт на своём слое и о TopBar не знает.
var _top_offset: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
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
	if not _showing:
		_show_next()

func _show_next() -> void:
	if _queue.is_empty():
		_showing = false
		_panel.visible = false
		return
	_showing = true
	var id: String = _queue.pop_front()
	_text.text = tr(HINTS[id])
	_panel.position.y = _top_offset
	_panel.visible = true
	shown_hint.emit(id)

## Карточка живёт ПОД верхней строкой. Иначе первый же урок первого забега
## накрывает ровно ту кнопку, на которую сам и показывает, — и заодно чипы
## колонистов (docs/03 §6: правый ВЕРХ, но не поверх постоянных зон).
func set_top_offset(px: float) -> void:
	_top_offset = px
	if _panel != null:
		_panel.position.y = px

func _close_current() -> void:
	_show_next()

func _on_run_started(_seed_value: int) -> void:
	_queue.clear()
	_showing = false
	_panel.visible = false
	_watch_resources()          # подсказки могли включить в настройках
	_watch_agents()
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
## до конца сессии не нужен никому.
func _watch_agents() -> void:
	var need: bool = Settings.hints_enabled and Meta.runs_played == 0 \
		and not Meta.hint_shown("first_below_zero")
	var on: bool = Events.agent_updated.is_connected(_on_agent_updated)
	if need and not on:
		Events.agent_updated.connect(_on_agent_updated)
	elif not need and on:
		Events.agent_updated.disconnect(_on_agent_updated)

func _on_agent_updated(id: int) -> void:
	var a: Dictionary = Game.query_agent_look(id)
	if a.is_empty() or bool(a["dead"]) or float(a["mark"]) >= 0.0:
		return
	trigger("first_below_zero")
	_watch_agents()

## Мокрый плавник виден как расхождение общего и сухого остатка.
func _on_resources() -> void:
	var total: int = int(Game.query_totals().get("driftwood", 0))
	var dry: int = int(Game.query_dry_totals().get("driftwood", 0))
	if total > dry:
		trigger("first_wet_wood")
	_watch_resources()
