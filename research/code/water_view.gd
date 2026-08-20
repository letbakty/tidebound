## Вода: экранный ColorRect с шейдером рефракции.
##
## Нода лежит на CanvasLayer ВНУТРИ WorldViewport (не в мировом пространстве),
## растянута на весь вьюпорт 640×360 и не двигается. Позиция кромки передаётся
## в шейдер числом — так прямоугольник не ползает субпиксельно при панораме
## камеры, а screen_tex остаётся в нативном разрешении мира.
##
## Заменяет заглушку этапа 02 (там ColorRect в мировом пространстве).
## Публичный контракт с этапом 02 сохраняется: подписка на Events.water_level_changed.
class_name WaterView
extends ColorRect

# Геометрия мира — держать синхронно с sim/balance.gd и game/world.gd.
const TOP_MARK: float = 6.0
const PX_PER_MARK: float = 96.0    # 3 тайла × 32 px = один ярус

# Скорость подтягивания визуального уровня к симуляционному.
# Events.water_level_changed приходит раз в 3 тика (docs/02 §3.2) — без лерпа
# кромка двигалась бы ступеньками по 3.3 px на подъёме «стеной» в HIGH.
const LEVEL_LERP: float = 18.0

@export var storm_fade_seconds: float = 2.0

var _level_target: float = 0.0
var _level_shown: float = 0.0
var _storm_target: float = 0.0
var _storm_shown: float = 0.0
var _mat: ShaderMaterial = null

func _ready() -> void:
	_mat = material as ShaderMaterial
	if _mat == null:
		push_error("WaterView: ожидается ShaderMaterial с water.gdshader")
		set_process(false)
		return
	_mat.set_shader_parameter(&"u_view_size", Vector2(get_viewport_rect().size))
	Events.water_level_changed.connect(_on_water_level_changed)
	Events.crisis_started.connect(_on_crisis_started)
	Events.crisis_ended.connect(_on_crisis_ended)

func _process(delta: float) -> void:
	_level_shown = lerpf(_level_shown, _level_target, minf(1.0, LEVEL_LERP * delta))
	_storm_shown = move_toward(_storm_shown, _storm_target, delta / storm_fade_seconds)

	var world_y: float = (TOP_MARK - _level_shown) * PX_PER_MARK
	var canvas: Transform2D = get_viewport().get_canvas_transform()
	var screen_y: float = (canvas * Vector2(0.0, world_y)).y

	_mat.set_shader_parameter(&"u_surface_y", floorf(screen_y))
	_mat.set_shader_parameter(&"u_storm", _storm_shown)

## Экранный Y кромки — нужен брызгам и отражениям, чтобы не считать заново.
func surface_screen_y() -> float:
	var world_y: float = (TOP_MARK - _level_shown) * PX_PER_MARK
	return floorf((get_viewport().get_canvas_transform() * Vector2(0.0, world_y)).y)

func _on_water_level_changed(level: float) -> void:
	_level_target = level

func _on_crisis_started(type: int) -> void:
	if type == SimTypes.CrisisType.STORM:
		_storm_target = 1.0

func _on_crisis_ended(type: int) -> void:
	if type == SimTypes.CrisisType.STORM:
		_storm_target = 0.0
