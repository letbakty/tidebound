class_name GameOverlay
extends Node2D
## Игровые оверлеи мира (docs/01 §2): отметки ярусов, зона затопления
## следующего цикла, «кто чем занят». Одновременно активен один.
##
## НЕ путать с DebugOverlay этапа 03: тот живёт за is_debug_build и показывает
## внутренности (граф, остатки депозитов). Этот — часть игры и уезжает в релиз.
##
## Живёт внутри World, а не на CanvasLayer: рисует мировые координаты и
## получает трансформацию камеры бесплатно (research/13 §2).

const MODE_NONE: String = ""
const MODE_MARKS: String = "marks"
const MODE_FLOOD: String = "flood"
const MODE_JOBS: String = "jobs"

const COL_MARK: Color = Color("c9a15e", 0.5)
## Клетки, куда выбранная постройка встаёт. Зелёный тот же, что у призрака.
const COL_SPOT: Color = Color(0.45, 1.0, 0.5, 0.18)
const COL_SPOT_EDGE: Color = Color(0.45, 1.0, 0.5, 0.45)
const COL_FLOOD: Color = Color("d4553a", 0.20)
const COL_FLOOD_EDGE: Color = Color("d4553a", 0.8)

var mode: String = MODE_NONE
## Постройка, выбранная в радиале. Пока она выбрана, поверх любого режима
## светятся клетки, куда её МОЖНО поставить: красный призрак говорит «сюда
## нельзя» и молчит о том, куда можно (FIX-playtest-01 §3).
var _place_def: String = ""
var _spots: Array[Vector2i] = []
var _spot_size: Vector2i = Vector2i.ONE

var _font: Font = ThemeDB.fallback_font
var _font_size: int = ThemeDB.fallback_font_size

func _ready() -> void:
	z_index = 95
	Events.water_level_changed.connect(_redraw.unbind(1))
	Events.phase_changed.connect(_redraw.unbind(2))
	Events.crisis_announced.connect(_redraw.unbind(2))
	Events.run_started.connect(_redraw.unbind(1))
	# Занятые клетки меняются стройкой и сносом: подсветка «куда можно»
	# обязана это увидеть. Пересчёт идёт только при выбранной постройке.
	Events.building_placed.connect(_redraw.unbind(1))
	Events.building_removed.connect(_redraw.unbind(1))

## Клетки размещения пересчитываются на выбор постройки и на перестройку мира,
## а не в кадре: обход утёса стоит пары тысяч проверок.
func set_place_def(def_id: String) -> void:
	_place_def = def_id
	_refresh_spots()
	queue_redraw()

func _refresh_spots() -> void:
	_spots.clear()
	_spot_size = Vector2i.ONE
	if _place_def.is_empty() or Game.world == null:
		return
	var d: BuildingDef = DB.building(_place_def)
	if d != null:
		_spot_size = d.size
	_spots = Game.query_place_spots(_place_def)

## Повторный вызов того же режима выключает оверлей — тумблер, а не радио.
func toggle(new_mode: String) -> void:
	mode = MODE_NONE if mode == new_mode else new_mode
	queue_redraw()

func _redraw() -> void:
	# Вода поднялась, лестницу достроили — набор пригодных клеток другой.
	if not _place_def.is_empty():
		_refresh_spots()
	if mode != MODE_NONE or not _place_def.is_empty():
		queue_redraw()

func _process(_delta: float) -> void:
	# Иконки занятий висят над агентами и обязаны ехать вместе с ними.
	if mode == MODE_JOBS:
		queue_redraw()

func _draw() -> void:
	if Game.world == null:
		return
	if not _place_def.is_empty():
		_draw_spots()
	match mode:
		MODE_MARKS: _draw_marks()
		MODE_FLOOD: _draw_flood()
		MODE_JOBS: _draw_jobs()

## Куда встаёт выбранная постройка. Прямоугольник её размера, а не клетка:
## койка 2×1 и лестница 1×3 занимают разное место, и подсветка обязана
## показывать именно то, что появится.
func _draw_spots() -> void:
	var box: Vector2 = Vector2(_spot_size) * float(WorldGeo.TILE)
	for cell: Vector2i in _spots:
		var rect: Rect2 = Rect2(WorldGeo.cell_to_world(cell), box)
		draw_rect(rect, COL_SPOT, true)
		draw_rect(rect, COL_SPOT_EDGE, false, 1.0)

func _map_width_px() -> float:
	return float(Game.cliff_def().width * WorldGeo.TILE)

func _draw_marks() -> void:
	var w: float = _map_width_px()
	for m: int in range(Balance.BOTTOM_MARK, Balance.TOP_MARK + 1):
		var y: float = WorldGeo.mark_to_world_y(float(m))
		draw_line(Vector2(0.0, y), Vector2(w, y), COL_MARK, 1.0)
		draw_string(_font, Vector2(4.0, y + float(_font_size)), str(m),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size, COL_MARK)

## Зона затопления СЛЕДУЮЩЕГО цикла: плато высокой воды плюс сизигия, если
## она уже объявлена (docs/00 §5, §9.2). Числа — из Balance, не из головы.
func _draw_flood() -> void:
	var clock: Dictionary = Game.query_clock()
	var level: float = Balance.HIGH_LEVEL
	var announced: Array = clock.get("announced", []) as Array
	if announced.has(int(SimTypes.CrisisType.SPRING_TIDE)):
		level += Balance.SPRING_BONUS
	var w: float = _map_width_px()
	var y: float = WorldGeo.mark_to_world_y(level)
	var bottom: float = WorldGeo.mark_to_world_y(float(Balance.BOTTOM_MARK))
	draw_rect(Rect2(Vector2(0.0, y), Vector2(w, bottom - y)), COL_FLOOD, true)
	draw_line(Vector2(0.0, y), Vector2(w, y), COL_FLOOD_EDGE, 2.0)
	draw_string(_font, Vector2(8.0, y - 6.0),
		tr("OVERLAY_FLOOD_TO").format({"mark": "%.0f" % level}),
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size, COL_FLOOD_EDGE)

## Одна буква над агентом: чем занят. Цвет+буква — два канала (docs/01 §6).
func _draw_jobs() -> void:
	for a: SimAgent in Game.world.agents.agents:
		if not a.is_alive():
			continue
		var pos: Vector2 = Game.query_agent_pos(a.id)
		var state: int = int(a.state)
		draw_string(_font, pos + Vector2(-4.0, -float(WorldGeo.TILE)),
			_letter_for(state), HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size,
			_color_for(state))

static func _letter_for(state: int) -> String:
	match state:
		int(SimTypes.AgentState.GATHER): return "G"
		int(SimTypes.AgentState.HAUL): return "H"
		int(SimTypes.AgentState.WORK): return "W"
		int(SimTypes.AgentState.REST): return "Z"
		int(SimTypes.AgentState.EAT): return "E"
		int(SimTypes.AgentState.RETURN): return "^"
		int(SimTypes.AgentState.PANIC): return "!"
		int(SimTypes.AgentState.DROWNING): return "!!"
		int(SimTypes.AgentState.GOTO): return ">"
	return "."

static func _color_for(state: int) -> Color:
	match state:
		int(SimTypes.AgentState.PANIC), int(SimTypes.AgentState.DROWNING):
			return UIPalette.danger()
		int(SimTypes.AgentState.REST), int(SimTypes.AgentState.EAT):
			return UIPalette.warm()
		int(SimTypes.AgentState.IDLE):
			return UITokens.FAINT
	return UITokens.INK
