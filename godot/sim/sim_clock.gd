class_name SimClock
extends RefCounted
## Часы забега: тик → фаза → цикл. Единственный источник времени в sim/
## (Time.* в ядре запрещён — CONVENTIONS).
##
## Границы цикла при единичном phase_scale: 450 / 1950 / 2250 / 3000 тиков.

var tick_in_phase: int = 0
var phase: SimTypes.Phase = SimTypes.Phase.EBB
var cycle: int = 1
var _total_ticks: int = 0

## Масштаб длительности фаз, phase(int) -> множитель. Единичный по умолчанию.
## Заведён на этапе 01 специально: этап 09 (шторм укорачивает LOW на 30%)
## иначе правил бы саму формулу перехода фаз — самое опасное место для
## детерминизма (research/11 §11).
var phase_scale: Dictionary[int, float] = {
	SimTypes.Phase.EBB: 1.0,
	SimTypes.Phase.LOW: 1.0,
	SimTypes.Phase.SIGNAL: 1.0,
	SimTypes.Phase.HIGH: 1.0,
}

## Сквозной счётчик тиков забега (не tick_in_phase): нужен хешам, логам,
## Game.sim_seconds() и графику времени тика.
func total_ticks() -> int:
	return _total_ticks

## Длительность фазы в тиках с учётом масштаба. Минимум 1 тик, иначе
## нулевой масштаб зациклил бы переходы внутри одного тика.
func phase_len(p: SimTypes.Phase) -> int:
	var base: int = int(Balance.PHASE_TICKS[p])
	var scale: float = float(phase_scale.get(int(p), 1.0))
	return maxi(1, int(round(float(base) * scale)))

func phase_progress() -> float:
	return float(tick_in_phase) / float(phase_len(phase))

## Продвигает время на один тик и возвращает события границ.
## Порядок событий внутри тика фиксирован: cycle_ended → cycle_started →
## phase_changed. Менять нельзя — на него опирается автопауза Итога цикла.
func tick() -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	_total_ticks += 1
	tick_in_phase += 1
	if tick_in_phase < phase_len(phase):
		return out

	tick_in_phase = 0
	var prev: SimTypes.Phase = phase
	if phase == SimTypes.Phase.HIGH:
		# Конец HIGH = конец цикла. Наполнение отчёта — этапы 08/11.
		# РЕШЕНИЕ: кладём в отчёт номер завершившегося цикла, иначе слушатель
		# не отличит итог 3-го цикла от итога 4-го.
		out.append(SimEvent.make("cycle_ended", {"cycle": cycle}))
		cycle += 1
		phase = SimTypes.Phase.EBB
		out.append(SimEvent.make("cycle_started", {"cycle": cycle}))
	else:
		phase = (prev + 1) as SimTypes.Phase
	# prev нужен этапу 08, чтобы отличить «конец LOW» от «начала SIGNAL».
	out.append(SimEvent.make("phase_changed", {
		"phase": int(phase), "prev": int(prev), "cycle": cycle,
	}))
	return out

func to_dict() -> Dictionary:
	var scale_out: Dictionary = {}
	for p: int in phase_scale:
		scale_out[str(p)] = phase_scale[p]   # ключи JSON — всегда строки
	return {
		"tick_in_phase": tick_in_phase,
		"phase": int(phase),
		"cycle": cycle,
		"total_ticks": _total_ticks,
		"phase_scale": scale_out,
	}

func from_dict(d: Dictionary) -> void:
	# int() обязателен: JSON.parse отдаёт ВСЕ числа как float, и без приведения
	# следующий to_dict напечатал бы 12.0 вместо 12 → хеш не совпадёт
	# (research/11 §8 — ошибка №1 при написании сейвов в Godot).
	tick_in_phase = int(d.get("tick_in_phase", 0))
	phase = int(d.get("phase", SimTypes.Phase.EBB)) as SimTypes.Phase
	cycle = int(d.get("cycle", 1))
	_total_ticks = int(d.get("total_ticks", 0))
	var scale_in: Dictionary = d.get("phase_scale", {}) as Dictionary
	for p: int in SimTypes.PHASE_ORDER:
		phase_scale[p] = float(scale_in.get(str(p), 1.0))
