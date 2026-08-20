class_name WorldGeo
extends RefCounted
## Единственное место, где мировые координаты связаны с сеткой и отметками ярусов.
##
## Правило: НИКТО не пишет свою конверсию cell<->world<->mark. WaterView,
## DebugOverlay, BuildGhost, CameraRig, AgentView — все зовут отсюда.
## Один и тот же расчёт в четырёх файлах — источник багов этапов 02/03/07/14/18.
##
## Числа берутся из Balance: их же использует sim (is_flooded, ограничения
## построек по отметкам). Дубликат здесь означал бы, что на этапе 18 вода
## уедет на 96 пикселей (research/12 §3).

const TILE: int = Balance.TILE_PX
const TOP_MARK: int = Balance.TOP_MARK
const TILES_PER_MARK: int = Balance.TILES_PER_MARK
const PX_PER_MARK: int = Balance.PX_PER_MARK

static func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(float(cell.x * TILE), float(cell.y * TILE))

## Центр клетки — для спрайтов и подсветки. map_to_local у TileMapLayer тоже
## возвращает ЦЕНТР, не угол: частая причина смещения призрака на пол-тайла.
static func cell_center_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE * 0.5, cell.y * TILE + TILE * 0.5)

## floori, а не int(): int(-0.5) == 0, floori(-0.5) == -1.
## Ниже отметки 0 — вся вторая половина карты, ошибка на клетку там фатальна.
static func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / float(TILE)), floori(p.y / float(TILE)))

## Принимает float, а не int: уровень воды дробный (−8.0..+2.0), и кромка воды
## обязана считаться той же формулой, что и сетка ярусов.
static func mark_to_world_y(mark: float) -> float:
	return (float(TOP_MARK) - mark) * float(PX_PER_MARK)

static func world_y_to_mark(y: float) -> float:
	return float(TOP_MARK) - y / float(PX_PER_MARK)

# Сетка ↔ отметки живут в Balance: ту же формулу использует sim (Terrain,
# is_flooded, ограничения построек). Здесь только проброс, чтобы презентация
# звала всё из одного места.
static func cell_to_mark(cell: Vector2i) -> int:
	return Balance.cell_to_mark(cell)

static func mark_to_first_cell_y(mark: int) -> int:
	return Balance.mark_to_first_cell_y(mark)

static func mark_to_floor_cell_y(mark: int) -> int:
	return Balance.mark_to_floor_cell_y(mark)

## Экранный Y кромки воды внутри мирового SubViewport.
## Нужен и WaterView этапа 02 (позиция ColorRect), и шейдеру этапа 18 (uniform):
## одна формула на оба — тогда на 18-м останется только надеть материал.
static func water_screen_y(level: float, viewport: Viewport) -> float:
	var world_y: float = mark_to_world_y(level)
	if viewport == null:
		return world_y
	# Канвас-трансформ учитывает и позицию камеры, и её зум — считать их
	# по отдельности значит рано или поздно забыть про одно из них.
	return (viewport.get_canvas_transform() * Vector2(0.0, world_y)).y
