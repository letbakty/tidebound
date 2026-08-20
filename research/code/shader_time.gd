## Драйвер глобального шейдер-uniform `sim_time`.
##
## ЗАЧЕМ: встроенный TIME в Godot 4.7 НЕ останавливается на паузе (подтверждено
## документацией, см. research/00-godot-4.7-api-facts.md §5). Приёмка этапа 18
## требует «на паузе шейдер останавливается». Значит все шейдеры проекта читают
## `global uniform float sim_time`, а не TIME.
##
## Куда класть: этот код встраивается в autoload/game.gd (Game уже владеет
## тиком и аккумулятором). Отдельная нода не нужна — здесь он выделен, чтобы
## агент видел готовый фрагмент.
##
## Требует записи в Project Settings:
##   shader_globals/sim_time = { "type": "float", "value": 0.0 }
## (Project → Project Settings → Shader Globals → добавить `sim_time` типа float)
extends Node

const SIM_TIME_UNIFORM: StringName = &"sim_time"

# --- фрагмент для game.gd ---------------------------------------------------
#
#	const TICKS_PER_SEC: int = 10
#	var _accum: float = 0.0
#	var speed: int = 1
#
#	func _physics_process(delta: float) -> void:
#		if speed == 0 or world == null:
#			_push_shader_time()   # на паузе всё равно пушим — значение не меняется
#			return
#		_accum += delta * float(speed)
#		var step: float = 1.0 / float(TICKS_PER_SEC)
#		while _accum >= step:
#			_accum -= step
#			world.tick()
#			_flush_events()
#		_push_shader_time()
#
#	## Секунды симуляции с дробной частью тика: кромка воды и волна двигаются
#	## плавно на 60 fps, хотя сим тикает 10 раз в секунду. На паузе стоит.
#	func sim_seconds() -> float:
#		return float(world.tick_count) / float(TICKS_PER_SEC) + _accum
#
#	func _push_shader_time() -> void:
#		RenderingServer.global_shader_parameter_set(&"sim_time", sim_seconds())
#
# ---------------------------------------------------------------------------

## ЗАМЕЧАНИЕ ПО ТОЧНОСТИ: забег = 12 циклов × 300 с = 3600 с максимум.
## float32 на 3600.0 держит шаг ~0.00024 с — для sin() в шейдере достаточно,
## обёртка по модулю не нужна. Если появятся забеги 16/20 циклов (docs/00 §17,
## Release) — добавить wrap: sim_seconds() % 3600.0, один незаметный скачок фазы.

## ПРОВЕРКА НА ЭТАПЕ 18: поставить игру на паузу на подъёме воды в HIGH.
## Кромка, пена, рябь и дождь должны замереть полностью. Если что-то шевелится —
## в этом шейдере остался TIME.
