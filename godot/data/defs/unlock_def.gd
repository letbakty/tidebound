class_name UnlockDef
extends Resource
## Разблокировка Журнала (docs/00 §11.3). Покупается за очки забегов
## и действует на все последующие забеги.

@export var id: String = ""
@export var display_key: String = ""
@export var desc_key: String = ""
@export var cost: int = 0
## Что открывает: {"building": id} / {"card": id} / {"start_bonus": key} /
## {"draft_size": 4} / {"upgrade": key}.
@export var grants: Dictionary = {}
