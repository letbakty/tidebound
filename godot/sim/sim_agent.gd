class_name SimAgent
extends RefCounted
## Данные одного агента. Поведение — в AgentSystem; здесь только состояние
## и свёртка модификаторов черт.
##
## Позиция — (platform_id, x в ТАЙЛАХ), а не Vector2: компоненты Vector2 в
## обычной сборке 32-битные, и накопление в них даёт дрожь на длинных прогонах
## (research/11 §1.2). Пиксели — забота View.

const NEED_KEYS: Array[String] = ["satiety", "warmth", "mood", "fatigue"]

var id: int = 0
var agent_name: String = ""
var bio_key: String = ""
var trait_ids: Array[String] = []

var state: SimTypes.AgentState = SimTypes.AgentState.IDLE
## Сколько тиков агент в текущем состоянии. Обязателен в сейве: без него
## после загрузки агент начнёт еду или работу заново.
var state_ticks: int = 0

var platform_id: int = 0
var x: float = 0.0
var target_x: float = 0.0
## Куда лезем: id площадки или −1. climb_t — 0..1 вдоль лестницы.
var climb_to: int = -1
var climb_t: float = 0.0
var facing: int = 1

## Кэш пути. Пересчитывается только при смене цели или графа — иначе поиск
## пути шёл бы каждый тик на каждого агента (research/11 §7).
var path: Array[int] = []
var path_idx: int = 0
var path_graph_version: int = -1
## Что делать по прибытии: GOTO — это всегда «идти, чтобы затем...».
var intent: SimTypes.AgentState = SimTypes.AgentState.IDLE
var goto_platform: int = -1
var goto_x: float = 0.0

## Потребности в милли-единицах + целочисленные остатки накопления.
var needs: Dictionary[String, int] = {}
var need_rem: Dictionary[String, int] = {}

var bag: Array[Dictionary] = []
var wet: bool = false
var has_gear: bool = false
var submerged_ticks: int = 0
var heat_ticks: int = 0
var drowning_warned: bool = false
var recalled: bool = false
var recall_hard: bool = false
## Двусторонняя связь с резервированием: job.taken_by == id ⟺ agent.job_id == job.id.
var job_id: int = -1
## Тики, накопленные на текущем действии (добыча идёт 2 с на единицу).
var work_ticks: int = 0
## Сколько единиц агент добыл на глубине за цикл — по этому числу колония
## решает, кому отдать Снаряжение (docs/00 §7).
var deep_gathered: int = 0

## Троттлинг agent_updated: не чаще раза в секунду на агента.
var last_update_tick: int = -1000
var update_pending: bool = false
## Для черты Трудяга: сколько тиков цикла агент простоял без дела.
var idle_ticks_cycle: int = 0
## Существо пугает агента ОДИН раз за цикл; без флага −10 духа прилетало бы
## каждые десять тиков, пока существо рядом.
var scared_this_cycle: bool = false
## Дух падал до нуля в этом цикле — «отказ спускаться» (docs/00 §6.3).
## Именно латч на цикл, а не проверка «Дух == 0 прямо сейчас»: спека обещает
## отказ НА ЦИКЛ, и отросший на пару единиц Дух не должен его отменять.
var no_descend_cycle: bool = false
## «Болезнь» docs/00 §6.3: Тепло дошло до нуля — скорость ×0.5 ДО ПОЛНОГО
## отогрева. Без флага множитель отпускал при тепле 1, и болезни как
## состояния не существовало (A1.6).
var sick: bool = false

## Расходы за цикл, посчитанные ОДИН раз при спавне: множитель черты может
## быть дробью вроде 24/18, и умножать её каждый тик значило бы копить
## ошибку float в целочисленной по замыслу системе.
var hunger_rate_milli: int = Balance.SATIETY_PER_CYCLE_MILLI
var warmth_rate_milli: int = Balance.WARMTH_PER_CYCLE_MILLI
var warmth_wet_rate_milli: int = Balance.WARMTH_WET_PER_CYCLE_MILLI
var fatigue_rate_milli: int = Balance.FATIGUE_PER_CYCLE_MILLI
var fatigue_rest_milli: int = Balance.FATIGUE_REST_PER_CYCLE_MILLI
var bag_slots: int = Balance.BAG_SLOTS
var drown_limit_ticks: int = int(Balance.DROWN_SEC * Balance.TICKS_PER_SEC)
## Тиков на единицу добычи: базовые 2 с, делённые на работоспособность черт.
var gather_ticks_per_unit: int = int(Balance.GATHER_SEC_PER_UNIT * Balance.TICKS_PER_SEC)

func init_needs() -> void:
	for k: String in NEED_KEYS:
		needs[k] = Balance.NEED_MAX_MILLI
		need_rem[k] = 0
	needs["mood"] = Balance.MOOD_START_MILLI
	needs["fatigue"] = Balance.NEED_MAX_MILLI

## Пересчитывает производные от черт числа. Звать после назначения trait_ids.
func recompute_from_traits() -> void:
	hunger_rate_milli = int(round(float(Balance.SATIETY_PER_CYCLE_MILLI)
		* modifier("hunger_rate_mult")))
	var wm: float = modifier("warmth_rate_mult")
	warmth_rate_milli = int(round(float(Balance.WARMTH_PER_CYCLE_MILLI) * wm))
	warmth_wet_rate_milli = int(round(float(Balance.WARMTH_WET_PER_CYCLE_MILLI) * wm))
	fatigue_rate_milli = int(round(float(Balance.FATIGUE_PER_CYCLE_MILLI)
		* modifier("rest_need_mult")))
	fatigue_rest_milli = int(round(float(Balance.FATIGUE_REST_PER_CYCLE_MILLI)
		* modifier("rest_gain_mult")))
	bag_slots = Balance.BAG_SLOTS + int(modifier("bag_slots_add"))
	var base_drown: float = Balance.DROWN_GEAR_SEC if has_gear else Balance.DROWN_SEC
	drown_limit_ticks = int(modifier("drown_seconds", base_drown)
		* float(Balance.TICKS_PER_SEC))
	gather_ticks_per_unit = maxi(1, int(round(
		Balance.GATHER_SEC_PER_UNIT * float(Balance.TICKS_PER_SEC) / modifier("work_mult"))))

## Свёртка модификаторов по чертам. Правило свёртки задаётся ключом
## (TraitKeys): множители перемножаются, прибавки суммируются, а
## drown_seconds/min_mark ЗАМЕНЯЮТ базовое значение — Ныряльщик держится
## 10 секунд, а не в 10 раз дольше.
func modifier(key: String, default_value: float = -1.0) -> float:
	var fold: String = TraitKeys.fold_of(key)
	match fold:
		"mult":
			var m: float = 1.0
			for tid: String in trait_ids:
				var d: TraitDef = DB.trait_def(tid)
				if d != null and d.modifiers.has(key):
					m *= d.modifiers[key]
			return m
		"add":
			var a: float = 0.0
			for tid2: String in trait_ids:
				var d2: TraitDef = DB.trait_def(tid2)
				if d2 != null and d2.modifiers.has(key):
					a += d2.modifiers[key]
			return a
		"replace":
			for tid3: String in trait_ids:
				var d3: TraitDef = DB.trait_def(tid3)
				if d3 != null and d3.modifiers.has(key):
					return d3.modifiers[key]
			return default_value
	push_error("SimAgent.modifier: ключ '%s' не из TraitKeys" % key)
	return default_value

func has_trait(tid: String) -> bool:
	return trait_ids.has(tid)

# --- Потребности ----------------------------------------------------------

## Изменение за цикл, разложенное по тикам целочисленно: остаток копится
## в need_rem и раз в несколько тиков даёт лишнюю единицу. Полностью
## детерминировано, в отличие от сложения дроби 3000 раз.
func apply_rate(need: String, per_cycle_milli: int) -> void:
	if per_cycle_milli == 0:
		return
	var sign_v: int = signi(per_cycle_milli)
	var mag: int = absi(per_cycle_milli)
	var step: int = mag / Balance.TICKS_PER_CYCLE
	need_rem[need] = int(need_rem[need]) + mag % Balance.TICKS_PER_CYCLE
	if int(need_rem[need]) >= Balance.TICKS_PER_CYCLE:
		need_rem[need] = int(need_rem[need]) - Balance.TICKS_PER_CYCLE
		step += 1
	if step == 0:
		return
	needs[need] = clampi(int(needs[need]) + sign_v * step, 0, Balance.NEED_MAX_MILLI)

func change_need(need: String, delta_milli: int) -> void:
	needs[need] = clampi(int(needs[need]) + delta_milli, 0, Balance.NEED_MAX_MILLI)

func satiety() -> float:
	return float(needs["satiety"]) / 1000.0

func warmth() -> float:
	return float(needs["warmth"]) / 1000.0

func mood() -> float:
	return float(needs["mood"]) / 1000.0

func fatigue() -> float:
	return float(needs["fatigue"]) / 1000.0

func is_alive() -> bool:
	return state != SimTypes.AgentState.DEAD

# --- Котомка --------------------------------------------------------------

func bag_count(item_id: String) -> int:
	var n: int = 0
	for s: Dictionary in bag:
		if str(s["item_id"]) == item_id:
			n += int(s["count"])
	return n

func bag_free_slots() -> int:
	return maxi(0, bag_slots - bag.size())

# --- Сериализация ---------------------------------------------------------

func to_dict() -> Dictionary:
	var needs_out: Dictionary = {}
	var rem_out: Dictionary = {}
	# Обход по const-массиву, а не по словарю: порядок вставки после загрузки
	# может отличаться, а он определяет порядок ключей в сейве.
	for k: String in NEED_KEYS:
		needs_out[k] = int(needs[k])
		rem_out[k] = int(need_rem[k])
	var bag_out: Array = []
	for s: Dictionary in bag:
		bag_out.append(s.duplicate())
	return {
		"id": id, "name": agent_name, "bio": bio_key,
		"traits": trait_ids.duplicate(),
		"state": int(state), "state_ticks": state_ticks,
		"platform": platform_id, "x": x, "target_x": target_x,
		"climb_to": climb_to, "climb_t": climb_t, "facing": facing,
		"path": path.duplicate(), "path_idx": path_idx,
		"path_gv": path_graph_version,
		"intent": int(intent), "goto_platform": goto_platform, "goto_x": goto_x,
		"needs": needs_out, "need_rem": rem_out, "bag": bag_out,
		"wet": wet, "has_gear": has_gear, "submerged": submerged_ticks,
		"heat_ticks": heat_ticks, "warned": drowning_warned,
		"recalled": recalled, "recall_hard": recall_hard,
		"last_update": last_update_tick, "update_pending": update_pending,
		"idle_ticks": idle_ticks_cycle,
		"job_id": job_id, "work_ticks": work_ticks, "deep_gathered": deep_gathered,
		"scared": scared_this_cycle,
		"no_descend": no_descend_cycle,
		"sick": sick,
	}

func from_dict(d: Dictionary) -> void:
	id = int(d["id"])
	agent_name = str(d["name"])
	bio_key = str(d["bio"])
	trait_ids.clear()
	for v: Variant in d.get("traits", []) as Array:
		trait_ids.append(str(v))
	state = int(d["state"]) as SimTypes.AgentState
	state_ticks = int(d["state_ticks"])
	platform_id = int(d["platform"])
	x = float(d["x"])
	target_x = float(d["target_x"])
	climb_to = int(d["climb_to"])
	climb_t = float(d["climb_t"])
	facing = int(d["facing"])
	path.clear()
	for pv: Variant in d.get("path", []) as Array:
		path.append(int(pv))
	path_idx = int(d["path_idx"])
	path_graph_version = int(d["path_gv"])
	intent = int(d["intent"]) as SimTypes.AgentState
	goto_platform = int(d["goto_platform"])
	goto_x = float(d["goto_x"])
	var nd: Dictionary = d["needs"] as Dictionary
	var rd: Dictionary = d["need_rem"] as Dictionary
	for k: String in NEED_KEYS:
		needs[k] = int(nd.get(k, 0))
		need_rem[k] = int(rd.get(k, 0))
	bag.clear()
	for bv: Variant in d.get("bag", []) as Array:
		bag.append(StackUtil.from_json(bv as Dictionary))
	wet = bool(d["wet"])
	has_gear = bool(d["has_gear"])
	submerged_ticks = int(d["submerged"])
	heat_ticks = int(d["heat_ticks"])
	drowning_warned = bool(d["warned"])
	recalled = bool(d["recalled"])
	recall_hard = bool(d["recall_hard"])
	last_update_tick = int(d["last_update"])
	update_pending = bool(d["update_pending"])
	idle_ticks_cycle = int(d["idle_ticks"])
	job_id = int(d.get("job_id", -1))
	work_ticks = int(d.get("work_ticks", 0))
	deep_gathered = int(d.get("deep_gathered", 0))
	scared_this_cycle = bool(d.get("scared", false))
	no_descend_cycle = bool(d.get("no_descend", false))
	sick = bool(d.get("sick", false))
	recompute_from_traits()
