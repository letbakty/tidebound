class_name TraitDef
extends Resource
## Черта агента: набор пар «ключ модификатора → значение» (docs/00 §6.4).
## Неиспользуемые ключи в словаре просто отсутствуют.
## Допустимые ключи и правило свёртки каждого — TraitKeys.

@export var id: String = ""
@export var display_key: String = ""
@export var desc_key: String = ""
@export var modifiers: Dictionary[String, float] = {}
