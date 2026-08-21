class_name BuildingView
extends Node2D
## Постройка на экране. Заглушка до настоящего арта, но по правилам пиксель-арта
## (промпт 18 п.9): силуэт, два тона и светлая кромка сверху. Плоский
## прямоугольник читается как «программерский арт» именно из-за их отсутствия.
##
## План — полупрозрачный, стройка и ремонт — с полосой прогресса, сломанная
## мигает, затопленная уходит в холод.

const PLANNED_ALPHA: float = 0.35
const DAMAGED_BLINK_HZ: float = 2.0
const FLOOD_TINT: Color = Color("6fa8c4")

## Цвет по назначению постройки — читаемость без арта.
const COLORS: Dictionary = {
	"ladder": Color("8a6a3f"), "platform": Color("9a8055"),
	"storage": Color("b09a6a"), "hearth": Color("c46a3a"),
	"bunk": Color("7a6a8a"), "raincatcher": Color("6a90a8"),
	"forge": Color("a05040"), "workbench": Color("8a7a5a"),
	"evaporator": Color("c0b070"), "saltery": Color("d0c090"),
	"dryer": Color("a89060"), "ropery": Color("94845a"),
	"sluice": Color("5a7a90"), "lantern": Color("e0c060"),
	"condenser": Color("70a0b0"), "winch": Color("808080"),
}

var building_id: int = -1

var _body: ColorRect = null
var _shade: ColorRect = null
var _edge: ColorRect = null
var _label: Label = null
var _bar: ColorRect = null
var _def: BuildingDef = null

func setup(id: int, def_id: String) -> void:
	building_id = id
	_def = DB.building(def_id)

func _ready() -> void:
	if _def == null:
		queue_free()
		return
	var px: Vector2 = Vector2(_def.size) * float(WorldGeo.TILE)
	_body = ColorRect.new()
	_body.size = px
	_body.color = COLORS.get(_def.special, Color("909090"))
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)
	# Нижняя треть темнее: объём без единого пикселя арта.
	_shade = ColorRect.new()
	_shade.size = Vector2(px.x, maxf(2.0, px.y / 3.0))
	_shade.position = Vector2(0.0, px.y - _shade.size.y)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)
	# Кромка сверху: свет всегда падает сверху, и это единственное, что
	# отличает «объект» от «заливки».
	_edge = ColorRect.new()
	_edge.size = Vector2(px.x, 2.0)
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_edge)
	_label = Label.new()
	_label.size = px
	_label.text = tr(_def.display_key).substr(0, 1).to_upper()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_bar = ColorRect.new()
	_bar.color = Color("7fd8a0")
	_bar.position = Vector2(0.0, px.y - 3.0)
	_bar.size = Vector2(0.0, 3.0)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)
	refresh()

func refresh() -> void:
	if Game.world == null or _def == null:
		return
	var b: Dictionary = Game.world.buildings.buildings.get(building_id, {})
	if b.is_empty():
		return
	var state: int = int(b["state"])
	var a: float = PLANNED_ALPHA if state == int(SimTypes.BuildState.PLANNED) else 1.0
	var tint: Color = COLORS.get(_def.special, Color("909090"))
	if bool(b["flooded"]):
		tint = tint.lerp(FLOOD_TINT, 0.5)
	_body.color = Color(tint.r, tint.g, tint.b, a)
	_shade.color = Color(tint.darkened(0.35).r, tint.darkened(0.35).g,
		tint.darkened(0.35).b, a)
	_edge.color = Color(tint.lightened(0.30).r, tint.lightened(0.30).g,
		tint.lightened(0.30).b, a)
	var px: Vector2 = Vector2(_def.size) * float(WorldGeo.TILE)
	var progress: float = Game.world.buildings.build_progress(b)
	var show_bar: bool = state == int(SimTypes.BuildState.UNDER_CONSTRUCTION) \
		or bool(b["damaged"])
	_bar.visible = show_bar
	_bar.size.x = px.x * progress

func _process(_delta: float) -> void:
	if Game.world == null:
		return
	var b: Dictionary = Game.world.buildings.buildings.get(building_id, {})
	if b.is_empty() or not bool(b["damaged"]):
		modulate.a = 1.0
		return
	# Мигание привязано к сим-времени, а не к TIME: на паузе замирает.
	modulate.a = 1.0 if fmod(Game.sim_seconds() * DAMAGED_BLINK_HZ, 1.0) < 0.5 else 0.45
