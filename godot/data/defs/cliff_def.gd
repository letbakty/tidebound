class_name CliffDef
extends Resource
## Карта утёса: ярусы, площадки, стартовые лестницы, слоты депозитов.
## Задаётся вручную в .tres (docs/00 §3.1 — не процедурно).
##
## Деф иммутабелен в рантайме: это shared-инстанс из кэша ResourceLoader.
## Всё изменяемое (сколько осталось в депозите, какие лестницы построены)
## живёт в sim/terrain.gd (docs/02 §5).

@export var id: String = ""
@export var width: int = 48
@export var height: int = 45

## Площадки-узлы графа: {"mark": int, "x0": int, "x1": int} включительно.
## Одна площадка на отметку. Соседние отметки перекрываются по x — там,
## где перекрытие, можно поставить лестницу.
@export var platforms: Array[Dictionary] = []

## Лестницы на старте забега: {"x": int, "mark_top": int}.
## Лестница занимает колонку x и связывает площадки mark_top и mark_top−1.
@export var start_ladders: Array[Dictionary] = []

## Слоты депозитов: {"kind": String, "mark": int, "x": int}.
## kind — ключ из Terrain.DEPOSIT_KINDS.
@export var deposit_slots: Array[Dictionary] = []

## Клетка, вокруг которой начинается колония (камера стартует здесь).
@export var spawn_cell: Vector2i = Vector2i.ZERO
## Стартовый склад забега (docs/00 §11.1). Постройкой станет на этапе 07.
@export var start_storage_cell: Vector2i = Vector2i.ZERO

func platform_for_mark(mark: int) -> Dictionary:
	for p: Dictionary in platforms:
		if int(p.get("mark", 9999)) == mark:
			return p
	return {}
