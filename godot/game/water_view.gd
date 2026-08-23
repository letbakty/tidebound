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

## Кромка воды: рябь, буи и всплеск (assets/sprites/fx_*.png, buoys.png —
## сборщик tools/gen_decor.gd).
##
## ⚠️ Всё это ЭКРАННЫЕ дети WaterView, а не ноды мира: сам прямоугольник воды
## намеренно не двигается (см. шапку), и кромка вместе с ним живёт в
## координатах вьюпорта. Мировые ноды здесь дали бы тот самый субпиксельный
## джиттер, ради которого вода и стоит на месте.
const RIPPLE_SHEET: String = "res://assets/sprites/fx_ripple.png"
const SPLASH_SHEET: String = "res://assets/sprites/fx_splash.png"
const BUOY_SHEET: String = "res://assets/sprites/buoys.png"
const FX_CELL: int = 32
## Рябь не тайлится сплошной лентой намеренно: повтор одного кадра каждые
## 32 px читается как узор, а не как вода. Несколько пятен вразбивку и с
## разным кадром — читается.
const RIPPLE_COUNT: int = 7
const RIPPLE_FPS: float = 6.0
const SPLASH_FPS: float = 12.0
const BUOY_BOB_PX: float = 2.0
const BUOY_BOB_HZ: float = 0.35

var _level_target: float = Balance.HIGH_LEVEL
var _level_shown: float = Balance.HIGH_LEVEL
var _storm_target: float = 0.0
var _storm_shown: float = 0.0
var _mat: ShaderMaterial = null
var _last_surface_y: float = INF
## Отметка, до которой брызги уже отыграли: всплеск даётся на ярус, а не на
## каждый кадр подъёма.
var _splashed_mark: int = 99
var _ripples: Array[Sprite2D] = []
var _buoys: Array[Sprite2D] = []
var _splash: Sprite2D = null
## Сим-время начала всплеска. -1 — не играет.
var _splash_started: float = -1.0

func _ready() -> void:
	color = Color(0, 0, 0, 0)          # цвет рисует шейдер, сам прямоугольник пуст
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = material as ShaderMaterial
	if _mat == null:
		push_error("WaterView: ожидается ShaderMaterial с water.gdshader")
	else:
		_mat.set_shader_parameter(&"u_view_size", Vector2(get_viewport_rect().size))
	_build_edge_fx()
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
	_update_edge_fx(y)

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
	_splash_started = Game.sim_seconds()
	fx.splash_at(get_viewport().get_canvas_transform().affine_inverse()
		* Vector2(vp.x * 0.5, surface_screen_y()))

# --- Кромка воды: рябь, буи, всплеск ---------------------------------------

func _build_edge_fx() -> void:
	var ripple: Texture2D = load(RIPPLE_SHEET) as Texture2D
	if ripple != null:
		for i: int in RIPPLE_COUNT:
			_ripples.append(_make_fx(ripple, "Ripple%d" % i))
	var buoys: Texture2D = load(BUOY_SHEET) as Texture2D
	if buoys != null:
		for i2: int in maxi(1, buoys.get_width() / 16):
			var b: Sprite2D = _make_fx(buoys, "Buoy%d" % i2)
			b.region_rect = Rect2(float(i2 * 16), 0.0, 16.0, 16.0)
			_buoys.append(b)
	var splash: Texture2D = load(SPLASH_SHEET) as Texture2D
	if splash != null:
		_splash = _make_fx(splash, "Splash")

func _make_fx(tex: Texture2D, node_name: String) -> Sprite2D:
	var s: Sprite2D = Sprite2D.new()
	s.name = node_name
	s.texture = tex
	s.region_enabled = true
	s.region_rect = Rect2(0.0, 0.0, float(FX_CELL), float(FX_CELL))
	s.visible = false
	add_child(s)
	return s

## Кадр листа по сим-времени: на паузе кромка замирает вместе с водой.
func _frame_rect(tex: Texture2D, frame: int, cell: int) -> Rect2:
	var cols: int = maxi(1, tex.get_width() / cell)
	var rows: int = maxi(1, tex.get_height() / cell)
	var n: int = posmod(frame, cols * rows)
	return Rect2(float((n % cols) * cell), float((n / cols) * cell),
		float(cell), float(cell))

func _update_edge_fx(surface_y: float) -> void:
	var vp: Vector2 = get_viewport_rect().size
	# Кромки не видно — гасим всё: невидимые спрайты не должны считать кадры.
	var on_screen: bool = surface_y > -float(FX_CELL) and surface_y < vp.y
	var t: float = Game.sim_seconds()
	for i: int in _ripples.size():
		var r: Sprite2D = _ripples[i]
		r.visible = on_screen
		if not on_screen:
			continue
		# Пятна вразбивку и с разным кадром: синхронная рябь читается как
		# полоса обоев, а не как вода.
		r.position = Vector2(roundf(vp.x * (float(i) + 0.5) / float(RIPPLE_COUNT)),
			roundf(surface_y))
		r.region_rect = _frame_rect(r.texture, int(t * RIPPLE_FPS) + i * 3, FX_CELL)
	for j: int in _buoys.size():
		var b: Sprite2D = _buoys[j]
		b.visible = on_screen
		if not on_screen:
			continue
		# Буй качается на волне: то же сим-время, что и у ряби.
		var bob: float = sin((t + float(j) * 1.7) * BUOY_BOB_HZ * TAU) * BUOY_BOB_PX
		b.position = Vector2(roundf(vp.x * (0.22 + 0.56 * float(j))),
			roundf(surface_y - 6.0 + bob))
	if _splash != null:
		_update_splash(t, surface_y, vp, on_screen)

func _update_splash(t: float, surface_y: float, vp: Vector2, on_screen: bool) -> void:
	if _splash_started < 0.0 or not on_screen:
		_splash.visible = false
		return
	var cols: int = maxi(1, _splash.texture.get_width() / FX_CELL)
	var rows: int = maxi(1, _splash.texture.get_height() / FX_CELL)
	var frame: int = int((t - _splash_started) * SPLASH_FPS)
	if frame < 0 or frame >= cols * rows:
		_splash.visible = false
		_splash_started = -1.0
		return
	_splash.visible = true
	_splash.position = Vector2(roundf(vp.x * 0.5), roundf(surface_y - 8.0))
	_splash.region_rect = _frame_rect(_splash.texture, frame, FX_CELL)

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
	_splash_started = -1.0
	_storm_target = 0.0
	_storm_shown = 0.0

func _on_crisis_started(type: int) -> void:
	if type == SimTypes.CrisisType.STORM:
		_storm_target = 1.0

func _on_crisis_ended(type: int) -> void:
	if type == SimTypes.CrisisType.STORM:
		_storm_target = 0.0
