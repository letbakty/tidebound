class_name WorldGeo
extends RefCounted
## Единственное место, где мировые координаты связаны с сеткой и отметками ярусов.
## Переносить в res://game/world_geo.gd (этап 02).
##
## Правило: НИКТО не пишет свою конверсию cell<->world<->mark. WaterView,
## DebugOverlay, BuildGhost, CameraRig, AgentView — все зовут отсюда.
## Один и тот же расчёт в четырёх файлах — источник багов этапов 02/03/07/14/18.

const TILE: int = 32
const TOP_MARK: int = 6           # верхняя отметка карты
const TILES_PER_MARK: int = 3     # 1 ярус = 3 тайла по вертикали
const PX_PER_MARK: int = TILES_PER_MARK * TILE   # 96

# ⚠️ Эти же числа нужны sim (is_flooded, ограничения построек по отметкам).
# Источник правды — Balance; здесь они продублированы как локальные константы
# ТОЛЬКО если Balance ещё не создан. При наличии Balance — заменить на
# const TILE := Balance.TILE и т.д., чтобы число жило в одном месте.

static func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE, cell.y * TILE)

## Центр клетки — для спрайтов и подсветки (map_to_local у TileMapLayer тоже
## возвращает ЦЕНТР, не угол; частая причина смещения призрака на пол-тайла).
static func cell_center_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE * 0.5, cell.y * TILE + TILE * 0.5)

## floori, а не int(): int(-0.5) == 0, floori(-0.5) == -1.
## Ниже отметки 0 — вся вторая половина карты, ошибка на клетку там фатальна.
static func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / float(TILE)), floori(p.y / float(TILE)))

## Принимает float, а не int: уровень воды дробный (-8.0..+2.0), и кромка воды
## обязана считаться той же формулой, что и сетка ярусов.
static func mark_to_world_y(mark: float) -> float:
	return (float(TOP_MARK) - mark) * float(PX_PER_MARK)

static func world_y_to_mark(y: float) -> float:
	return float(TOP_MARK) - y / float(PX_PER_MARK)

static func cell_to_mark(cell: Vector2i) -> int:
	return TOP_MARK - floori(float(cell.y) / float(TILES_PER_MARK))

static func mark_to_first_cell_y(mark: int) -> int:
	return (TOP_MARK - mark) * TILES_PER_MARK

## Экранный Y кромки воды внутри мирового SubViewport.
## Нужен и WaterView этапа 02 (позиция ColorRect), и шейдеру этапа 18 (uniform).
## Писать один раз здесь — тогда на 18-м останется только надеть материал.
static func water_screen_y(level: float, viewport: Viewport) -> float:
	var cam: Camera2D = viewport.get_camera_2d()
	var world_y: float = mark_to_world_y(level)
	if cam == null:
		return world_y
	return (world_y - cam.get_screen_center_position().y) * cam.zoom.y \
		+ viewport.get_visible_rect().size.y * 0.5
