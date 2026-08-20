class_name ItemDef
extends Resource
## Предмет как данные. Таблица-источник — docs/00 §7.
##
## Деф иммутабелен в рантайме: load() отдаёт закэшированный инстанс, и правка
## поля изменит предмет для всех и до конца процесса, включая следующие тесты
## (research/14 §2). Всё изменяемое живёт в стаках StorageSystem.

@export var id: String = ""
@export var display_key: String = ""
@export var stack_size: int = 1
## 0 = не портится. Считается в циклах.
@export var spoil_cycles: int = 0
## Что делает с предметом затопление склада (docs/00 §7).
@export var flood_rule: SimTypes.FloodRule = SimTypes.FloodRule.OK
@export var ship_points: int = 0
## Пусто до этапа 18: код, который её читает, обязан иметь фолбэк.
@export var icon: Texture2D = null
