class_name SimProbe
extends RefCounted
## Прогон до условия, снимки по тикам, пошаговое исполнение.
## Переносить в res://tests/sim_probe.gd.
##
## Зачем: разбор docs/BUG-salt-chain.md стоил пяти прогонов с ручной печатью.
## run_until отвечает на вопрос «когда впервые случится X» за один прогон
## (research/43 §3.3).

## Прогоняет мир, пока предикат не станет истинным. Возвращает тик или −1.
##
## ⚠️ Условие проверяется ПОСЛЕ тика: «соль появилась» ловится в тот же тик,
## когда появилась, а не через один.
## ⚠️ events_out чистится: иначе за 20 000 тиков накопятся сотни тысяч SimEvent.
static func run_until(world: Object, cond: Callable, max_ticks: int = 60000) -> int:
	for i: int in max_ticks:
		world.call("tick")
		(world.get("events_out") as Array).clear()
		if bool(cond.call(world)):
			return int(world.get("clock").call("total_ticks"))
	return -1

## Прогон с остановкой на первой ошибке движка. Возвращает тик или −1.
## Работает в паре с ErrorGuard: ловит класс дефектов вроде buffer_take,
## где тесты зелёные, а в логе сотни SCRIPT ERROR.
static func run_until_error(world: Object, max_ticks: int = 60000) -> int:
	var base: int = ErrorGuard.errors
	return run_until(world, func(_w: Object) -> bool:
		return ErrorGuard.errors > base, max_ticks)

## Снимки на перечисленных тиках -> файлы в dir. Ровно та таблица,
## которая в BUG-salt-chain.md собиралась руками.
## ⚠️ Пишет в user://, не в res://: дампы большие и в git им не место.
static func dump_at(world: Object, ticks: Array[int], dir: String = "user://dumps/") -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var want: Array[int] = ticks.duplicate()
	want.sort()
	var idx: int = 0
	var limit: int = want[want.size() - 1]
	while idx < want.size():
		var now: int = int(world.get("clock").call("total_ticks"))
		if now >= want[idx]:
			_write(world, "%sdump_%06d.json" % [dir, now])
			idx += 1
			continue
		if now > limit:
			break
		world.call("tick")
		(world.get("events_out") as Array).clear()

static func _write(world: Object, path: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("SimProbe: не записан %s" % path)
		return
	# indent + sort_keys: файл должен читаться глазами и диффиться построчно.
	f.store_string(JSON.stringify(world.call("to_dict"), "\t", true, true))
	f.close()

## Пошагово: тик + дифф с предыдущим состоянием. Для «что изменилось за один тик».
static func step_diff(world: Object, n: int = 1, full: bool = false) -> String:
	var before: Dictionary = SimDump.flat(world)
	for i: int in n:
		world.call("tick")
		(world.get("events_out") as Array).clear()
	return SimDump.diff_text(before, SimDump.flat(world), full)

# --- Готовые предикаты ----------------------------------------------------
# Те, что понадобятся в FIX-review чаще всего.

static func p_agent_died(from_count: int) -> Callable:
	return func(w: Object) -> bool:
		return int(w.get("agents").call("alive_count")) < from_count

static func p_item_reaches(item_id: String, n: int) -> Callable:
	return func(w: Object) -> bool:
		return int((w.get("storage").call("totals") as Dictionary).get(item_id, 0)) >= n

static func p_phase(phase: int, cycle: int) -> Callable:
	return func(w: Object) -> bool:
		var c: Object = w.get("clock")
		return int(c.get("phase")) == phase and int(c.get("cycle")) == cycle
