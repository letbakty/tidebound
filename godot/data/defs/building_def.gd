class_name BuildingDef
extends Resource
## Постройка как данные (docs/00 §8). Различия построек живут ЗДЕСЬ,
## а не спецкейсами в коде: склад переживает два шторма не потому, что он
## склад, а потому что у него hp = 2.

@export var id: String = ""
@export var display_key: String = ""
## Ширина × высота в тайлах.
@export var size: Vector2i = Vector2i.ONE
@export var cost: Dictionary[String, int] = {}
@export var min_mark: int = Balance.BOTTOM_MARK
@export var max_mark: int = Balance.TOP_MARK
## Что делает с постройкой затопление: OK — работает под водой,
## DISABLED — не работает, пока в воде.
@export var flood_rule: SimTypes.FloodRule = SimTypes.FloodRule.OK
@export var storm_breaks: bool = false
## Сушила срывает штормом на ЛЮБОЙ отметке, а не только ниже +3.
@export var storm_always: bool = false
@export var hp: int = 1
## Маркер логики: "ladder", "storage", "hearth", "lantern", "sluice", "dryer",
## "evaporator", "winch", "bunk", "raincatcher", "forge", "workbench",
## "saltery", "ropery", "platform", "condenser", "weir".
@export var special: String = ""
## "" = доступна сразу; иначе id разблокировки Журнала.
@export var unlock_id: String = ""
## Можно ли её ставить игроку. Стартовые постройки без цены (Дождесборник)
## строиться не могут: пустая смета даёт стройку за один тик из ничего.
@export var buildable: bool = true

## Суммарная стоимость в единицах — по ней считается время стройки.
func cost_units() -> int:
	var n: int = 0
	for k: String in cost:
		n += int(cost[k])
	return n
