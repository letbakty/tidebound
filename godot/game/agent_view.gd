class_name AgentView
extends Node2D
## Спрайт агента: сетка 16×24 в assets/sprites/agent.png (сборщик —
## tools/gen_agent.gd). Ряд = состояние, столбец = кадр. Игровой логики здесь
## нет — только отображение.
##
## Кадр выбирается по СОСТОЯНИЮ и по сим-времени, а не по реальному: на паузе
## агент обязан замереть, а на ×3 — перебирать ногами втрое быстрее. Привязка
## к sim_seconds даёт и то и другое бесплатно.

const SHEET: String = "res://assets/sprites/agent.png"
## Лежащий агент повёрнут (24×16) и в клетку листа не влезает.
const DEAD_SPRITE: String = "res://assets/sprites/agent_dead.png"
const W: int = 16
const H: int = 24
const COLS: int = 8

## Ряды листа. Порядок — контракт с tools/gen_agent.gd (сторожит тест).
enum Row { IDLE, WALK, CARRY, WORK, DROWN, PANIC }

## Кадров в секунду симуляции. Ходьба — полный цикл из восьми кадров за секунду.
const WALK_FPS: float = 8.0
const WORK_FPS: float = 6.0
const PANIC_FPS: float = 8.0
const DROWN_FPS: float = 4.0
const BODY: Color = Color(1, 1, 1, 1)
const BODY_WET: Color = Color("8fb4c4")
const BODY_DEAD: Color = Color("5a5148")

## Иконки состояний: буква над головой там, где поза сама по себе не читается
## на 16 пикселях. У тонущего и паникующего своя анимация, но буква остаётся
## единственным, что видно на дальнем зуме.
const STATE_MARKS: Dictionary = {
	SimTypes.AgentState.DROWNING: "Z",
	SimTypes.AgentState.PANIC: "!",
	SimTypes.AgentState.REST: "z",
	SimTypes.AgentState.EAT: "*",
}

var agent_id: int = -1

var _body: Sprite2D = null
var _mark: Label = null
var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _t: float = 1.0
var _moving: bool = false

func setup(id: int) -> void:
	agent_id = id

func _ready() -> void:
	_body = Sprite2D.new()
	_body.texture = load(SHEET) as Texture2D
	_body.region_enabled = true
	_body.region_rect = Rect2(0.0, 0.0, float(W), float(H))
	# Спрайт «стоит» на клетке: якорь снизу по центру.
	_body.centered = false
	_body.position = Vector2(-float(W) * 0.5, -float(H))
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
		_body.modulate = BODY_DEAD
	elif bool(info.get("wet", false)):
		_body.modulate = BODY_WET
	else:
		_body.modulate = BODY
	_mark.text = str(STATE_MARKS.get(st, ""))
	var cell: Vector2i = cell_for(st, _moving, bool(info.get("carry", false)),
		Game.sim_seconds())
	_body.region_rect = Rect2(float(cell.x * W), float(cell.y * H),
		float(W), float(H))
	_body.position.y = -float(H)
	# Флип — только у спрайта; отрицательный scale на родителе ломает Y-sort
	# и переворачивает иконку состояния.
	var facing: int = int(info.get("facing", 1))
	_body.flip_h = facing < 0
	_body.position.x = -float(W) * 0.5

## Клетка листа: x — кадр, y — ряд. Чистая функция, её же проверяет тест.
static func cell_for(state: int, moving: bool, carrying: bool,
		sim_time: float) -> Vector2i:
	match state:
		SimTypes.AgentState.DROWNING:
			return Vector2i(_step(sim_time, DROWN_FPS), Row.DROWN)
		SimTypes.AgentState.PANIC:
			return Vector2i(_step(sim_time, PANIC_FPS), Row.PANIC)
		SimTypes.AgentState.WORK, SimTypes.AgentState.GATHER:
			return Vector2i(_step(sim_time, WORK_FPS), Row.WORK)
	# Несёт груз — это видно по позе, а не по значку: котомка у нас и есть
	# главный смысл ходьбы туда-обратно.
	var row: int = Row.CARRY if carrying else Row.WALK
	if not moving:
		# Стоящий с грузом остаётся в своём ряду: иначе груз мигал бы на
		# каждой остановке у склада.
		return Vector2i(0, row if carrying else Row.IDLE)
	return Vector2i(_step(sim_time, WALK_FPS), row)

static func _step(sim_time: float, fps: float) -> int:
	return int(sim_time * fps) % COLS

## Прямоугольник для хит-теста без физики (World.pick_at).
func hit_rect() -> Rect2:
	return Rect2(position - Vector2(float(W) * 0.5, float(H)), Vector2(float(W), float(H)))

func play_death_and_free(_cause: String) -> void:
	if _body != null:
		# Лежащее тело — отдельный файл: он шире клетки листа.
		var dead: Texture2D = load(DEAD_SPRITE) as Texture2D
		if dead != null:
			_body.texture = dead
			_body.region_enabled = false
			_body.flip_h = false
			_body.position = Vector2(-float(dead.get_width()) * 0.5,
				-float(dead.get_height()))
		_body.modulate = BODY_DEAD
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.8)
	tw.tween_callback(queue_free)
