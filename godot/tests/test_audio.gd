extends RefCounted
## Приёмка этапа 17: кроссфейд, дакинг, расписание колокола, полнота каталога.
##
## Автолоадов в headless-раннере нет, звуковой карты тоже: проверяем ровно то,
## что можно проверить без них — арифметику (она вынесена в статические функции)
## и согласованность каталога с файлами на диске и с генератором заглушек.

const AUDIO_PATH: String = "res://autoload/audio_service.gd"
const GEN_PATH: String = "res://tools/gen_placeholder_sfx.gd"
const EVENTS_PATH: String = "res://autoload/events.gd"
const SFX_DIR: String = "res://assets/sfx/"
const MUSIC_DIR: String = "res://assets/music/"

static func _audio() -> GDScript:
	return load(AUDIO_PATH) as GDScript

# --- Вертикальный кроссфейд -----------------------------------------------

## Равномощностный, а не линейный: сумма энергий постоянна на всей высоте.
## При линейном в середине провал ≈3 дБ — слышно как «дырка» при прокрутке.
static func test_ambient_crossfade_is_constant_power(t: TestCtx) -> void:
	var a: GDScript = _audio()
	for i: int in 19:
		var mark: float = lerpf(8.0, -14.0, float(i) / 18.0)
		var g: Vector2 = a.call("ambient_gains", mark)
		t.check_approx(g.x * g.x + g.y * g.y, 1.0, 0.001,
			"на отметке %.1f сумма энергий постоянна" % mark)
		t.check(g.x >= 0.0 and g.y >= 0.0, "громкости неотрицательны")

## Смешивание — только в средней трети: наверху слышен верх, внизу низ.
## Без этого оба слоя слышны везде и ни один не читается.
static func test_ambient_layers_are_separated(t: TestCtx) -> void:
	var a: GDScript = _audio()
	var top: Vector2 = a.call("ambient_gains", 6.0)
	var bottom: Vector2 = a.call("ambient_gains", -12.0)
	t.check(top.x > 0.99 and top.y < 0.01, "наверху звучит только верхний слой")
	t.check(bottom.y > 0.99 and bottom.x < 0.01, "на дне — только нижний")
	var mid: Vector2 = a.call("ambient_gains", -3.0)
	t.check_approx(mid.x, mid.y, 0.05, "на середине слои равны")
	# Монотонность: при движении вниз верх не может стать громче.
	var prev: float = 2.0
	for i: int in 30:
		var g: Vector2 = a.call("ambient_gains", lerpf(6.0, -12.0, float(i) / 29.0))
		t.check(g.x <= prev + 0.0001, "верхний слой не растёт при спуске")
		prev = g.x

## Камера выше верха и ниже дна карты не должна ломать микс.
static func test_ambient_clamped_outside_map(t: TestCtx) -> void:
	var a: GDScript = _audio()
	var above: Vector2 = a.call("ambient_gains", 99.0)
	var below: Vector2 = a.call("ambient_gains", -99.0)
	t.check_approx(above.x, 1.0, 0.001, "выше карты — верхний слой на полной")
	t.check_approx(below.y, 1.0, 0.001, "ниже карты — нижний слой на полной")

# --- Громкости ------------------------------------------------------------

## Ноль — это тишина, а не −80 дБ: на технике −80 дБ всё ещё слышно.
static func test_zero_gain_is_silence(t: TestCtx) -> void:
	var a: GDScript = _audio()
	var floor_db: float = float(a.get("WATER_FLOOR_DB"))
	t.check_eq(float(a.call("gain_to_db", 0.0)), floor_db, "ноль уходит в пол")
	t.check_eq(float(a.call("gain_to_db", -1.0)), floor_db, "мусор тоже")
	t.check_approx(float(a.call("gain_to_db", 1.0)), 0.0, 0.001,
		"единица — это 0 дБ")
	t.check(float(a.call("gain_to_db", 0.5)) < -5.0,
		"половина громкости — это около −6 дБ, а не −0.5")

## Шум подъёма: стоячая вода молчит, быстрый подъём — на полной.
static func test_water_noise_follows_speed(t: TestCtx) -> void:
	var a: GDScript = _audio()
	t.check_eq(float(a.call("water_noise_db", 0.0)), float(a.get("WATER_FLOOR_DB")),
		"стоячая вода молчит")
	t.check_approx(float(a.call("water_noise_db", 99.0)), 0.0, 0.001,
		"скорость выше потолка не делает звук громче потолка")
	var prev: float = -100.0
	for i: int in 10:
		var db: float = float(a.call("water_noise_db", float(i) * 0.06))
		t.check(db >= prev, "громкость не падает при росте скорости")
		prev = db

## Всплеск — на ярус, а не на каждое изменение уровня.
static func test_splash_only_on_mark_crossing(t: TestCtx) -> void:
	var a: GDScript = _audio()
	t.check(bool(a.call("crossed_mark_up", -3.2, -2.9)), "перешли отметку −3")
	t.check(not bool(a.call("crossed_mark_up", -3.2, -3.1)),
		"внутри яруса всплеска нет")
	t.check(not bool(a.call("crossed_mark_up", -2.9, -3.2)),
		"на спаде воды всплеска нет")
	t.check(not bool(a.call("crossed_mark_up", -3.0, -3.0)),
		"стоячая вода не плещет")

# --- Колокол и дакинг -----------------------------------------------------

## Ровно три удара, с интервалом, каждый следующий чуть ниже и тише.
static func test_bell_is_three_strikes(t: TestCtx) -> void:
	var a: GDScript = _audio()
	var schedule: Array = a.call("bell_schedule")
	t.check_eq(schedule.size(), 3, "три удара, не два и не четыре")
	var gap: float = float(a.get("BELL_GAP_SEC"))
	for i: int in schedule.size():
		var strike: Array = schedule[i] as Array
		t.check_approx(float(strike[0]), float(i) * gap, 0.001,
			"удар %d приходит вовремя" % i)
		if i == 0:
			continue
		var prev: Array = schedule[i - 1] as Array
		t.check(float(strike[1]) < float(prev[1]), "питч следующего удара ниже")
		t.check(float(strike[2]) < float(prev[2]), "и сам удар тише")
	# Три удара должны уложиться в фазу Сигнала, иначе колокол зазвучит
	# уже на Высокой воде.
	var last: Array = schedule[schedule.size() - 1] as Array
	var signal_sec: float = float(int(Balance.PHASE_TICKS[SimTypes.Phase.SIGNAL])) \
		/ float(Balance.TICKS_PER_SEC)
	t.check(float(last[0]) < signal_sec, "вся серия укладывается в фазу Сигнала")

## Два дакинга подряд не «запоминают» уже пониженную базу: смещение всегда
## возвращается в ноль, а базу шины берём из настроек, а не из самой шины.
static func test_duck_returns_to_zero(t: TestCtx) -> void:
	var a: GDScript = _audio()
	var attack: float = float(a.get("DUCK_ATTACK_SEC"))
	var release: float = float(a.get("DUCK_RELEASE_SEC"))
	var hold: float = 2.0
	var depth: float = -12.0
	t.check_eq(float(a.call("duck_offset_db", 0.0, hold, depth)), 0.0,
		"до начала смещения нет")
	t.check_approx(float(a.call("duck_offset_db", attack * 0.5, hold, depth)),
		depth * 0.5, 0.01, "спад линейный")
	t.check_eq(float(a.call("duck_offset_db", attack + hold * 0.5, hold, depth)),
		depth, "на удержании — полная глубина")
	t.check_eq(float(a.call("duck_offset_db", attack + hold + release, hold, depth)),
		0.0, "после возврата смещение ровно ноль")
	t.check_eq(float(a.call("duck_offset_db", 99.0, hold, depth)), 0.0,
		"и спустя минуту тоже ноль")

## Музыка по фазе: спокойная на Отливе и Низкой, тревожная с Сигнала.
static func test_music_follows_phase(t: TestCtx) -> void:
	var a: GDScript = _audio()
	var calm: int = int(a.call("music_for_phase", SimTypes.Phase.EBB))
	t.check_eq(int(a.call("music_for_phase", SimTypes.Phase.LOW)), calm,
		"Отлив и Низкая — одно состояние")
	var tense: int = int(a.call("music_for_phase", SimTypes.Phase.SIGNAL))
	t.check_eq(int(a.call("music_for_phase", SimTypes.Phase.HIGH)), tense,
		"Сигнал и Высокая — одно состояние")
	t.check(calm != tense, "и эти состояния разные")
	t.check_eq(str(a.call("music_file", tense)), "music_tense.wav",
		"тревожное состояние берёт свой файл")

# --- Каталог --------------------------------------------------------------

## Каждый id из каталога лежит на диске. Молчащий звук — самый дорогой дефект
## этапа: он не падает, не логируется и замечается через месяц.
static func test_every_sound_id_has_a_file(t: TestCtx) -> void:
	var a: GDScript = _audio()
	for id: String in _ids(a, "SFX_IDS") + _ids(a, "UI_IDS") + _ids(a, "LOOP_IDS"):
		t.check(ResourceLoader.exists(SFX_DIR + id + ".wav"),
			"нет файла assets/sfx/%s.wav" % id)
	for id: String in _ids(a, "MUSIC_IDS"):
		t.check(ResourceLoader.exists(MUSIC_DIR + id + ".wav"),
			"нет файла assets/music/%s.wav" % id)

## Генератор заглушек и каталог сервиса обязаны совпадать: иначе перегенерация
## тихо оставит один из звуков без файла.
static func test_generator_matches_catalog(t: TestCtx) -> void:
	var a: GDScript = _audio()
	var gen: GDScript = load(GEN_PATH) as GDScript
	var made: Array[String] = []
	for row: Variant in (gen.get("TONES") as Array) + (gen.get("LOOPS") as Array) \
			+ (gen.get("MUSIC") as Array):
		made.append(str((row as Array)[0]))
	var need: Array[String] = _ids(a, "SFX_IDS") + _ids(a, "UI_IDS") \
		+ _ids(a, "LOOP_IDS") + _ids(a, "MUSIC_IDS")
	for id: String in need:
		t.check(made.has(id), "генератор не делает %s" % id)
	for id: String in made:
		t.check(need.has(id), "генератор делает лишний файл %s" % id)

## Плейсхолдеры не щёлкают: огибающая обязана приводить хвост к нулю.
## Читаем сам .wav с диска, а не импортированный ресурс: импортёр отдаёт
## сжатый поток, и «последний семпл» в нём — уже не наш последний семпл.
static func test_placeholders_do_not_click(t: TestCtx) -> void:
	var a: GDScript = _audio()
	for id: String in _ids(a, "SFX_IDS") + _ids(a, "UI_IDS"):
		var pcm: PackedByteArray = _pcm(SFX_DIR + id + ".wav")
		t.check(pcm.size() > 32, "%s не пустой" % id)
		if pcm.size() < 2:
			continue
		var last: int = pcm.decode_s16(pcm.size() - 2)
		t.check(absi(last) < 400, "%s обрывается на тишине (%d)" % [id, last])

## Лупы обязаны быть лупами. Луп живёт в .import, а не в .wav: одноразовый
## эмбиент отыграет свои секунды и молча оставит игру в тишине.
static func test_loops_are_looped(t: TestCtx) -> void:
	var a: GDScript = _audio()
	for id: String in _ids(a, "LOOP_IDS") + _ids(a, "MUSIC_IDS"):
		var dir: String = MUSIC_DIR if id.begins_with("music_") else SFX_DIR
		var cfg: String = FileAccess.get_file_as_string(dir + id + ".wav.import")
		t.check(cfg.contains("edit/loop_mode=1"), "%s не зациклен" % id)
	for id: String in _ids(a, "SFX_IDS") + _ids(a, "UI_IDS"):
		var cfg2: String = FileAccess.get_file_as_string(SFX_DIR + id + ".wav.import")
		t.check(cfg2.contains("edit/loop_mode=0"),
			"%s зациклен, а это разовый звук" % id)

## Раскладка шин собрана генератором и лежит в проекте: без неё Settings
## молча не применяет ни одну громкость.
static func test_bus_layout_exists(t: TestCtx) -> void:
	var path: String = str(ProjectSettings.get_setting(
		"audio/buses/default_bus_layout", "res://default_bus_layout.tres"))
	t.check(ResourceLoader.exists(path), "нет раскладки шин %s" % path)
	var layout: AudioBusLayout = load(path) as AudioBusLayout
	t.check(layout != null, "раскладка читается")
	var gen: GDScript = load("res://tools/gen_bus_layout.gd") as GDScript
	var names: Array[String] = []
	for row: Variant in gen.get("BUSES") as Array:
		names.append(str((row as Array)[0]))
	t.check_eq(names, ["Music", "SFX", "UI", "Ambient"] as Array[String],
		"шины те, которые ждёт Settings.apply()")

# --- Подписки -------------------------------------------------------------

## Все события docs/00 §15 должны дёргать AudioService. Проверяем по исходнику:
## поднять автолоад в headless нельзя, а забытая подписка иначе не видна.
static func test_subscribed_to_spec_events(t: TestCtx) -> void:
	var src: String = FileAccess.get_file_as_string(AUDIO_PATH)
	var required: Array[String] = ["phase_changed", "water_level_changed",
		"agent_died", "crisis_started", "creature_spawned", "recall_issued",
		"draft_ready", "building_placed", "building_state_changed", "run_started"]
	for sig: String in required:
		t.check(src.contains("Events.%s.connect(" % sig),
			"AudioService не подписан на %s" % sig)
	var events: String = FileAccess.get_file_as_string(EVENTS_PATH)
	for sig: String in required:
		t.check(events.contains("signal %s(" % sig),
			"сигнала %s больше нет в шине" % sig)

## Кнопки звучат один раз: у подтверждения и отмены свой звук вместо тапа.
static func test_dialog_buttons_replace_tap(t: TestCtx) -> void:
	var src: String = FileAccess.get_file_as_string(
		"res://ui/components/confirm_dialog.gd")
	t.check(src.contains('_ok.sound_id = "ui_confirm"'), "у «ОК» звук подтверждения")
	t.check(src.contains('_cancel.sound_id = "ui_cancel"'), "у «Отмены» — свой")
	var btn: PixelButton = PixelButton.new()
	t.check_eq(str(btn.sound_id), "ui_tap", "у обычной кнопки звук тапа")
	btn.free()

static func _ids(a: GDScript, key: String) -> Array[String]:
	var out: Array[String] = []
	for v: Variant in a.get(key) as Array:
		out.append(str(v))
	return out

## PCM-данные из .wav на диске: минимальный разбор RIFF без импорта ресурса.
static func _pcm(path: String) -> PackedByteArray:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var all: PackedByteArray = f.get_buffer(int(f.get_length()))
	f.close()
	var i: int = 12                       # RIFF####WAVE
	while i + 8 <= all.size():
		var id: String = all.slice(i, i + 4).get_string_from_ascii()
		var size: int = all.decode_u32(i + 4)
		if id == "data":
			return all.slice(i + 8, mini(i + 8 + size, all.size()))
		i += 8 + size + (size % 2)
	return PackedByteArray()
