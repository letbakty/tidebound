extends Node
## Оркестратор: владеет SimWorld, тикает его фиксированным шагом, транслирует
## events_out в сигналы Events и принимает команды игрока cmd_* (docs/02 §3.3, §4).
##
## Наполняет этап 01. Здесь — только каркас, чтобы ссылки компилировались.

const TICKS_PER_SEC: int = 10
const STEP: float = 1.0 / TICKS_PER_SEC
## Защита от «спирали смерти»: при лаге не пытаться догнать всё разом (research/11 §3).
const MAX_TICKS_PER_FRAME: int = 12

## 0 = пауза. Паузу делаем скоростью, get_tree().paused не трогаем.
var speed: int = 0

func _physics_process(_delta: float) -> void:
	# Этап 01: аккумулятор и world.tick().
	pass
