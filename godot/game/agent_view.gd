class_name AgentView
extends Node2D
## Спрайт агента. Заглушка до этапа 18: прямоугольник 16×24 с иконкой
## состояния над головой. Игровой логики здесь нет — только отображение.

const W: int = 16
const H: int = 24
const BODY: Color = Color("d8c8a8")
const BODY_WET: Color = Color("8fb4c4")
const BODY_DEAD: Color = Color("5a5148")

## Иконки состояний: буква над головой вместо арта.
const STATE_MARKS: Dictionary = {
	SimTypes.AgentState.DROWNING: "Z",
	SimTypes.AgentState.PANIC: "!",
	SimTypes.AgentState.REST: "z",
	SimTypes.AgentState.EAT: "*",
}

var agent_id: int = -1

var _body: ColorRect = null
var _mark: Label = null
var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _t: float = 1.0
var _moving: bool = false

func setup(id: int) -> void:
	agent_id = id

func _ready() -> void:
	_body = ColorRect.new()
	_body.size = Vector2(float(W), float(H))
	# Спрайт «стоит» на клетке: якорь снизу по центру.
	_body.position = Vector2(-float(W) * 0.5, -float(H))
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)
	_mark = Label.new()
	_mark.position = Vector2(-float(W) * 0.5, -float(H) - 16.0)
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mark)
	_snap_to_sim()

## Позиция тянется раз в кадр, а не приходит событием.
## РЕШЕНИЕ (research/15 §6.3): agent_updated троттлится до 1 Гц — этого хватает
## смене СОСТОЯНИЯ, но не движению: агент телепортировался бы раз в секунду.
## Позиция — тот же разрешённый синхронный «pull» через Game, что и
## Game.query_agent для карточки агента.
func _process(delta: float) -> void:
	var target: Vector2 = Game.query_agent_pos(agent_id)
	if target != _to:
		_from = position
		_to = target
		_t = 0.0
		_moving = true
	# На паузе не доезжаем: иначе она читается как подтормаживание, а не
	# как остановка.
	if Game.speed > 0 and _t < 1.0:
		_t = minf(_t + delta * float(Balance.TICKS_PER_SEC) * float(Game.speed), 1.0)
		position = _from.lerp(_to, _t).round()
	elif _t >= 1.0:
		_moving = false
	_refresh_look()

func _snap_to_sim() -> void:
	position = Game.query_agent_pos(agent_id).round()
	_from = position
	_to = position
	_t = 1.0

func _refresh_look() -> void:
	# Лёгкий срез: полный query_agent с копией котомки каждый кадр — впустую
	# (review/04 PERF-01).
	var info: Dictionary = Game.query_agent_look(agent_id)
	if info.is_empty():
		return
	var st: int = int(info.get("state", 0))
	if st == int(SimTypes.AgentState.DEAD):
		_body.color = BODY_DEAD
	elif bool(info.get("wet", false)):
		_body.color = BODY_WET
	else:
		_body.color = BODY
	_mark.text = str(STATE_MARKS.get(st, ""))
	# Покачивание при ходьбе: сдвиг на ЦЕЛЫЙ пиксель, а не синус — дробное
	# смещение в пиксель-арте даёт мыло.
	var bob: float = 0.0
	if _moving:
		bob = -1.0 if fmod(Game.sim_seconds() * 6.0, 2.0) < 1.0 else 0.0
	_body.position.y = -float(H) + bob
	# Флип — только у спрайта; отрицательный scale на родителе ломает Y-sort
	# и переворачивает иконку состояния.
	var facing: int = int(info.get("facing", 1))
	_body.position.x = -float(W) * 0.5 + (1.0 if facing < 0 else 0.0)

## Прямоугольник для хит-теста без физики (World.pick_at).
func hit_rect() -> Rect2:
	return Rect2(position - Vector2(float(W) * 0.5, float(H)), Vector2(float(W), float(H)))

func play_death_and_free(_cause: String) -> void:
	if _body != null:
		_body.color = BODY_DEAD
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.8)
	tw.tween_callback(queue_free)
