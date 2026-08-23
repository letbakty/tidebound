class_name WeatherView
extends Node
## Погода и атмосфера: дождь, виньетка, молния, глубинный туман, брызги, пар.
##
## Дирижёр, а не рисовалка: сами эффекты живут в двух местах — внутри мирового
## вьюпорта (дождь, туман, частицы) и снаружи, в нативном разрешении окна
## (виньетка). Одна нода держит их синхронно по одному числу «сила шторма».
##
## Виньетка снаружи намеренно (research/04): это эффект объектива, а не часть
## пиксельного мира; внутри 640×360 её градиент даёт грубый бандинг.

## Секунды на разгон и затухание шторма. Совпадает с водой: кромка и небо
## должны меняться вместе, иначе шторм читается как два разных события.
const STORM_FADE_SEC: float = 3.0
const FLASH_MIN_GAP: float = 6.0
const FLASH_MAX_GAP: float = 18.0
## Пул брызг: создавать GPUParticles2D на лету дорого, четырёх хватает —
## всплески идут раз в ярус, а не пачками.
const SPLASH_POOL: int = 4
const SPLASH_AMOUNT: int = 24
const STEAM_AMOUNT: int = 12
## Группа всех эмиттеров: по ней раздаётся пауза и скорость.
const FX_GROUP: StringName = &"fx"

var rain: ColorRect = null
var fog: ColorRect = null
var vignette: ColorRect = null
var fx_root: Node2D = null
var world_viewport: SubViewport = null

var _storm_target: float = 0.0
var _storm_shown: float = 0.0
var _flash_timer: float = 0.0
var _splashes: Array[GPUParticles2D] = []
var _steam: Dictionary[int, GPUParticles2D] = {}
## ВИЗУАЛ, а не sim: молнии не влияют на игру, SimRNG здесь не нужен и вреден —
## забег не должен зависеть от того, сколько кадров нарисовалось.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Ноды передаёт Main: искать их через $"/root/..." — прямой путь к падению
## при смене дерева.
func setup(rain_rect: ColorRect, fog_rect: ColorRect, vignette_rect: ColorRect,
		fx: Node2D, viewport: SubViewport) -> void:
	rain = rain_rect
	fog = fog_rect
	vignette = vignette_rect
	fx_root = fx
	world_viewport = viewport
	_build_splash_pool()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 20260818
	_flash_timer = _rng.randf_range(FLASH_MIN_GAP, FLASH_MAX_GAP)
	Events.crisis_started.connect(_on_crisis_started)
	Events.crisis_ended.connect(_on_crisis_ended)
	Events.speed_changed.connect(_on_speed_changed)
	Events.run_started.connect(_on_run_started)
	Events.building_placed.connect(_on_building_placed)
	Events.building_removed.connect(_on_building_removed)
	var win: Window = get_window()
	if win != null:
		win.size_changed.connect(_update_aspect)
		_update_aspect()

func _process(delta: float) -> void:
	_storm_shown = move_toward(_storm_shown, _storm_target, delta / STORM_FADE_SEC)
	_set_param(rain, &"u_intensity", _storm_shown)
	_set_param(vignette, &"u_intensity", _storm_shown)
	_update_fog_bounds()
	_update_lightning(delta)

## Сила шторма 0..1 — для дебаг-панели.
func storm_amount() -> float:
	return _storm_shown

# --- Туман ----------------------------------------------------------------

## Туман привязан к МИРУ, а не к экрану: границы пересчитываются из
## canvas_transform каждый кадр, иначе градиент «плывёт» при панораме камеры
## и это сразу читается как дефект.
func _update_fog_bounds() -> void:
	if fog == null or world_viewport == null:
		return
	var canvas: Transform2D = world_viewport.get_canvas_transform()
	var top_y: float = (canvas * Vector2(0.0, WorldGeo.mark_to_world_y(
		float(Balance.TOP_MARK)))).y
	var bottom_y: float = (canvas * Vector2(0.0, WorldGeo.mark_to_world_y(
		float(Balance.BOTTOM_MARK)))).y
	_set_param(fog, &"u_top_y", top_y)
	_set_param(fog, &"u_bottom_y", bottom_y)

# --- Молния ---------------------------------------------------------------

func _update_lightning(delta: float) -> void:
	if _storm_shown < 0.5:
		return
	_flash_timer -= delta
	if _flash_timer > 0.0:
		return
	_flash_timer = _rng.randf_range(FLASH_MIN_GAP, FLASH_MAX_GAP)
	flash()

## Вспышка молнии. Отдельным методом: её же зовёт дебаг-панель и режим съёмки.
func flash() -> void:
	if vignette == null:
		return
	var mat: ShaderMaterial = vignette.material as ShaderMaterial
	if mat == null:
		return
	# Резкий фронт и медленный спад: наоборот выглядит как включение лампы.
	var tw: Tween = create_tween()
	tw.tween_method(func(v: float) -> void:
		mat.set_shader_parameter(&"u_flash", v), 0.0, 0.75, 0.05)
	tw.tween_method(func(v: float) -> void:
		mat.set_shader_parameter(&"u_flash", v), 0.75, 0.0, 0.22)

# --- Частицы --------------------------------------------------------------

func _build_splash_pool() -> void:
	if fx_root == null:
		return
	for i: int in SPLASH_POOL:
		var p: GPUParticles2D = _make_particles("Splash%d" % i, SPLASH_AMOUNT, true)
		_splashes.append(p)

## Брызги в точке мира. Зовёт WaterView, когда кромка перешла ярус.
func splash_at(world_pos: Vector2) -> void:
	for p: GPUParticles2D in _splashes:
		if p.emitting:
			continue
		p.position = world_pos
		p.restart()
		p.emitting = true
		return
	# Все четыре заняты — кадр пропускаем. Пятый эмиттер эффекта не добавит.

## Пар от горна и очага: непрерывный эмиттер на постройку.
func _on_building_placed(id: int) -> void:
	if fx_root == null or _steam.has(id):
		return
	var b: Dictionary = Game.query_building(id)
	if b.is_empty() or not ["forge", "hearth"].has(str(b.get("def_id", ""))):
		return
	var p: GPUParticles2D = _make_particles("Steam%d" % id, STEAM_AMOUNT, false)
	p.position = WorldGeo.cell_center_world(b["cell"] as Vector2i)
	p.emitting = true
	_steam[id] = p

func _on_building_removed(id: int) -> void:
	var p: GPUParticles2D = _steam.get(id, null)
	if p != null and is_instance_valid(p):
		p.queue_free()
	_steam.erase(id)

func _make_particles(node_name: String, amount: int, one_shot: bool) -> GPUParticles2D:
	var p: GPUParticles2D = GPUParticles2D.new()
	p.name = node_name
	p.amount = amount
	p.one_shot = one_shot
	p.explosiveness = 1.0 if one_shot else 0.0
	p.lifetime = 0.7 if one_shot else 2.0
	p.emitting = false
	p.local_coords = false
	p.add_to_group(FX_GROUP)
	var m: ParticleProcessMaterial = ParticleProcessMaterial.new()
	m.particle_flag_disable_z = true
	m.direction = Vector3(0.0, -1.0, 0.0)
	m.spread = 35.0 if one_shot else 12.0
	m.initial_velocity_min = 40.0 if one_shot else 8.0
	m.initial_velocity_max = 90.0 if one_shot else 18.0
	m.gravity = Vector3(0.0, 260.0 if one_shot else -14.0, 0.0)
	m.scale_min = 1.0
	m.scale_max = 2.0 if one_shot else 3.0
	m.color = UITokens.INK if one_shot else Color(0.85, 0.85, 0.85, 0.35)
	p.process_material = m
	# Текстуры нет: точка 1×1 в пиксельном мире — это и есть капля.
	fx_root.add_child(p)
	return p

# --- Пауза и скорость -----------------------------------------------------

## ⚠️ speed_scale = 0 на GPUParticles2D не останавливает симуляцию надёжно
## (godot issue #77916). Надёжный способ — process_mode = DISABLED.
## На ×2/×3 ускоряем через speed_scale — там артефактов нет.
##
## ⚠️ Гейт по дереву обязателен: сигнал приходит и на выходе из сцены. При
## закрытии игры ScreenRouter._exit_tree разбирает очередь модальных окон,
## каждое снятие автопаузы зовёт cmd_set_speed — а этот узел из дерева уже
## вынут, и get_tree() отдаёт null. Ловится только выходом из игры с открытым
## Итогом забега (tools/playtest_run.gd, шаг «колония ниже порога»).
func _on_speed_changed(mult: int) -> void:
	if not is_inside_tree():
		return
	var mode: Node.ProcessMode = Node.PROCESS_MODE_DISABLED if mult == 0 \
		else Node.PROCESS_MODE_INHERIT
	for n: Node in get_tree().get_nodes_in_group(FX_GROUP):
		n.process_mode = mode
		var p: GPUParticles2D = n as GPUParticles2D
		if p != null and mult > 0:
			p.speed_scale = float(mult)

# --- Служебное ------------------------------------------------------------

func _on_crisis_started(type: int) -> void:
	if type == SimTypes.CrisisType.STORM:
		_storm_target = 1.0

func _on_crisis_ended(type: int) -> void:
	if type == SimTypes.CrisisType.STORM:
		_storm_target = 0.0

func _on_run_started(_seed_value: int) -> void:
	_storm_target = 0.0
	_storm_shown = 0.0
	for id: int in _steam.keys():
		_on_building_removed(id)

func _update_aspect() -> void:
	var win: Window = get_window()
	if win == null:
		return
	_set_param(vignette, &"u_aspect",
		float(win.size.x) / maxf(1.0, float(win.size.y)))

func _set_param(rect: ColorRect, param: StringName, value: Variant) -> void:
	if rect == null:
		return
	var mat: ShaderMaterial = rect.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter(param, value)
