class_name WaterView
extends ColorRect
## Вода: экранный прямоугольник на CanvasLayer ВНУТРИ мирового SubViewport.
##
## Нода растянута на весь вьюпорт и НЕ двигается: двигающийся прямоугольник
## даёт субпиксельный джиттер относительно мира при панораме (research/06 §4).
## Позиция кромки передаётся ЧИСЛОМ (surface_screen_y), а не размером ноды —
## на этапе 18 то же число уедет в uniform шейдера, и переделывать будет нечего.
##
## ⚠️ ОТКЛОНЕНИЕ от промпта 02 и research/12 §7: у FxLayer
## follow_viewport_enabled = FALSE, а не true. С true слой берёт трансформ
## камеры, и Full Rect растягивается в МИРОВЫХ координатах — прямоугольник
## начинает ездить за камерой, а экранный Y кромки считается уже в другой
## системе координат. Проверено на скриншоте: вода уезжала в верх экрана.
## Экранный слой + кромка числом — это и есть требование «не двигается».
##
## Заглушка этапа 02: заливка через _draw(). Шейдер — этап 18.
## Публичный контракт сохраняется: подписка на Events.water_level_changed.

## РЕШЕНИЕ: цвета воды — визуальные числа, не игровые, поэтому живут здесь,
## а не в Balance (палитра docs/01 §4). На этапе 18 они уедут в параметры
## материала, который правит художник в инспекторе.
const SHALLOW: Color = Color("2d6b7a", 0.40)
const DEEP: Color = Color("1a3a4a", 0.90)
const FOAM: Color = Color("e8eff0")
const FOAM_PX: float = 2.0
const DEPTH_RANGE_PX: float = 160.0     # ≈1.7 яруса до выхода на цвет глубины

## Events.water_level_changed приходит раз в 3 тика — без сглаживания кромка
## двигалась бы ступеньками по 3 px на подъёме «стеной» в фазе HIGH.
const LEVEL_LERP: float = 18.0

var _level_target: float = Balance.HIGH_LEVEL
var _level_shown: float = Balance.HIGH_LEVEL
var _last_drawn_y: float = INF

func _ready() -> void:
	color = Color(0, 0, 0, 0)          # сам прямоугольник прозрачен, рисует _draw
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Events.water_level_changed.connect(_on_water_level_changed)
	Events.run_started.connect(_on_run_started)

func _process(delta: float) -> void:
	_level_shown = lerpf(_level_shown, _level_target, minf(1.0, LEVEL_LERP * delta))
	var y: float = surface_screen_y()
	# Перерисовка только при сдвиге кромки на целый пиксель: камера двигается
	# каждый кадр, а вода — нет.
	if not is_equal_approx(y, _last_drawn_y):
		_last_drawn_y = y
		queue_redraw()

func _draw() -> void:
	var y: float = _last_drawn_y
	if y >= size.y:
		return
	var top: float = maxf(y, 0.0)
	# Градиент мелководье → глубина: два прямоугольника вместо шейдера.
	var fade: float = minf(DEPTH_RANGE_PX, size.y - top)
	draw_rect(Rect2(0.0, top, size.x, fade), SHALLOW, true)
	if size.y - top > fade:
		draw_rect(Rect2(0.0, top + fade, size.x, size.y - top - fade), DEEP, true)
	if y >= 0.0:
		draw_rect(Rect2(0.0, y, size.x, FOAM_PX), FOAM, true)

## Экранный Y кромки. Нужен брызгам, отражениям и шейдеру этапа 18 —
## чтобы никто не считал его заново.
func surface_screen_y() -> float:
	return floorf(WorldGeo.water_screen_y(_level_shown, get_viewport()))

func _on_water_level_changed(level: float) -> void:
	_level_target = level

func _on_run_started(_seed_value: int) -> void:
	_level_target = Balance.HIGH_LEVEL
	_level_shown = Balance.HIGH_LEVEL
