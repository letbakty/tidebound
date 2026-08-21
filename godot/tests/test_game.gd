extends RefCounted
## Приёмка оркестратора Game: автопауза, немедленная остановка тика,
## переэмиссия состояния после загрузки. Сьют уровня автолоада, а не sim:
## именно на этой границе жили SIM-04, SIM-10 и REL-04.

const SEED: int = 4242

## Новый забег с уже разобранным стартовым драфтом. Без этого первый же тик
## отдаёт draft_ready и ставит автопаузу — любой тест «до границы цикла»
## останавливался бы на первом тике, ничего не проверив.
static func _fresh_run() -> void:
	Game.cmd_new_run(SEED)
	Game.cmd_set_speed(1)
	Game._physics_process(0.2)
	while Game.pause_depth() > 0:
		Game.pop_pause()
	Game._accum = 0.0

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

## SIM-10 · автопауза останавливает время немедленно, а не через 11 тиков.
##
## speed проверялся один раз на входе в _physics_process; cmd_set_speed(0)
## из _flush_events цикл не прерывал, и при ×3 после конца цикла мир убегал
## вперёд — отчёт показывал одно, картинка другое.
static func test_autopause_stops_tick_immediately(t: TestCtx) -> void:
	_fresh_run()
	Game.cmd_set_speed(3)
	var c: SimClock = Game.world.clock
	# Два тика до конца Высокой воды, то есть до конца цикла.
	c.phase = SimTypes.Phase.HIGH
	c.tick_in_phase = c.phase_len(SimTypes.Phase.HIGH) - 2
	Game._accum = 0.0
	var before: int = c.total_ticks()
	# Кадра с запасом хватило бы на 12 тиков (MAX_TICKS_PER_FRAME).
	Game._physics_process(1.0)
	t.check_eq(Game.speed, 0, "граница цикла поставила автопаузу")
	t.check_eq(Game.world.clock.total_ticks() - before, 2,
		"мир встал ровно на границе, а не убежал вперёд")
	while Game.pause_depth() > 0:
		Game.pop_pause()
	_cleanup()

## Прогоняет мир до ближайшей границы цикла через сам Game.
static func _run_to_cycle_boundary(t: TestCtx) -> void:
	var guard: int = 0
	while Game.speed != 0 and guard < Balance.TICKS_PER_CYCLE * 2:
		Game._physics_process(0.1)
		guard += 1
	t.check(guard < Balance.TICKS_PER_CYCLE * 2, "граница цикла достигнута")
