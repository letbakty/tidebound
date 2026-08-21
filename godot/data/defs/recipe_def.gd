class_name RecipeDef
extends Resource
## Рецепт станции (docs/00 §9.1).
##
## Активный рецепт (needs_agent) требует агента у станции и идёт work_seconds.
## Пассивный (work_seconds = 0) срабатывает на границе фазы или цикла —
## passive_per задаёт, на какой именно.

@export var id: String = ""
@export var display_key: String = ""
## special постройки, на которой рецепт работает.
@export var station_special: String = ""
@export var inputs: Dictionary[String, int] = {}
@export var outputs: Dictionary[String, int] = {}
## 0 = пассивный рецепт.
@export var work_seconds: float = 0.0
## "cycle" — на границе цикла, "low_phase" — в конце Низкой воды, "" — активный.
@export var passive_per: String = ""
@export var needs_agent: bool = true
@export var unlock_id: String = ""

func work_ticks() -> int:
	return maxi(1, int(work_seconds * float(Balance.TICKS_PER_SEC)))
