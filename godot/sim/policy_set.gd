class_name PolicySet
extends RefCounted
## Шесть ползунков 0..3 — единственный постоянный рычаг игрока (docs/00 §6.6).
## Прямых приказов агентам нет: игрок задаёт правила, а не задачи.

var values: Dictionary[int, int] = {}

func _init() -> void:
	reset()

func reset() -> void:
	values.clear()
	for p: int in SimTypes.POLICY_ORDER:
		values[p] = int(Balance.POLICY_DEFAULTS[p])

func get_value(policy: int) -> int:
	return int(values.get(policy, 0))

func set_value(policy: int, value: int) -> bool:
	if not values.has(policy):
		push_error("PolicySet: нет политики %d" % policy)
		return false
	var v: int = clampi(value, 0, 3)
	if v == int(values[policy]):
		return false
	values[policy] = v
	return true

## Какая политика управляет классом работы (docs/00 §6.6).
## РЕШЕНИЕ: STATION спека отдельной политике не назначает — вешаем на
## Заготовку: работа у станции это то же снабжение колонии.
static func policy_for_class(job_class: int) -> int:
	match job_class:
		SimTypes.JobClass.GATHER, SimTypes.JobClass.HAUL, SimTypes.JobClass.STATION:
			return SimTypes.Policy.SUPPLY
		SimTypes.JobClass.BUILD:
			return SimTypes.Policy.BUILD
		SimTypes.JobClass.REPAIR:
			return SimTypes.Policy.REPAIR
		SimTypes.JobClass.REST, SimTypes.JobClass.EAT:
			return SimTypes.Policy.REST
	return SimTypes.Policy.SUPPLY

## Вес класса. 0 — не «низкий приоритет», а ЗАПРЕТ: класс отбрасывается
## до расчёта скоринга (research/16 §1).
func weight_for_class(job_class: int) -> float:
	return Balance.POLICY_WEIGHT[get_value(policy_for_class(job_class))]

func to_dict() -> Dictionary:
	var out: Dictionary = {}
	# Ключи JSON — строки; обход по const-массиву, а не по словарю.
	for p: int in SimTypes.POLICY_ORDER:
		out[str(p)] = int(values[p])
	return out

func from_dict(d: Dictionary) -> void:
	for p: int in SimTypes.POLICY_ORDER:
		values[p] = clampi(int(d.get(str(p), Balance.POLICY_DEFAULTS[p])), 0, 3)
