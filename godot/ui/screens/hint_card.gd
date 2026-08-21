class_name HintCard
extends Control
## Карточка-урок при первом столкновении с механикой (docs/01 §3, docs/03 §6).
##
## Правый ВЕРХ: тосты и кнопка отзыва живут в правом низу, перекрывать их
## нельзя (research/22 §6).

signal shown_hint(id: String)

## Триггеры первых событий. Ключ — id подсказки, значение — ключ текста.
const HINTS: Dictionary[String, String] = {
	"first_storm": "HINT_STORM",
	"first_visit": "HINT_VISIT",
	"first_spring": "HINT_SPRING",
	"final_spring": "HINT_FINAL_SPRING",
	"first_spoil": "HINT_SPOIL",
	"first_washed": "HINT_WASHED",
	"first_wet_wood": "HINT_WET_WOOD",
}

var _panel: PixelPanel = null
var _text: Label = null
var _queue: Array[String] = []
var _showing: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	Events.crisis_announced.connect(_on_crisis)
	Events.cycle_ended.connect(_on_cycle_ended)
	Events.resources_changed.connect(_on_resources.unbind(1))
	Events.run_started.connect(_on_run_started)

func _build() -> void:
	_panel = PixelPanel.new()
	_panel.name = "Card"
	_panel.custom_minimum_size = Vector2(320.0, 0.0)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.visible = false
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
	_panel.visible = true
	shown_hint.emit(id)

func _close_current() -> void:
	_show_next()

func _on_run_started(_seed_value: int) -> void:
	_queue.clear()
	_showing = false
	_panel.visible = false

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

## Мокрый плавник виден как расхождение общего и сухого остатка.
func _on_resources() -> void:
	var total: int = int(Game.query_totals().get("driftwood", 0))
	var dry: int = int(Game.query_dry_totals().get("driftwood", 0))
	if total > dry:
		trigger("first_wet_wood")
