class_name WaterView
extends ColorRect
## Вода: экранный прямоугольник с шейдером на CanvasLayer ВНУТРИ мирового
## SubViewport (research/01 §3).
##
## Нода растянута на весь вьюпорт и НЕ двигается: двигающийся прямоугольник
## даёт субпиксельный джиттер относительно мира при панораме (research/06 §4).
## Позиция кромки передаётся ЧИСЛОМ в uniform u_surface_y, уже округлённым
## здесь — шейдер её не пересчитывает. Всё, что выше кромки, шейдер вырезает
## сам, поэтому прямоугольник может стоять на месте.
##
## ⚠️ ОТКЛОНЕНИЕ от промпта 02 и research/12 §7: у слоя воды
## follow_viewport_enabled = FALSE, а не true. С true слой берёт трансформ
## камеры, Full Rect растягивается в МИРОВЫХ координатах, и экранный Y кромки
## считается уже в другой системе координат — вода уезжала в верх экрана.
##
## РЕШЕНИЕ (этап 18): числа воды — визуальные, не игровые, поэтому живут в
## assets/shaders/water_material.tres и tools/gen_materials.gd, а не в Balance.
## Их правит художник в инспекторе, а не геймдизайнер в балансе.

## Events.water_level_changed приходит раз в 3 тика — без сглаживания кромка
## двигалась бы ступеньками по 9 px на подъёме «стеной» в фазе HIGH.
const LEVEL_LERP: float = 18.0
## Секунды на разгон и затухание штормовой волны.
const STORM_FADE_SEC: float = 3.0

var _level_target: float = Balance.HIGH_LEVEL
var _level_shown: float = Balance.HIGH_LEVEL
var _storm_target: float = 0.0
var _storm_shown: float = 0.0
var _mat: ShaderMaterial = null
var _last_surface_y: float = INF
## Отметка, до которой брызги уже отыграли: всплеск даётся на ярус, а не на
## каждый кадр подъёма.
var _splashed_mark: int = 99

func _ready() -> void:
	color = Color(0, 0, 0, 0)          # цвет рисует шейдер, сам прямоугольник пуст
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = material as ShaderMaterial
	if _mat == null:
		push_error("WaterView: ожидается ShaderMaterial с water.gdshader")
	else:
		_mat.set_shader_parameter(&"u_view_size", Vector2(get_viewport_rect().size))
	Events.water_level_changed.connect(_on_water_level_changed)
	Events.crisis_started.connect(_on_crisis_started)
	Events.crisis_ended.connect(_on_crisis_ended)
	Events.run_started.connect(_on_run_started)

func _process(delta: float) -> void:
	_level_shown = lerpf(_level_shown, _level_target, minf(1.0, LEVEL_LERP * delta))
	_storm_shown = move_toward(_storm_shown, _storm_target, delta / STORM_FADE_SEC)
	if _mat == null:
		return
	var y: float = surface_screen_y()
	if not is_equal_approx(y, _last_surface_y):
		_last_surface_y = y
		_mat.set_shader_parameter(&"u_surface_y", y)
	_mat.set_shader_parameter(&"u_storm", _storm_shown)
	_check_splash()

## Экранный Y кромки. Нужен брызгам и отражениям — чтобы никто не считал
## его заново.
func surface_screen_y() -> float:
	return floorf(WorldGeo.water_screen_y(_level_shown, get_viewport()))

## Уровень, который сейчас РИСУЕТСЯ (он отстаёт от симуляционного на лерп).
func shown_level() -> float:
	return _level_shown

## Брызги в момент прихода воды на ярус (промпт 18 п.6). Считаем по целым
## отметкам: между ярусами всплеску взяться неоткуда.
func _check_splash() -> void:
	var mark: int = floori(_level_shown)
	if mark <= _splashed_mark:
		_splashed_mark = mini(_splashed_mark, mark)
		return
	_splashed_mark = mark
	var fx: WeatherView = _weather()
	if fx == null:
		return
	# Брызги — по центру экрана на линии кромки: точка «где именно» игроку
	# не важна, а честный перебор построек стоил бы дороже эффекта.
	var vp: Vector2 = get_viewport_rect().size
	fx.splash_at(get_viewport().get_canvas_transform().affine_inverse()
		* Vector2(vp.x * 0.5, surface_screen_y()))

func _weather() -> WeatherView:
	var root: Node = get_tree().current_scene
	if root == null:
		return null
	return root.get_node_or_null(^"WeatherView") as WeatherView

func _on_water_level_changed(level: float) -> void:
	_level_target = level

func _on_run_started(_seed_value: int) -> void:
	_level_target = Balance.HIGH_LEVEL
	_level_shown = Balance.HIGH_LEVEL
	_splashed_mark = 99
	_storm_target = 0.0
	_storm_shown = 0.0

func _on_crisis_started(type: int) -> void:
	if type == SimTypes.CrisisType.STORM:
		_storm_target = 1.0

func _on_crisis_ended(type: int) -> void:
	if type == SimTypes.CrisisType.STORM:
		_storm_target = 0.0
