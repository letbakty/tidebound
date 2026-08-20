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

# --- Геометрия мира (docs/00 §3.1) ----------------------------------------
# Здесь, а не в game/world_geo.gd: sim и презентация обязаны видеть одни числа.
const TILE_PX: int = 32
const TOP_MARK: int = 6                    # верх утёса
const BOTTOM_MARK: int = -8                # дальнее дно
const TILES_PER_MARK: int = 3              # ярус = 3 тайла (docs/00 §2)
const PX_PER_MARK: int = TILE_PX * TILES_PER_MARK
