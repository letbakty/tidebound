class_name LightBudget
extends Node2D
## Бюджет 2D-света: жёсткий лимит Balance.MAX_LIGHTS на экран (docs/00 §16,
## промпт 18 п.2 — «спавн 12 фонарей не роняет fps, дальние гаснут»).
##
## Постройки со светом (фонарь, горн, очаг) не создают PointLight2D сами, а
## просят его здесь: один реестр — один способ соблюсти лимит.
##
## ЗАЧЕМ ГАСИТЬ, А НЕ УДАЛЯТЬ: `enabled = false` снимает свет с прохода
## освещения целиком, а free/instantiate стоит аллокаций и RID-трафика
## (research/02 §2). Нода остаётся в дереве и в реестре.

## Пересчёт четыре раза в секунду: камера в колони-симе движется медленно,
## а сортировка на каждом кадре — работа на ровном месте.
const RECHECK_SEC: float = 0.25
const GLOW_TEXTURE: String = "res://assets/shaders/light_glow.tres"

## Цвет и сила света по типу источника. Тёплый свет против холодного низа —
## главный приём «дорогой» картинки (research/02).
##
## ⚠️ Сила света пересобрана вместе с настоящим артом. Прежние числа (1.15 /
## 1.30 / 1.00) подбирались, когда шейдер Ground возводил цвет тайла в КВАДРАТ
## и порода была на 40% темнее. На починенной базе сложение выжигало охряный
## камень в белое пятно: очага не видно, видно засветку (backlog «Пересъём
## атмосферы»).
const KINDS: Dictionary = {
	"hearth": {"color": Color("ffb14a"), "energy": 0.70, "scale": 2.2},
	"forge": {"color": Color("ff8a3a"), "energy": 0.80, "scale": 1.8},
	"lantern": {"color": Color("ffd27a"), "energy": 0.60, "scale": 1.6},
}

var _lights: Array[PointLight2D] = []
var _accum: float = 0.0
var _camera: Camera2D = null
var _glow: Texture2D = null

func _ready() -> void:
	_glow = load(GLOW_TEXTURE) as Texture2D
	if _glow == null:
		push_warning("LightBudget: нет текстуры света %s" % GLOW_TEXTURE)

## Заводит свет заданного типа в точке мира. Возвращает ноду: гасить и
## двигать её можно, но лимитом распоряжается бюджет.
func add_light(kind: String, pos: Vector2) -> PointLight2D:
	var cfg: Dictionary = KINDS.get(kind, KINDS["lantern"]) as Dictionary
	var l: PointLight2D = PointLight2D.new()
	l.name = "Light_" + kind
	l.texture = _glow
	l.color = cfg["color"] as Color
	l.energy = float(cfg["energy"])
	l.texture_scale = float(cfg["scale"])
	l.blend_mode = Light2D.BLEND_MODE_ADD
	# Тени в пиксель-арте выключены: PCF мылит и стоит отдельного прохода
	# (research/02 §2). Это главный ползунок качества, если он понадобится.
	l.shadow_enabled = false
	l.position = pos
	add_child(l)
	_lights.append(l)
	_accum = RECHECK_SEC              # пересчитать на ближайшем кадре
	return l

func remove_light(l: PointLight2D) -> void:
	_lights.erase(l)
	if is_instance_valid(l):
		l.queue_free()

func clear() -> void:
	for l: PointLight2D in _lights:
		if is_instance_valid(l):
			l.queue_free()
	_lights.clear()

## Сколько светов сейчас горит — для дебаг-панели и теста приёмки.
func lit_count() -> int:
	var n: int = 0
	for l: PointLight2D in _lights:
		if is_instance_valid(l) and l.enabled:
			n += 1
	return n

func total_count() -> int:
	return _lights.size()

func _process(delta: float) -> void:
	_accum += delta
	if _accum < RECHECK_SEC:
		return
	_accum = 0.0
	_rebalance()

func _rebalance() -> void:
	var alive: Array[PointLight2D] = []
	for l: PointLight2D in _lights:
		if is_instance_valid(l):
			alive.append(l)
	_lights = alive
	if _lights.size() <= Balance.MAX_LIGHTS:
		for l: PointLight2D in _lights:
			l.enabled = true
		return
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_2d()
		if _camera == null:
			return
	var center: Vector2 = _camera.get_screen_center_position()
	var order: Array[PointLight2D] = _lights.duplicate()
	# Тай-брейк по имени узла: при равном расстоянии порядок иначе не определён,
	# и два соседних фонаря начинают мигать по очереди на каждом пересчёте.
	order.sort_custom(func(a: PointLight2D, b: PointLight2D) -> bool:
		var da: float = a.global_position.distance_squared_to(center)
		var db: float = b.global_position.distance_squared_to(center)
		if is_equal_approx(da, db):
			return a.get_instance_id() < b.get_instance_id()
		return da < db)
	for i: int in order.size():
		order[i].enabled = i < Balance.MAX_LIGHTS

## Сколько светов останется гореть при данном их числе — чистая функция для
## теста приёмки «спавн 12 фонарей гасит дальние».
static func lit_for(total: int) -> int:
	return mini(maxi(total, 0), Balance.MAX_LIGHTS)
