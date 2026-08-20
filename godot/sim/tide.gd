class_name Tide
extends RefCounted
## Уровень воды в отметках (docs/00 §4, §5). 0 = нормальная высокая вода,
## −8 = нормальное дно отлива. Мировая Y считается из этого числа в game/.

var level: float = Balance.HIGH_LEVEL

## Плато — поля, а не const: сизигия поднимает high_plateau до +2,
## карты «Глубокий заход»/«Великий отлив» опускают low_plateau до −10/−12.
var low_plateau: float = Balance.LOW_LEVEL
var high_plateau: float = Balance.HIGH_LEVEL

## Троттлинг события: не чаще раза в EMIT_EVERY тиков и только при заметном
## сдвиге. Это не косметика — без него за забег набегает 36 000 объектов
## SimEvent на одну лишь воду (research/11 §5).
const EMIT_EVERY: int = 3
const EMIT_EPS: float = 0.01

var _ticks_since_emit: int = 0
var _last_emitted: float = Balance.HIGH_LEVEL

## Пересчитывает уровень по фазе и её прогрессу; возвращает события наружу.
func update(clock: SimClock) -> Array[SimEvent]:
	level = _level_for(clock)
	var out: Array[SimEvent] = []
	_ticks_since_emit += 1
	if _ticks_since_emit >= EMIT_EVERY and absf(level - _last_emitted) > EMIT_EPS:
		_ticks_since_emit = 0
		_last_emitted = level
		out.append(SimEvent.make("water_level_changed", {"level": level}))
	return out

## Кривая воды. Ключевые точки — docs/00 §4; между ними smoothstep,
## кроме Сигнала (там спека требует линейного подъёма).
func _level_for(clock: SimClock) -> float:
	var p: float = clock.phase_progress()
	match clock.phase:
		SimTypes.Phase.EBB:
			return lerpf(high_plateau, low_plateau, smoothstep(0.0, 1.0, p))
		SimTypes.Phase.LOW:
			return low_plateau
		SimTypes.Phase.SIGNAL:
			return lerpf(low_plateau, Balance.SIGNAL_LEVEL, p)
		SimTypes.Phase.HIGH:
			# «Вода стеной»: подъём за первые 20 с, дальше плато.
			# Окно подъёма не может быть длиннее самой фазы (шторм/карты
			# укорачивают фазы через phase_scale).
			var rise: int = mini(Balance.HIGH_RISE_TICKS, clock.phase_len(SimTypes.Phase.HIGH))
			if clock.tick_in_phase >= rise:
				return high_plateau
			var t: float = float(clock.tick_in_phase) / float(rise)
			return lerpf(Balance.SIGNAL_LEVEL, high_plateau, smoothstep(0.0, 1.0, t))
	push_error("Tide: неизвестная фаза %d" % int(clock.phase))
	return level

## Сбрасывает уровень к началу забега/цикла без эмиссии события.
func reset(clock: SimClock) -> void:
	level = _level_for(clock)
	_last_emitted = level
	_ticks_since_emit = 0

func to_dict() -> Dictionary:
	return {
		"level": level,
		"low_plateau": low_plateau,
		"high_plateau": high_plateau,
		"ticks_since_emit": _ticks_since_emit,
		"last_emitted": _last_emitted,
	}

func from_dict(d: Dictionary) -> void:
	level = float(d.get("level", Balance.HIGH_LEVEL))
	low_plateau = float(d.get("low_plateau", Balance.LOW_LEVEL))
	high_plateau = float(d.get("high_plateau", Balance.HIGH_LEVEL))
	_ticks_since_emit = int(d.get("ticks_since_emit", 0))
	_last_emitted = float(d.get("last_emitted", level))
