class_name CreatureView
extends Node2D
## Существо Прихода: тёмный силуэт с горбом и красными глазами
## (assets/sprites/creature.png, генератор tools/gen_sprites.gd).

const W: int = 32
const H: int = 24
const SPRITE: String = "res://assets/sprites/creature.png"
const BODY: Color = Color(1, 1, 1, 0.92)
const EYE: Color = Color("e04a3a")
const EYE_PULSE_HZ: float = 1.5

var creature_id: int = -1

var _body: Sprite2D = null
var _eyes: ColorRect = null
var _to: Vector2 = Vector2.ZERO
var _from: Vector2 = Vector2.ZERO
var _t: float = 1.0

func setup(id: int) -> void:
	creature_id = id

func _ready() -> void:
	z_index = 50
	_body = Sprite2D.new()
	_body.texture = load(SPRITE) as Texture2D
	_body.centered = false
	_body.position = Vector2(-float(W) * 0.5, -float(H))
	_body.modulate = BODY
	add_child(_body)
	_eyes = ColorRect.new()
	_eyes.size = Vector2(float(W) * 0.5, 2.0)
	_eyes.position = Vector2(-float(W) * 0.25, -float(H) + 6.0)
	_eyes.color = EYE
	_eyes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_eyes)
	position = Game.query_creature_pos(creature_id).round()
	_from = position
	_to = position

func _process(delta: float) -> void:
	var target: Vector2 = Game.query_creature_pos(creature_id)
	if target != _to:
		_from = position
		_to = target
		_t = 0.0
	# На паузе не доезжаем — как и агенты.
	if Game.speed > 0 and _t < 1.0:
		_t = minf(_t + delta * float(Balance.TICKS_PER_SEC) * float(Game.speed), 1.0)
		position = _from.lerp(_to, _t).round()
	# Пульсация глаз по сим-времени: на паузе замирает.
	_eyes.modulate.a = 0.55 + 0.45 * absf(sin(Game.sim_seconds() * EYE_PULSE_HZ * PI))
