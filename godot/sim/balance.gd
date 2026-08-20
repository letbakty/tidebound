class_name Balance
extends RefCounted
## ВСЕ игровые числа проекта. Только const — статических изменяемых переменных
## здесь быть не может: два SimWorld в тесте детерминизма делили бы состояние
## и тест стал бы ложно-зелёным (research/11 §4).
## Магическое число в коде системы = дефект (CONVENTIONS).

# --- Время (docs/00 §2, §4) -----------------------------------------------
const TICKS_PER_SEC: int = 10

## Базовая длительность фаз в тиках: 45 / 150 / 30 / 75 секунд.
## Реальная длительность = база × SimClock.phase_scale (шторм укорачивает LOW).
const PHASE_TICKS: Dictionary = {
	SimTypes.Phase.EBB: 450,
	SimTypes.Phase.LOW: 1500,
	SimTypes.Phase.SIGNAL: 300,
	SimTypes.Phase.HIGH: 750,
}
const TICKS_PER_CYCLE: int = 3000          # сумма PHASE_TICKS при единичном масштабе
const CYCLES_PER_RUN: int = 12

# --- Вода (docs/00 §4, §5) ------------------------------------------------
const HIGH_LEVEL: float = 0.0              # плато высокой воды = отметка 0
const LOW_LEVEL: float = -8.0              # плато низкой воды
const SIGNAL_LEVEL: float = -6.0           # уровень к концу фазы Сигнал
const SPRING_BONUS: float = 2.0            # сизигия: плато HIGH = 0 + 2
## «Вода стеной» в начале HIGH: −6 → плато за первые 20 с.
const HIGH_RISE_TICKS: int = 200

# --- Календарь кризисов (docs/00 §9.2) ------------------------------------
## cycle -> список кризисов цикла. count = число существ Прихода (0 для остальных).
## Объявление — за CRISIS_ANNOUNCE_LEAD циклов до события.
const CRISIS_CALENDAR: Dictionary = {
	4: [{"type": SimTypes.CrisisType.VISIT, "count": 1}],
	6: [{"type": SimTypes.CrisisType.SPRING_TIDE, "count": 0}],
	7: [{"type": SimTypes.CrisisType.VISIT, "count": 2}],
	10: [
		{"type": SimTypes.CrisisType.STORM, "count": 0},
		{"type": SimTypes.CrisisType.VISIT, "count": 3},
	],
	12: [{"type": SimTypes.CrisisType.SPRING_TIDE, "count": 0}],
}
const CRISIS_ANNOUNCE_LEAD: int = 1
## Шторм укорачивает LOW на 30% (docs/00 §9.4) — множитель для phase_scale.
const STORM_LOW_SCALE: float = 0.7

# --- Депозиты (docs/00 §3.2) ----------------------------------------------
## kind -> {item, capacity, refill (за отлив), marks (допустимый диапазон)}.
## refill = 0 значит «не восполняется»: ближние руины кончаются к 4–5 циклу,
## и это главный источник давления в забеге.
const DEPOSIT_KINDS: Dictionary = {
	"ruins_near": {"item": "scrap", "capacity": 12, "refill": 0, "mark_hi": -2, "mark_lo": -4},
	"ruins_deep": {"item": "scrap", "capacity": 20, "refill": 0, "mark_hi": -5, "mark_lo": -8},
	"shallow": {"item": "catch", "capacity": 8, "refill": 4, "mark_hi": -1, "mark_lo": -5},
	"kelp": {"item": "kelp", "capacity": 10, "refill": 2, "mark_hi": -2, "mark_lo": -5},
}
## Реликвия: 15% на депозит глубоких руин, но только на −7..−8, 1 штука.
const RELIC_CHANCE: float = 0.15
const RELIC_MARK_MAX: int = -7             # реликвия возможна на отметке ≤ этой
## Плавник после каждой Высокой воды: 3–6 стаков на земле вдоль отметок 0..+1
## (docs/00 §3.2). Спавнит StorageSystem — это предметы, а не депозит.
const DRIFTWOOD_MIN: int = 3
const DRIFTWOOD_MAX: int = 6
const DRIFTWOOD_MARK_LO: int = 0
const DRIFTWOOD_MARK_HI: int = 1

# --- Предметы и склады (docs/00 §7, §11.1) --------------------------------
const STORAGE_SLOTS: int = 12              # слот = один стак
## Мокрый стак сохнет 2 полных цикла на складе не ниже DRY_MIN_MARK.
const DRY_CYCLES: int = 2
const DRY_MIN_MARK: int = 2
## Старт забега (docs/00 §11.1): 8 провизии, 6 сухого плавника, 4 утиля.
## Массив пар, а не словарь: порядок раскладки по складу обязан быть
## детерминированным, а порядок обхода словаря зависит от порядка вставки.
const START_ITEMS: Array[Array] = [
	["rations", 8], ["driftwood", 6], ["scrap", 4],
]

## Затопление: клетка мокрая, если её отметка НИЖЕ уровня воды.
## Эпсилон обязателен — уровень считается по smoothstep и на плато даёт
## −7.9999999, а не −8.0. Без него нижняя ступень мигала бы от float-шума,
## и склад на −8 «затапливался» бы по нескольку раз за цикл (research/12 §5).
const FLOOD_EPS: float = 0.001

## Единственная формула затопления на весь проект: Terrain.is_flooded и
## StorageSystem зовут её, а не пишут своё сравнение.
static func is_mark_flooded(mark: int, water_level: float) -> bool:
	return float(mark) < water_level - FLOOD_EPS

# --- Геометрия мира (docs/00 §3.1) ----------------------------------------
# Здесь, а не в game/world_geo.gd: sim и презентация обязаны видеть одни числа.
const TILE_PX: int = 32
const TOP_MARK: int = 6                    # верх утёса
const BOTTOM_MARK: int = -8                # дальнее дно
const TILES_PER_MARK: int = 3              # ярус = 3 тайла (docs/00 §2)
const PX_PER_MARK: int = TILE_PX * TILES_PER_MARK

## Сетка ↔ отметки. Статические функции, а не const — но правило «только const»
## они не нарушают: изменяемого состояния тут нет, а формула обязана быть ОДНА
## на оба слоя. Terrain (sim) и WorldGeo (game) зовут отсюда; дубликат формулы
## означал бы, что вода и площадки однажды разъедутся на ярус (research/12 §3).
## floori, а не int(): int(-0.5) == 0, а нужно −1 — ниже отметки 0 лежит
## вся вторая половина карты.
static func cell_to_mark(cell: Vector2i) -> int:
	return TOP_MARK - floori(float(cell.y) / float(TILES_PER_MARK))

## Верхняя строка яруса; ярус занимает [first_y, first_y + 2].
static func mark_to_first_cell_y(mark: int) -> int:
	return (TOP_MARK - mark) * TILES_PER_MARK

## Пол яруса — НИЖНЯЯ его строка: над ней две строки свободного пространства
## (docs/00 §2 «площадка + пространство над ней»). Агент стоит здесь.
static func mark_to_floor_cell_y(mark: int) -> int:
	return mark_to_first_cell_y(mark) + TILES_PER_MARK - 1
