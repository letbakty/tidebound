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

# --- Агенты (docs/00 §6) --------------------------------------------------
const START_AGENTS: int = 6
const MAX_AGENTS: int = 12                 # MVP; релиз — 16
const BAG_SLOTS: int = 4
const WALK_SPEED: float = 2.0              # тайлов/с по площадке
const LADDER_SPEED: float = 1.2            # тайлов/с по лестнице
## Отметка, выше которой Отзыв считает агента в безопасности. +3, а не 0:
## в сизигию плато высокой воды поднимается до +2.
const SAFE_MARK: int = 3
const HARD_RECALL_SPEED_MULT: float = 1.15

## Потребности хранятся в МИЛЛИ-единицах (0..100000) и меняются целочисленно
## с накоплением остатка. Наивное «X за цикл / 3000 тиков» даёт бесконечную
## дробь, ошибка копится, и приёмка save→load этапа 11 не проходит
## (research/11 §1.3). Наружу отдаётся float через SimAgent.satiety() и т.п.
const NEED_MAX_MILLI: int = 100_000
const SATIETY_PER_CYCLE_MILLI: int = 18_000       # −18 за цикл
const WARMTH_PER_CYCLE_MILLI: int = 10_000        # −10 за цикл
const WARMTH_WET_PER_CYCLE_MILLI: int = 25_000    # −25 если мокрый
const WARMTH_HEAT_PER_CYCLE_MILLI: int = 30_000   # +30 у очага
## РЕШЕНИЕ: усталость в docs/00 §6.3 названа «скрытой шкалой» без чисел.
## Берём −20 за цикл и +60 за цикл отдыха: полный отдых занимает треть цикла.
const FATIGUE_PER_CYCLE_MILLI: int = 20_000
const FATIGUE_REST_PER_CYCLE_MILLI: int = 60_000

## Порог «плохо» — 30 (docs/00 §6.3). Выход из состояния ВЫШЕ порога входа:
## без гистерезиса агент дребезжит на границе каждый тик (research/15 §4).
const NEED_LOW_ENTER_MILLI: int = 30_000
const NEED_LOW_EXIT_MILLI: int = 55_000
const NEED_SLOW_MULT: float = 0.75         # скорость при потребности <30
const NEED_SICK_MULT: float = 0.5          # «болезнь» при тепле = 0

## Еда (docs/00 §6.3). Сырая добыча даёт меньше и портит настроение.
const EAT_RATIONS_MILLI: int = 60_000
const EAT_CATCH_MILLI: int = 30_000

## События Духа (docs/00 §6.3).
const MOOD_START_MILLI: int = 70_000
const MOOD_DEATH_MILLI: int = 25_000       # −25 всем за смерть агента
const MOOD_RAW_FOOD_MILLI: int = 5_000
const MOOD_STORAGE_FLOODED_MILLI: int = 10_000
const MOOD_WARM_MEAL_MILLI: int = 5_000
const MOOD_NEW_AGENT_MILLI: int = 5_000
const MOOD_RELIC_MILLI: int = 10_000       # +10 всем за найденную реликвию
const MOOD_COLD_PER_CYCLE_MILLI: int = 5_000   # −5 за цикл при тепле <30

## Утопление (docs/00 §6.3). Снаряжение даёт +15 с к базовым 5.
const DROWN_SEC: float = 5.0
const DROWN_GEAR_SEC: float = 20.0
const DROWN_WARN_SEC: float = 2.0
## Мокрый флаг снимается у очага за 30 с или сам к концу цикла.
const WET_DRY_SEC_AT_HEAT: float = 30.0
const HEAT_RADIUS: int = 4

## Пополнение колонии (docs/00 §6.1).
const NEWCOMER_CHANCE: float = 0.25
const NEWCOMER_MOOD_MIN: float = 60.0
const NEWCOMER_COOLDOWN_CYCLES: int = 2

# --- Работы и политики (docs/00 §6.5, §6.6) -------------------------------
## Дефолты политик старта: Жадность 1, Осторожность 2, Ремонт 1, Стройка 2,
## Заготовка 2, Отдых 1.
const POLICY_DEFAULTS: Dictionary = {
	SimTypes.Policy.GREED: 1,
	SimTypes.Policy.CAUTION: 2,
	SimTypes.Policy.REPAIR: 1,
	SimTypes.Policy.BUILD: 2,
	SimTypes.Policy.SUPPLY: 2,
	SimTypes.Policy.REST: 1,
}
## РЕШЕНИЕ: вес класса = само значение политики (0..3), как написано в
## docs/00 §6.5. research/16 §4 предлагал шкалу [0, 0.5, 1, 2] — это его
## оценка, а не спека; при расхождении приоритет у docs (CONVENTIONS).
const POLICY_WEIGHT: Array[float] = [0.0, 1.0, 2.0, 3.0]

## Жадность: предел расстояния цели от ближайшей лестницы, в тайлах.
## −1 = без лимита (docs/00 §6.6).
const GREED_LADDER_LIMIT: Array[int] = [4, 8, 16, -1]
## Осторожность: за сколько секунд до конца Сигнала объявляется авто-возврат.
const CAUTION_LEAD_SEC: Array[int] = [0, 20, 40, 60]
## Паника (Дух<30) сдвигает личный авто-возврат ещё на 20 с раньше.
const PANIC_RECALL_BONUS_SEC: int = 20

## База «рекламы» задачи (docs/00 §6.5).
const JOB_BASE: Dictionary = {
	SimTypes.JobClass.GATHER: 10.0,
	SimTypes.JobClass.HAUL: 10.0,
	SimTypes.JobClass.BUILD: 12.0,
	SimTypes.JobClass.REPAIR: 12.0,
	SimTypes.JobClass.STATION: 10.0,
	SimTypes.JobClass.REST: 6.0,
	SimTypes.JobClass.EAT: 20.0,
}
const JOB_BASE_EAT_STARVING: float = 100.0     # при Сытости <30
const URGENCY_PERISHABLE: float = 1.5          # переноска портящегося
const URGENCY_CRITICAL_REPAIR: float = 2.0
const URGENCY_BELOW_WATER_IN_SIGNAL: float = 3.0

## Маяк: бонус скоринга и радиус в тайлах (docs/00 §6.7).
const BEACON_BONUS: float = 1.3
const BEACON_RADIUS: float = 12.0
const NO_BEACON: Vector2i = Vector2i(-9999, -9999)

## Добыча: 2 секунды на единицу (docs/00 §6.5 — темп работы).
const GATHER_SEC_PER_UNIT: float = 2.0
## Агент идёт есть, пока сытость ниже этого порога: тот же гистерезис, что
## и у прерываний, иначе сытый агент будет доедать провизию «на всякий случай».
const EAT_WANT_MILLI: int = 55_000
const REST_WANT_MILLI: int = 55_000

# --- Постройки (docs/00 §8) -----------------------------------------------
## 5 секунд на каждую единицу стоимости — суммарное время стройки.
const BUILD_SEC_PER_UNIT: float = 5.0
## Ремонт стоит половину материалов (округление вниз) и столько же времени.
const REPAIR_COST_FRACTION: int = 2
## Снос возвращает половину, округление вниз.
const DEMOLISH_REFUND_FRACTION: int = 2
## Отметка, выше которой шторм постройки не трогает (docs/00 §9.4).
const STORM_SAFE_MARK: int = 3
## Топливо: очаг жжёт 1 сухой плавник за цикл, фонарь — за два.
const HEARTH_FUEL_CYCLES: int = 1
const LANTERN_FUEL_CYCLES: int = 2
## Радиус тепла очага; с разблокировкой u_hearth_big — больше.
const HEAT_RADIUS_BIG: int = 6
const UNLOCK_HEARTH_BIG: String = "u_hearth_big"

# --- Производство (docs/00 §9.1) ------------------------------------------
## Сушила сушат до двух мокрых плавников за цикл — параллельно основному
## рецепту, а не вместо него.
const DRYER_DRIFTWOOD_PER_CYCLE: int = 2
## Дождесборник даёт больше в шторм (docs/00 §9.4).
const RAINCATCHER_STORM_WATER: int = 3
## Лебёдка поднимает один стак за 6 секунд, без участия агента.
const WINCH_LIFT_SEC: float = 6.0

## Затопление: клетка мокрая, если её отметка НИЖЕ уровня воды.
## Эпсилон обязателен — уровень считается по smoothstep и на плато даёт
## −7.9999999, а не −8.0. Без него нижняя ступень мигала бы от float-шума,
## и склад на −8 «затапливался» бы по нескольку раз за цикл (research/12 §5).
const FLOOD_EPS: float = 0.001

## Шаг квантования дробных величин, попадающих в сейв.
##
## ⚠️ JSON.stringify даже с full_precision=true печатает 16 значащих цифр —
## для double этого НЕ хватает: 0.9999999999999969 читается обратно как
## ...68, и продолжение после загрузки расходится с непрерывным прогоном.
## Поэтому каждая дробная величина состояния (позиция агента, доля подъёма
## по лестнице, уровень воды) квантуется в момент изменения. 1e-4 тайла —
## сотая доля пикселя, для игры незаметно, зато представление короткое и
## переживает round-trip точно.
const QUANT_STEPS: float = 10000.0

## ⚠️ Именно деление целого на QUANT_STEPS, а НЕ snappedf(v, 0.0001):
## snappedf умножает на 0.0001, а это число само не представимо точно, и
## результат получается 3.8000000000000003 вместо канонического 3.8 —
## то есть ровно та величина, которая не переживает round-trip.
## Деление же даёт корректно округлённый ближайший double к k/10000.
static func quant(v: float) -> float:
	return float(roundi(v * QUANT_STEPS)) / QUANT_STEPS

## Единственная формула затопления на весь проект: Terrain.is_flooded и
## StorageSystem зовут её, а не пишут своё сравнение.
static func is_mark_flooded(mark: int, water_level: float) -> bool:
	return is_markf_flooded(float(mark), water_level)

## Дробная отметка нужна агенту на лестнице: он между двумя ярусами, и вода
## достаёт его раньше, чем он долез.
static func is_markf_flooded(mark: float, water_level: float) -> bool:
	return mark < water_level - FLOOD_EPS

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
