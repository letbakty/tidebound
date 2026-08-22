class_name CameraRig
extends Camera2D
## Камера мира: панорама, зум ступенями, лимиты по краям карты.
##
## Плавность НЕ через position_smoothing: вместе с pixel snap он даёт
## задокументированную дрожь в масштабированном SubViewport (issue 93048).
## Вместо него — дробная «виртуальная» позиция, а настоящая всегда округлена
## до целого пикселя (research/12 §6.4).

## Ступени зума мира из docs/01 §1.1. Число — во сколько раз мир крупнее
## нативного пикселя окна.
##
## РЕШЕНИЕ: контейнер мира держит stretch_shrink = 2 (этап 00), поэтому зум
## камеры = factor / 2 → 1.0 / 1.5 / 2.0. Ступени ×2 и ×4 пиксель-идеальны.
## У ×3 тайл делится ровно (32 → 48), но деталь внутри спрайта масштабируется
## неравномерно. Числа зафиксированы в docs/01, поэтому оставлены как есть;
## этапу 18 это стоит проверить глазами на финальном арте.
const ZOOM_FACTORS: Array[int] = [2, 3, 4]
const ZOOM_TWEEN_SEC: float = 0.15
const FOCUS_TWEEN_SEC: float = 0.35
const PAN_SPEED_PX: float = 220.0
## Скорость таскания правой кнопкой: 1.0 = мир едет ровно за курсором.
const DRAG_GAIN: float = 1.0

var _zoom_idx: int = 0
var _virtual_pos: Vector2 = Vector2.ZERO
var _limit_min: Vector2 = Vector2.ZERO
var _limit_max: Vector2 = Vector2.ZERO
var _map_px: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _zoom_tween: Tween = null
var _focus_tween: Tween = null

func setup(cliff: CliffDef) -> void:
	_map_px = Vector2(float(cliff.width * WorldGeo.TILE), float(cliff.height * WorldGeo.TILE))
	_apply_zoom(ZOOM_FACTORS[_zoom_idx], false)
	_virtual_pos = WorldGeo.cell_center_world(cliff.spawn_cell)
	_recalc_limits()
	_commit()

func _ready() -> void:
	position_smoothing_enabled = false
	ignore_rotation = true
	make_current()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return                          # мир скрыт экраном (аудит B1.5)
	var dir: Vector2 = Input.get_vector("pan_left", "pan_right", "pan_up", "pan_down")
	if dir != Vector2.ZERO:
		_kill_zoom_tween()
		_kill_focus_tween()
		_virtual_pos += dir * PAN_SPEED_PX * delta / zoom.x
		_commit()

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_RIGHT:
		_dragging = mb.pressed
		return
	# ⚠️ Колесо здесь НЕ ловим: жесты (в том числе зум колесом) распознаёт
	# InputService и отдаёт их сигналом zoom_step. Пока это делали оба, один
	# щелчок давал две ступени (аудит B2.7).
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null and _dragging:
		_kill_focus_tween()
		_virtual_pos -= mm.relative * DRAG_GAIN / zoom.x
		_commit()

## Плавный центр камеры на точке мира. Зовёт HUD по тапу на чипе агента или
## тосте — и только по явному действию игрока: событиями камеру не «похищаем»
## (docs/01 §5, антипаттерн автозума Fallout Shelter).
func focus_on(world_pos: Vector2, animated: bool = true) -> void:
	_kill_focus_tween()
	var target: Vector2 = world_pos.clamp(_limit_min, _limit_max)
	# reduce_motion — про вестибулярный дискомфорт, и наезд камеры под него
	# подпадает наравне с анимациями интерфейса (docs/03 §3.6).
	if not animated or Game.fast_forwarding or Settings.reduce_motion:
		_virtual_pos = target
		_commit()
		return
	_focus_tween = create_tween()
	_focus_tween.tween_method(func(p: Vector2) -> void:
		_virtual_pos = p
		_commit(), _virtual_pos, target, FOCUS_TWEEN_SEC) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Любой ввод игрока прерывает наезд: камера не должна «доезжать» поверх
## того, что игрок уже сам подвинул (research/21 §10).
func _kill_focus_tween() -> void:
	if _focus_tween != null and _focus_tween.is_valid():
		_focus_tween.kill()
	_focus_tween = null

## Зум ступенями. factor — из ZOOM_FACTORS; сюда переехал set_world_zoom этапа 00.
func set_zoom_step(factor: int) -> void:
	var idx: int = ZOOM_FACTORS.find(factor)
	if idx < 0:
		push_warning("CameraRig: ступени зума %s, запрошено ×%d" % [str(ZOOM_FACTORS), factor])
		return
	_zoom_idx = idx
	_apply_zoom(factor, true)

func zoom_in() -> void:
	set_zoom_step(ZOOM_FACTORS[mini(_zoom_idx + 1, ZOOM_FACTORS.size() - 1)])

func zoom_out() -> void:
	set_zoom_step(ZOOM_FACTORS[maxi(_zoom_idx - 1, 0)])

## Панорама пальцем: жест приходит из InputService через World (этап 13).
func pan_by(screen_delta: Vector2) -> void:
	_kill_focus_tween()
	_kill_zoom_tween()
	_virtual_pos -= screen_delta * DRAG_GAIN / zoom.x
	_commit()

func zoom_factor() -> int:
	return ZOOM_FACTORS[_zoom_idx]

func _apply_zoom(factor: int, animated: bool) -> void:
	# Контейнер уже увеличивает мир вдвое, камере остаётся factor / 2.
	var target: Vector2 = Vector2.ONE * (float(factor) * 0.5)
	_kill_zoom_tween()
	if not animated or Settings.reduce_motion:
		zoom = target
		_recalc_limits()
		_commit()
		return
	# Промежуточные значения дробные — это допустимо только в анимации,
	# конечное состояние всегда «приземляется» на ступень (docs/01 §1.1).
	_zoom_tween = create_tween()
	_zoom_tween.tween_property(self, "zoom", target, ZOOM_TWEEN_SEC) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# ⚠️ parallel() цепляет следующий твинер к ПРЕДЫДУЩЕМУ шагу. Стоя после
	# tween_callback, он шёл параллельно колбэку — то есть уже ПОСЛЕ анимации,
	# и всю отдалённую анимацию камера жила со старыми лимитами: на краю карты
	# в кадр попадала пустота за её пределами (аудит B5).
	_zoom_tween.parallel().tween_method(func(_v: float) -> void:
		_recalc_limits()
		_commit(), 0.0, 1.0, ZOOM_TWEEN_SEC)
	# chain(): «приземление» на ступень — строго после обоих.
	_zoom_tween.chain().tween_callback(func() -> void:
		zoom = target
		_recalc_limits()
		_commit())

func _kill_zoom_tween() -> void:
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = null

## Лимиты Camera2D заданы в мировых координатах и от зума не зависят, а вот
## видимая область — зависит. Клампим центр сами: иначе на дальнем зуме камера
## упирается в лимит и «застревает» в углу (research/12 §6.2).
func _recalc_limits() -> void:
	var view: Vector2 = Vector2(get_viewport_rect().size) / zoom
	var half: Vector2 = view * 0.5
	limit_left = 0
	limit_top = 0
	limit_right = int(_map_px.x)
	limit_bottom = int(_map_px.y)
	# Карта уже вьюпорта — центрируем, а не клампим в ноль.
	_limit_min = Vector2(
		minf(half.x, _map_px.x * 0.5), minf(half.y, _map_px.y * 0.5))
	_limit_max = Vector2(
		maxf(_map_px.x - half.x, _map_px.x * 0.5),
		maxf(_map_px.y - half.y, _map_px.y * 0.5))

func _commit() -> void:
	_virtual_pos = _virtual_pos.clamp(_limit_min, _limit_max)
	# Камера всегда на целом пикселе: дробная позиция + Nearest = «кипящие» края.
	global_position = _virtual_pos.round()
	# Вертикальный эмбиент-кроссфейд (этап 17): наверху чайки, внизу капель.
	# Троттлинг живёт в AudioService — камера не обязана знать про 4 Гц.
	AudioService.set_camera_mark(WorldGeo.world_y_to_mark(global_position.y))
