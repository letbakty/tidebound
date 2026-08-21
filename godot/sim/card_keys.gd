class_name CardKeys
extends RefCounted
## Допустимые ключи эффектов карт. Держим списком, а не комментарием:
## опечатка в ключе даёт молчаливый ноль-эффект, который всплывёт через
## несколько этапов (research/14 §1.1). Валидатор в tests/test_data.gd
## падает на любом ключе не отсюда.

const ALL: Array[String] = [
	"low_plateau_add",     # сдвиг плато отлива (−2 = «Глубокий заход»)
	"low_time_mult",       # длительность фазы LOW
	"haul_speed_mult",     # скорость агента с грузом
	"bag_slots_add",       # слоты котомки
	"recall_earlier_sec",  # авто-возврат раньше на N секунд
	"drown_bonus_sec",     # запас времени под водой
	"gather_speed_mult",   # скорость добычи
	"next_spring_add",     # следующая сизигия выше на N отметок
	"cancel_visit",        # Приход этого цикла отменён
	"mark_relic",          # на дне помечена гарантированная реликвия
]

static func is_known(key: String) -> bool:
	return ALL.has(key)
