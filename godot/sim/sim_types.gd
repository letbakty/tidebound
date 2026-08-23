class_name SimTypes
extends RefCounted
## Общие перечисления симуляции + хелперы сериализации.
## Контракт: docs/02 §3.1. Значения enum'ов уходят в сейв как int — порядок
## членов менять нельзя, только дописывать в конец.

enum Phase { EBB, LOW, SIGNAL, HIGH }
enum AgentState { IDLE, GOTO, WORK, HAUL, GATHER, RETURN, REST, EAT, PANIC, DROWNING, DEAD }
enum JobClass { GATHER, HAUL, BUILD, REPAIR, STATION, REST, EAT }
enum Policy { GREED, CAUTION, REPAIR, BUILD, SUPPLY, REST }
enum FloodRule { OK, WET, LOSE_HALF, DESTROY, DISABLED }
enum CrisisType { SPRING_TIDE, STORM, VISIT }   # сизигия, шторм, приход
## SURRENDER дописан в конец (значения enum уходят в сейв — см. шапку):
## сдача — решение игрока, а не гибель колонии, и звать её гибелью нельзя
## (docs/00 §11.2, исход 4).
enum RunEnd { SHIP, WIPE, EARLY, SURRENDER }
## Расширение контракта docs/02 §3.1 (этап 07): три состояния постройки.
## Именно три + два ортогональных флага (flooded, damaged), а не пять
## состояний: постройка бывает ACTIVE+flooded+damaged одновременно, и правила
## для каждой комбинации свои — enum из пяти дал бы комбинаторный взрыв.
enum BuildState { PLANNED, UNDER_CONSTRUCTION, ACTIVE }

## Порядок обхода фаз внутри цикла. Заведён отдельно от enum'а, чтобы код
## переходов не полагался на арифметику по значениям.
const PHASE_ORDER: Array[int] = [Phase.EBB, Phase.LOW, Phase.SIGNAL, Phase.HIGH]

## Порядок обхода политик — он же порядок в сейве и в панели.
const POLICY_ORDER: Array[int] = [Policy.GREED, Policy.CAUTION, Policy.REPAIR,
	Policy.BUILD, Policy.SUPPLY, Policy.REST]

# --- Хелперы сериализации (research/11 §8) --------------------------------
# JSON не знает Vector2i и не умеет NAN/INF: конвертируем руками, а не надеемся.

static func v2i_to_arr(v: Vector2i) -> Array:
	return [v.x, v.y]

static func arr_to_v2i(a: Array) -> Vector2i:
	if a.size() < 2:
		push_error("arr_to_v2i: ожидался массив из 2 чисел, получено %s" % str(a))
		return Vector2i.ZERO
	return Vector2i(int(a[0]), int(a[1]))

## NAN/INF в JSON превращаются в null молча — конвертируем явно.
static func f_or_null(v: float) -> Variant:
	return null if is_nan(v) else v

static func null_or_f(v: Variant) -> float:
	return NAN if v == null else float(v)

static func phase_name(p: int) -> String:
	match p:
		Phase.EBB: return "EBB"
		Phase.LOW: return "LOW"
		Phase.SIGNAL: return "SIGNAL"
		Phase.HIGH: return "HIGH"
	return "?"
