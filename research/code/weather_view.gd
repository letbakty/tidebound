## Погода и атмосфера: дождь, виньетка, молния, глубинный туман, брызги.
##
## Куда класть: game/weather_view.gd, нода в Main (не в мире — она дирижирует
## объектами в обоих местах). Ссылки на ноды — через @export, без $"/root/...".
##
## Ноды, которыми она управляет:
##   WorldViewport/RainLayer/Rain      (ColorRect, rain.gdshader)      — внутри мира
##   WorldViewport/FogLayer/DepthFog   (ColorRect, depth_fog.gdshader) — внутри мира
##   WeatherLayer/Vignette             (ColorRect, vignette.gdshader)  — снаружи, натив
##   WorldViewport/Fx/SplashPool       (пул GPUParticles2D)
class_name WeatherView
extends Node

const TOP_MARK: float = 6.0
const BOTTOM_MARK: float = -8.0
const PX_PER_MARK: float = 96.0

const STORM_FADE: float = 3.0        # секунды на разгон/затухание шторма
const FLASH_MIN_GAP: float = 6.0     # секунды между молниями
const FLASH_MAX_GAP: float = 18.0

@export var rain: ColorRect
@export var fog: ColorRect
@export var vignette: ColorRect
@export var splash_pool: Node2D
@export var world_viewport: SubViewport

var _storm_target: float = 0.0
var _storm_shown: float = 0.0
var _flash_timer: float = 0.0
var _rng := RandomNumberGenerator.new()   # ВИЗУАЛ, не sim — SimRNG здесь не нужен

func _ready() -> void:
	_rng.randomize()
	Events.crisis_started.connect(_on_crisis_started)
	Events.crisis_ended.connect(_on_crisis_ended)
	Events.speed_changed.connect(_on_speed_changed)
	_flash_timer = _rng.randf_range(FLASH_MIN_GAP, FLASH_MAX_GAP)
	get_window().size_changed.connect(_update_aspect)
	_update_aspect()

func _process(delta: float) -> void:
	_storm_shown = move_toward(_storm_shown, _storm_target, delta / STORM_FADE)
	_set_param(rain, &"u_intensity", _storm_shown)
	_set_param(vignette, &"u_intensity", _storm_shown)
	_update_fog_bounds()
	_update_lightning(delta)

# --- туман -------------------------------------------------------------------

## Туман привязан к МИРУ, а не к экрану: границы пересчитываются из
## canvas_transform каждый кадр, иначе градиент «плывёт» при панораме камеры.
func _update_fog_bounds() -> void:
	if fog == null or world_viewport == null:
		return
	var canvas: Transform2D = world_viewport.get_canvas_transform()
	var top_y: float = (canvas * Vector2(0.0, (TOP_MARK - TOP_MARK) * PX_PER_MARK)).y
	var bottom_y: float = (canvas * Vector2(0.0, (TOP_MARK - BOTTOM_MARK) * PX_PER_MARK)).y
	_set_param(fog, &"u_top_y", top_y)
	_set_param(fog, &"u_bottom_y", bottom_y)

# --- молния ------------------------------------------------------------------

func _update_lightning(delta: float) -> void:
	if _storm_shown < 0.5:
		return
	_flash_timer -= delta
	if _flash_timer > 0.0:
		return
	_flash_timer = _rng.randf_range(FLASH_MIN_GAP, FLASH_MAX_GAP)
	_fire_flash()

func _fire_flash() -> void:
	if vignette == null:
		return
	var mat: ShaderMaterial = vignette.material as ShaderMaterial
	var tw: Tween = create_tween()
	tw.tween_method(func(v: float) -> void:
		mat.set_shader_parameter(&"u_flash", v), 0.0, 0.75, 0.05)
	tw.tween_method(func(v: float) -> void:
		mat.set_shader_parameter(&"u_flash", v), 0.75, 0.0, 0.22)

# --- частицы и пауза ---------------------------------------------------------

## ВАЖНО: speed_scale = 0 на GPUParticles2D НЕ останавливает симуляцию надёжно
## (godot issue #77916, открыт). Надёжный способ — process_mode = DISABLED.
## На скоростях ×2/×3 частицы ускоряем через speed_scale — там артефактов нет.
func _on_speed_changed(mult: int) -> void:
	var mode: Node.ProcessMode = Node.PROCESS_MODE_DISABLED if mult == 0 \
		else Node.PROCESS_MODE_INHERIT
	for n: Node in get_tree().get_nodes_in_group(&"fx"):
		n.process_mode = mode
		if mult > 0 and n is GPUParticles2D:
			(n as GPUParticles2D).speed_scale = float(mult)

# --- брызги прихода воды -----------------------------------------------------

## Вызывается из WaterView, когда кромка пересекла отметку яруса на подъёме.
## Пул эмиттеров: создавать GPUParticles2D на лету дорого, держим 4 штуки.
func splash_at(world_pos: Vector2) -> void:
	if splash_pool == null:
		return
	for child: Node in splash_pool.get_children():
		var p: GPUParticles2D = child as GPUParticles2D
		if p != null and not p.emitting:
			p.global_position = world_pos
			p.restart()
			p.emitting = true
			return
	# все заняты — пропускаем кадр, лишний эмиттер не создаём

# --- служебное ---------------------------------------------------------------

func _on_crisis_started(type: int) -> void:
	if type == SimTypes.CrisisType.STORM:
		_storm_target = 1.0

func _on_crisis_ended(type: int) -> void:
	if type == SimTypes.CrisisType.STORM:
		_storm_target = 0.0

func _update_aspect() -> void:
	var s: Vector2i = get_window().size
	_set_param(vignette, &"u_aspect", float(s.x) / maxf(1.0, float(s.y)))

func _set_param(rect: ColorRect, name: StringName, value: Variant) -> void:
	if rect == null:
		return
	var mat: ShaderMaterial = rect.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter(name, value)
