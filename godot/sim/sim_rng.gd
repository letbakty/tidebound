class_name SimRNG
extends RefCounted
## Единственный источник случайности в sim/. Глобальные randi()/randf()
## запрещены: они сидируются системным временем и убивают детерминизм
## (research/11 §1).
##
## В сейв уходит state, а НЕ seed: seed сбрасывает последовательность в начало,
## и после загрузки мир пошёл бы другим путём (research/11 §9).

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var seed_value: int = 0

func setup(p_seed: int) -> void:
	seed_value = p_seed
	_rng.seed = p_seed

func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)

func randf() -> float:
	return _rng.randf()

func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)

## Случайный элемент массива. Пустой массив — не ошибка вызывающего кода,
## а сигнал о пустом пуле: возвращаем null и шумим в лог.
func pick(arr: Array) -> Variant:
	if arr.is_empty():
		push_warning("SimRNG.pick: пустой массив")
		return null
	return arr[_rng.randi_range(0, arr.size() - 1)]

func chance(p: float) -> bool:
	return _rng.randf() < p

func get_state() -> int:
	return _rng.state

func set_state(s: int) -> void:
	_rng.state = s

## РЕШЕНИЕ: seed и state пишем СТРОКАМИ, а не числами.
## Это полные 64-битные значения, а JSON.parse отдаёт числа как double —
## мантисса 53 бита, младшие биты теряются молча. На проверке было
## −5470398187538053127 → −5470398187538053120: после загрузки генератор
## пошёл бы другой последовательностью. Строка переживает round-trip точно.
func to_dict() -> Dictionary:
	return {"seed": str(seed_value), "state": str(get_state())}

func from_dict(d: Dictionary) -> void:
	seed_value = str(d.get("seed", "0")).to_int()
	_rng.seed = seed_value
	set_state(str(d.get("state", "0")).to_int())
