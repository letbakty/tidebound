class_name MaterialRequester
extends RefCounted
## Учёт «сколько материала уже едет» — против дублирования HAUL-задач.
##
## Без него постройка в PLANNED каждый тик видит «не хватает 4 утиля» и просит
## доставку: за десять тиков — десять задач, и шестеро агентов растаскивают
## материалы по кругу (research/17 §6). Тот же учёт нужен трижды: стройка,
## топливо очага и фонаря, входы станций — поэтому он вынесен сюда, а не
## переписан в каждой системе.

## Сколько ещё нужно заказать: требуется − в буфере − уже в пути.
static func missing(need: Dictionary, buffer: Dictionary,
		pending_jobs: Array[int], w: SimWorld) -> Dictionary[String, int]:
	var left: Dictionary[String, int] = {}
	var keys: Array[String] = []
	keys.assign(need.keys())
	keys.sort()                          # детерминированный порядок заказов
	for k: String in keys:
		left[k] = int(need[k]) - int(buffer.get(k, 0))
	for jid: int in pending_jobs:
		var j: Dictionary = w.jobs.jobs.get(jid, {})
		if j.is_empty():
			continue
		var item: String = str(j["item_id"])
		if left.has(item):
			left[item] = int(left[item]) - int(j["n"])
	return left

## Убирает из списка задачи, которых уже нет в пуле. Без этого массив растёт
## вечно и попадает в сейв.
static func prune(pending_jobs: Array[int], w: SimWorld) -> Array[int]:
	var out: Array[int] = []
	for jid: int in pending_jobs:
		if w.jobs.jobs.has(jid):
			out.append(jid)
	return out

## Склад, где лежит нужный предмет. Тай-брейк по меньшему id.
static func source_for(item_id: String, w: SimWorld) -> Dictionary:
	for s: Dictionary in w.storage.storages:
		if w.storage.count_in(int(s["id"]), item_id) > 0:
			return {"kind": "storage", "id": int(s["id"]), "cell": s["cell"]}
	return {}
