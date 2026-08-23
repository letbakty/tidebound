class_name CreatureView
extends Node2D
## Существо Прихода: тёмный силуэт, лист 32×24 в assets/sprites/creature.png
## (сборщик — tools/gen_creature.gd). Ряд = состояние, столбец = кадр.
##
## Состояние собирается ЗДЕСЬ из того, что и так доступно виду: грызёт ли оно
## (срез из Game) и накрыла ли его вода (уровень приходит событием, как и
## водной кромке). Новых знаний в sim это не требует.

const SHEET: String = "res://assets/sprites/creature.png"
const W: int = 32
const H: int = 24
const COLS: int = 8

## Ряды листа. Порядок — контракт с tools/gen_creature.gd (сторожит тест).
enum Row { IDLE, MOVE, GNAW, SWIM }

const MOVE_FPS: float = 6.0
const GNAW_FPS: float = 8.0
const SWIM_FPS: float = 5.0
const BODY: Color = Color(1, 1, 1, 0.92)

var creature_id: int = -1

var _body: Sprite2D = null
var _to: Vector2 = Vector2.ZERO
var _from: Vector2 = Vector2.ZERO
var _t: float = 1.0
var _moving: bool = false
## Мировой Y поверхности воды. 99999 — воды нет нигде.
var _water_y: float = 99999.0

func setup(id: int) -> void:
	creature_id = id

func _ready() -> void:
	z_index = 50
	_body = Sprite2D.new()
	_body.texture = load(SHEET) as Texture2D
	_body.region_enabled = true
	_body.region_rect = Rect2(0.0, 0.0, float(W), float(H))
	_body.centered = false
	_body.position = Vector2(-float(W) * 0.5, -float(H))
	_body.modulate = BODY
	add_child(_body)
	Events.water_level_changed.connect(_on_water_level_changed)
	position = Game.query_creature_pos(creature_id).round()
	_from = position
	_to = position

func _on_water_level_changed(level: float) -> void:
	_water_y = WorldGeo.mark_to_world_y(level)

func _process(delta: float) -> void:
	var target: Vector2 = Game.query_creature_pos(creature_id)
	if target != _to:
		_from = position
		_to = target
		_t = 0.0
		_moving = true
	# На паузе не доезжаем — как и агенты.
	if Game.speed > 0 and _t < 1.0:
		_t = minf(_t + delta * float(Balance.TICKS_PER_SEC) * float(Game.speed), 1.0)
		position = _from.lerp(_to, _t).round()
	elif _t >= 1.0:
		_moving = false
	# Смотрит туда, куда идёт: у существа нет facing в симуляции, и брать его
	# больше неоткуда.
	if _to.x < _from.x:
		_body.flip_h = true
	elif _to.x > _from.x:
		_body.flip_h = false
	var info: Dictionary = Game.query_creature_look(creature_id)
	var cell: Vector2i = cell_for(bool(info.get("gnaw", false)),
		position.y > _water_y, _moving, Game.sim_seconds())
	_body.region_rect = Rect2(float(cell.x * W), float(cell.y * H),
		float(W), float(H))

## Клетка листа: x — кадр, y — ряд. Чистая функция, её же проверяет тест.
static func cell_for(gnawing: bool, submerged: bool, moving: bool,
		sim_time: float) -> Vector2i:
	if gnawing:
		return Vector2i(int(sim_time * GNAW_FPS) % COLS, Row.GNAW)
	if submerged:
		return Vector2i(int(sim_time * SWIM_FPS) % COLS, Row.SWIM)
	if not moving:
		return Vector2i(0, Row.IDLE)
	return Vector2i(int(sim_time * MOVE_FPS) % COLS, Row.MOVE)
