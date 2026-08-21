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

# --- Переэмиссия после загрузки ------------------------------------------

## REL-04 · выход во время драфта не теряет драфт.
##
## run_state.draft сохраняется корректно, но rebroadcast_state не эмитил
## draft_ready: после «Продолжить» панель выбора не появлялась, автопауза
## не вставала, и на границе Спада auto_pick_if_needed брал первую карту
## за игрока (docs/03 §8).
static func test_draft_survives_save_load(t: TestCtx) -> void:
	Game.cmd_new_run(SEED)
	Game.cmd_set_speed(1)
	Game._physics_process(0.2)                    # первый тик отдаёт драфт
	var draft: Array[String] = Game.world.run_state.draft.duplicate()
	t.check(not draft.is_empty(), "драфт собран")
	t.check(not Game.world.run_state.drafted_this_cycle, "карта ещё не выбрана")
	Game.cmd_save()
	t.check(SaveService.has_valid_save(), "забег сохранён прямо на драфте")

	var got: Array[String] = []
	var seen: Array[bool] = [false]
	var cb: Callable = func(ids: Array[String]) -> void:
		seen[0] = true
		got.assign(ids)
	Events.draft_ready.connect(cb)
	Game.world = null                             # как будто игра перезапущена
	t.check(Game.cmd_load(), "забег загружен")
	Events.draft_ready.disconnect(cb)

	t.check(seen[0], "draft_ready прозвучал заново")
	t.check_eq(got, draft, "и с теми же картами")
	t.check(Game.pause_depth() > 0, "автопауза драфта встала")
	while Game.pause_depth() > 0:
		Game.pop_pause()
	_cleanup()

# --- Профиль --------------------------------------------------------------

## Профиль игрока — общий файл, а не тестовый. Снимаем и возвращаем как было.
static func _profile_text() -> String:
	if not FileAccess.file_exists(Meta.PROFILE_PATH):
		return ""
	return FileAccess.get_file_as_string(Meta.PROFILE_PATH)

static func _write_profile(text: String) -> void:
	if text.is_empty():
		if FileAccess.file_exists(Meta.PROFILE_PATH):
			DirAccess.remove_absolute(
				ProjectSettings.globalize_path(Meta.PROFILE_PATH))
		return
	var f := FileAccess.open(Meta.PROFILE_PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()

## REL-02 · профиль чужой версии не обнуляется молча.
##
## load_profile возвращал false, оставляя поля дефолтными, но файл на диске
## не трогал — и первый же mark_dirty (конец забега, покупка) перезаписывал
## его нулями. Игрок терял весь Журнал без предупреждения и без копии.
static func test_incompatible_profile_is_backed_up(t: TestCtx) -> void:
	var saved: String = _profile_text()
	var bak: String = "%s.v999.bak" % Meta.PROFILE_PATH.get_basename()
	_write_profile('{"version": 999, "points_total": 777}')

	t.check(not Meta.load_profile(), "профиль чужой версии не загружается")
	t.check(not FileAccess.file_exists(Meta.PROFILE_PATH),
		"файл убран с дороги: следующий save_profile его уже не затрёт")
	t.check(FileAccess.file_exists(bak), "и лежит копией рядом")
	var kept: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(bak)) as Dictionary
	t.check_eq(int(kept.get("points_total", 0)), 777,
		"копия — тот самый файл, а не пустышка")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(bak))
	_write_profile(saved)
	Meta.load_profile()

## REL-03 · профиль пишется на выходе вместе с забегом.
##
## _notification сохранял только забег, а Meta полагалась на дебаунс в
## _process — кадра для которого после quit() может уже не быть.
static func test_quit_saves_profile(t: TestCtx) -> void:
	var saved: String = _profile_text()
	_write_profile("")
	t.check(not FileAccess.file_exists(Meta.PROFILE_PATH), "профиля на диске нет")
	SaveService._save_all()
	t.check(FileAccess.file_exists(Meta.PROFILE_PATH),
		"выход из игры записал профиль, а не только забег")
	_write_profile(saved)
	Meta.load_profile()

## Прогоняет мир до ближайшей границы цикла через сам Game.
static func _run_to_cycle_boundary(t: TestCtx) -> void:
	var guard: int = 0
	while Game.speed != 0 and guard < Balance.TICKS_PER_CYCLE * 2:
		Game._physics_process(0.1)
		guard += 1
	t.check(guard < Balance.TICKS_PER_CYCLE * 2, "граница цикла достигнута")
