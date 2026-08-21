class_name CardDef
extends Resource
## План вылазки — карта-модификатор одного цикла (docs/00 §10).
## Эффект живёт ровно один цикл и сбрасывается на его конце.

@export var id: String = ""
@export var display_key: String = ""
@export var desc_key: String = ""
## "base" — всегда в пуле, "rare" — только после разблокировки.
@export var rarity: String = "base"
@export var unlock_id: String = ""
## Фикс-ключи — см. CardKeys. Опечатка в ключе даёт молчаливый ноль-эффект.
@export var effects: Dictionary[String, float] = {}
