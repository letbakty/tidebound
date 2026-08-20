## Бюджет 2D-света: жёсткий лимит Balance.MAX_LIGHTS на экран (docs/00 §16,
## промпт 18 п.2 — «спавн 12 фонарей не роняет fps, дальние гаснут»).
##
## Куда класть: game/light_budget.gd, нода-ребёнок World.
## Постройки со светом (фонарь, горн, очаг) при появлении регистрируются здесь,
## а не создают PointLight2D сами.
##
## ЗАЧЕМ ИМЕННО ТАК: невидимый Light2D всё равно проходит через culling движка,
## но не занимает слот в проходе освещения. `enabled = false` (свойство Light2D)
## снимает свет с рендера полностью и дешевле, чем free/instantiate — поэтому
## светильники не удаляются, а гасятся.
class_name LightBudget
extends Node2D

const MAX_LIGHTS: int = 8          # = Balance.MAX_LIGHTS, держать синхронно
const RECHECK_INTERVAL: float = 0.25  # пересчёт 4 раза в секунду достаточно

var _lights: Array[PointLight2D] = []
var _accum: float = 0.0
var _camera: Camera2D = null

func _ready() -> void:
	_camera = get_viewport().get_camera_2d()

func register(light: PointLight2D) -> void:
	if not _lights.has(light):
		_lights.append(light)
		_accum = RECHECK_INTERVAL  # пересчитать на ближайшем кадре

func unregister(light: PointLight2D) -> void:
	_lights.erase(light)

func _process(delta: float) -> void:
	_accum += delta
	if _accum < RECHECK_INTERVAL:
		return
	_accum = 0.0
	_rebalance()

func _rebalance() -> void:
	if _camera == null:
		_camera = get_viewport().get_camera_2d()
		if _camera == null:
			return

	# Чистим освободившиеся ссылки (постройка снесена/затоплена)
	var alive: Array[PointLight2D] = []
	for l: PointLight2D in _lights:
		if is_instance_valid(l):
			alive.append(l)
	_lights = alive

	if _lights.size() <= MAX_LIGHTS:
		for l: PointLight2D in _lights:
			l.enabled = true
		return

	var center: Vector2 = _camera.get_screen_center_position()
	# Сортировка по расстоянию до центра камеры: ближние горят, дальние гаснут.
	_lights.sort_custom(func(a: PointLight2D, b: PointLight2D) -> bool:
		return a.global_position.distance_squared_to(center) \
			 < b.global_position.distance_squared_to(center))

	for i: int in range(_lights.size()):
		_lights[i].enabled = i < MAX_LIGHTS


## Фабрика тёплого точечного света в стиле проекта.
## texture — мягкий белый радиальный градиент (GradientTexture2D, FILL_RADIAL),
## одна текстура на все светильники: меньше смен состояния.
static func make_light(tex: Texture2D, color: Color, energy: float, scale: float) -> PointLight2D:
	var l: PointLight2D = PointLight2D.new()
	l.texture = tex
	l.color = color
	l.energy = energy
	l.texture_scale = scale
	l.blend_mode = Light2D.BLEND_MODE_ADD
	l.shadow_enabled = false          # тени в пиксель-арте выключены (доки: filter None/off)
	l.range_z_min = -1024
	l.range_z_max = 1024
	return l
