extends RefCounted
## Приёмка оркестратора Game: автопауза, немедленная остановка тика,
## переэмиссия состояния после загрузки. Сьют уровня автолоада, а не sim:
## именно на этой границе жили SIM-04, SIM-10 и REL-04.

const SEED: int = 4242

static func _fresh_run() -> void:
	Game.cmd_new_run(SEED)

static func _cleanup() -> void:
	Game.cmd_set_speed(0)
	SaveService.delete_run()

# --- Автопауза ------------------------------------------------------------

## SIM-04 · скорость не падает на ×1 после каждого цикла.
##
## На границе цикла в одном тике эмитятся cycle_ended и draft_ready, и обе
## ветки просили паузу. Пока «прежняя скорость» была одним полем, вторая
## запись затирала первую нулём, и resume возвращал ×1 — за 12 циклов
## одиннадцать молчаливых понижений.
static func test_nested_pause_keeps_speed(t: TestCtx) -> void:
	_fresh_run()
	Game.cmd_set_speed(3)
	t.check_eq(Game.speed, 3, "игрок выбрал ×3")
	Game.push_pause()                       # итог цикла
	t.check_eq(Game.speed, 0, "первая пауза остановила время")
	Game.push_pause()                       # драфт поверх итога
	t.check_eq(Game.pause_depth(), 2, "две сущности просят паузу")
	Game.pop_pause()
	t.check_eq(Game.speed, 0, "нижнее окно ещё открыто — время стоит")
	Game.pop_pause()
	t.check_eq(Game.speed, 3, "выбранная скорость вернулась, а не ×1")
	_cleanup()

## Полная граница цикла: cycle_ended и draft_ready в одном тике.
static func test_cycle_boundary_keeps_speed(t: TestCtx) -> void:
	_fresh_run()
	Game.cmd_set_speed(3)
	_run_to_cycle_boundary(t)
	t.check_eq(Game.speed, 0, "автопауза на границе цикла сработала")
	while Game.pause_depth() > 0:
		Game.pop_pause()
	t.check_eq(Game.speed, 3, "после закрытия всех окон снова ×3")
	_cleanup()

## Прогоняет мир до ближайшей границы цикла через сам Game.
static func _run_to_cycle_boundary(t: TestCtx) -> void:
	var guard: int = 0
	while Game.speed != 0 and guard < Balance.TICKS_PER_CYCLE * 2:
		Game._physics_process(0.1)
		guard += 1
	t.check(guard < Balance.TICKS_PER_CYCLE * 2, "граница цикла достигнута")
