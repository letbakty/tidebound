extends Node
## Шины, пулы плееров, маппинг событий Events -> звук, вертикальный кроссфейд.
##
## Правило слоя (research/23 §5): звук подписывается на Events САМ. Ни sim, ни
## HUD не зовут play_sfx для мировых событий — иначе один и тот же звук
## оказывается и в двух местах сразу, и нигде. Исключение одно и оно осознанное:
## UI-звуки (тап, подтверждение, отмена, ошибка размещения) — у них нет
## сигналов в шине, и звать play_ui из виджета честнее, чем городить сигналы
## ради щелчка.
##
## Вся арифметика вынесена в статические функции: кроссфейд, дакинг, громкость
## шума воды и расписание колокола проверяются тестом без дерева и без звуковой
## карты (автолоадов в headless-раннере нет).
##
## Числа здесь — презентация, а не баланс игры: в sim/balance.gd им не место.

enum MusicState { NONE, CALM, TENSE }

# --- Каталог (он же контракт с tools/gen_placeholder_sfx.gd) --------------

## Одноразовые звуки мира, шина SFX.
const SFX_IDS: Array[String] = ["bell", "bell_low", "splash", "phase_shift",
	"build", "build_done", "break", "station", "work", "creature", "thunder"]
## Звуки интерфейса, шина UI.
const UI_IDS: Array[String] = ["ui_tap", "ui_confirm", "ui_cancel", "ui_draft",
	"ui_error"]
## Лупы: три слоя эмбиента + дождь шторма + шум подъёма воды.
const LOOP_IDS: Array[String] = ["amb_sea", "amb_top", "amb_bottom", "amb_rain",
	"water_rise"]
const MUSIC_IDS: Array[String] = ["music_calm", "music_tense"]

const SFX_DIR: String = "res://assets/sfx/"
const MUSIC_DIR: String = "res://assets/music/"

# --- Числа ----------------------------------------------------------------

## Полифония: восемь одновременных звуков мира (docs/00 §16 — на экране не
## бывает больше событий) и четыре UI.
const POLYPHONY_SFX: int = 8
const POLYPHONY_UI: int = 4

const MUSIC_FADE_SEC: float = 2.0
## В меню музыка тише: там она фон под текстом, а не часть сцены.
const MENU_MUSIC_DB: float = -6.0
const RAIN_FADE_SEC: float = 1.0

## Три удара колокола с интервалом. Второй и третий чуть ниже и тише —
## настоящий колокол не бьёт дважды одинаково (research/35 §3.2).
const BELL_STRIKES: int = 3
const BELL_GAP_SEC: float = 0.6
const BELL_PITCH_STEP: float = 0.015
const BELL_DB_STEP: float = 1.2

## Дакинг: провал громкости шины под важный звук.
const DUCK_ATTACK_SEC: float = 0.15
const DUCK_RELEASE_SEC: float = 0.5
const DUCK_DEATH_DB: float = -12.0
const DUCK_DEATH_SEC: float = 2.0
const DUCK_BELL_DB: float = -6.0
const DUCK_BELL_SEC: float = 0.3

## Вертикальный кроссфейд: отметки верха и дна утёса и полоса смешивания.
## Кроссфейд идёт не по всей высоте, а в средней трети — иначе оба слоя
## слышны везде и ни один не читается (research/35 §5.2).
const MARK_TOP: float = 6.0
const MARK_BOTTOM: float = -12.0
const MIX_FROM: float = 0.35
const MIX_TO: float = 0.65
## Не чаще 4 Гц: дрожание камеры не должно дёргать громкость.
const CAMERA_THROTTLE_SEC: float = 0.25
## Скорость подтягивания громкости к цели (доля за кадр при 60 fps).
const AMBIENT_LERP: float = 0.08

## Шум подъёма: громкость от скорости изменения уровня, отметок в секунду.
const WATER_SPEED_FULL: float = 0.5
const WATER_LERP: float = 0.2
const WATER_FLOOR_DB: float = -40.0

## Питч-вариация разовых звуков: двадцать всплесков подряд перестают звучать
## как один файл (research/35 §2.2). Это презентация — обычный randf, не SimRNG.
const PITCH_JITTER: float = 0.06

## Одна станция не должна тарахтеть каждый тик, а шестнадцать агентов —
## стучать инструментом вразнобой.
const THROTTLE_WORK_SEC: float = 0.8
const THROTTLE_STATION_SEC: float = 1.5
const THROTTLE_SPLASH_SEC: float = 0.4

## Хаптика (research/23 §7): больше 150 мс раздражает.
const HAPTIC_MS: Dictionary[String, int] = {
	"tap": 30, "signal": 60, "death": 120,
}

const LOG_MAX: int = 200

# --- Состояние ------------------------------------------------------------

## Лог вызовов для дебаг-панели: приёмка этапа сводится к сверке со списком
## docs/00 §15. Только в debug-сборке.
var call_log: Array[String] = []

var _poly_sfx: AudioStreamPlayer = null
var _poly_ui: AudioStreamPlayer = null
var _sfx: AudioStreamPlaybackPolyphonic = null
var _ui: AudioStreamPlaybackPolyphonic = null
var _music: Array[AudioStreamPlayer] = []
var _music_idx: int = 0
var _music_state: MusicState = MusicState.NONE
var _music_tween: Tween = null
var _in_menu: bool = true

var _amb: Dictionary[String, AudioStreamPlayer] = {}
var _cache: Dictionary[String, AudioStream] = {}
var _missing: Dictionary[String, bool] = {}

## Активные дакинги: шина -> [время старта, длительность удержания, глубина].
var _ducks: Dictionary[String, Array] = {}

var _mark_target: float = MARK_TOP
var _mark_now: float = MARK_TOP
var _mark_last_set: float = -1.0
var _rain_gain: float = 0.0
var _rain_target: float = 0.0

var _water_level: float = 0.0
var _water_seen: bool = false
var _water_last_t: float = 0.0
var _water_gain: float = 0.0
var _water_target: float = 0.0

var _throttle: Dictionary[String, float] = {}
var _building_flags: Dictionary[int, Array] = {}
var _bell_tween: Tween = null
## Режим без звуковой карты: события считаются и логируются, но не звучат.
var _silent: bool = false

# --- Жизненный цикл -------------------------------------------------------

func _ready() -> void:
	# Пауза игры — это speed = 0, а не пауза дерева; но модальные окна могут
	# ставить дерево на паузу, и звук обязан пережить это.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Без звуковой карты (headless: тесты, смоук, съёмка) плееры не создаём.
	# Играть всё равно некуда, а загруженные лупы живут до конца процесса и
	# на выходе дают «resources still in use at exit» — то есть красный прогон
	# тестов на ровном месте. Маппинг событий при этом проверяется по call_log:
	# он пишется ДО попытки воспроизведения.
	_silent = DisplayServer.get_name() == "headless"
	if not _silent:
		_build_players()
	_subscribe()
	set_music_state(MusicState.CALM)

func _build_players() -> void:
	_poly_sfx = _make_poly("SFX", POLYPHONY_SFX)
	_poly_ui = _make_poly("UI", POLYPHONY_UI)
	# get_stream_playback() валиден ТОЛЬКО после play() (research/23 §2).
	_sfx = _poly_sfx.get_stream_playback() as AudioStreamPlaybackPolyphonic
	_ui = _poly_ui.get_stream_playback() as AudioStreamPlaybackPolyphonic
	for i: int in 2:
		var m: AudioStreamPlayer = AudioStreamPlayer.new()
		m.name = "Music%d" % i
		m.bus = "Music"
		m.volume_db = -60.0
		add_child(m)
		_music.append(m)
	# Три слоя эмбиента играют всегда, меняется только их громкость: старт и
	# остановка лупов слышны как переключение радиостанции.
	for id: String in ["amb_sea", "amb_top", "amb_bottom", "amb_rain"]:
		_amb[id] = _make_loop(id, "Ambient")
	# Шум подъёма — событие мира, а не фон: шина SFX.
	_amb["water_rise"] = _make_loop("water_rise", "SFX")

func _make_poly(bus: String, voices: int) -> AudioStreamPlayer:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.name = "Poly" + bus
	p.bus = bus
	var s: AudioStreamPolyphonic = AudioStreamPolyphonic.new()
	s.polyphony = voices
	p.stream = s
	add_child(p)
	p.play()
	return p

func _make_loop(id: String, bus: String) -> AudioStreamPlayer:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.name = id
	p.bus = bus
	p.volume_db = WATER_FLOOR_DB
	var stream: AudioStream = _stream(SFX_DIR + id + ".wav")
	if stream == null:
		add_child(p)
		return p
	p.stream = stream
	add_child(p)
	p.play()
	return p

func _subscribe() -> void:
	Events.phase_changed.connect(_on_phase_changed)
	Events.water_level_changed.connect(_on_water_level_changed)
	Events.agent_died.connect(_on_agent_died)
	Events.agent_updated.connect(_on_agent_updated)
	Events.crisis_started.connect(_on_crisis_started)
	Events.crisis_ended.connect(_on_crisis_ended)
	Events.creature_spawned.connect(_on_creature_spawned)
	Events.building_placed.connect(_on_building_placed)
	Events.building_state_changed.connect(_on_building_state_changed)
	Events.building_removed.connect(_on_building_removed)
	Events.recall_issued.connect(_on_recall_issued)
	Events.draft_ready.connect(_on_draft_ready)
	Events.card_picked.connect(_on_card_picked)
	Events.run_started.connect(_on_run_started)
	Events.run_ended.connect(_on_run_ended)

## На выходе потоки отпускаем руками. Автолоад умирает последним, и без этого
## движок пишет «resources still in use at exit» — а раннер тестов валит прогон
## на любом ERROR (docs/02 §7.1). Заодно это честная проверка на утечки этапа 19.
func _exit_tree() -> void:
	for tw: Tween in [_music_tween, _bell_tween]:
		if tw != null and tw.is_valid():
			tw.kill()
	for p: AudioStreamPlayer in _amb.values():
		p.stop()
		p.stream = null
	for m: AudioStreamPlayer in _music:
		m.stop()
		m.stream = null
	for poly: AudioStreamPlayer in [_poly_sfx, _poly_ui]:
		if poly == null:
			continue
		poly.stop()
		poly.stream = null
	_sfx = null
	_ui = null
	_amb.clear()
	_music.clear()
	_cache.clear()

func _process(delta: float) -> void:
	_apply_ducks()
	_advance_ambient(delta)

# --- Публичный API --------------------------------------------------------

## Разовый звук мира. Питч-вариация — по умолчанию: одинаковые повторы
## ухо помечает как шум и перестаёт на них реагировать.
func play_sfx(id: String, volume_db: float = 0.0, pitch: float = 0.0) -> void:
	# Лог до воспроизведения: приёмка маппинга событий не должна зависеть от
	# наличия звуковой карты.
	_note("sfx:" + id)
	if _sfx == null:
		return
	var stream: AudioStream = _stream(SFX_DIR + id + ".wav")
	if stream == null:
		return
	var p: float = pitch if pitch > 0.0 else randf_range(
		1.0 - PITCH_JITTER, 1.0 + PITCH_JITTER)
	_sfx.play_stream(stream, 0.0, volume_db, p)

func play_ui(id: String, volume_db: float = 0.0) -> void:
	_note("ui:" + id)
	if _ui == null:
		return
	var stream: AudioStream = _stream(SFX_DIR + id + ".wav")
	if stream == null:
		return
	_ui.play_stream(stream, 0.0, volume_db, 1.0)

func set_music_state(s: MusicState) -> void:
	if s == _music_state:
		return
	_music_state = s
	_note("music:" + music_name(s))
	if _music.is_empty():
		return
	var from: AudioStreamPlayer = _music[_music_idx]
	_music_idx = 1 - _music_idx
	var to: AudioStreamPlayer = _music[_music_idx]
	var stream: AudioStream = null
	if s != MusicState.NONE:
		stream = _stream(MUSIC_DIR + music_file(s))
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	if stream == null:
		# Трека нет — гасим текущий и не поднимаем пустой плеер.
		_music_tween = create_tween()
		_music_tween.tween_property(from, "volume_db", -60.0, MUSIC_FADE_SEC)
		_music_tween.tween_callback(from.stop)
		return
	to.stream = stream
	to.volume_db = -60.0
	to.play()
	# Плеер отвечает за микс, шина — за настройку игрока: целевая громкость
	# всегда 0 дБ (минус тише в меню), а не Settings.music_db (research/23 §4).
	var target: float = MENU_MUSIC_DB if _in_menu else 0.0
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(to, "volume_db", target, MUSIC_FADE_SEC)
	_music_tween.tween_property(from, "volume_db", -60.0, MUSIC_FADE_SEC)
	# chain(), иначе stop сработает сразу, а не после фейда.
	_music_tween.chain().tween_callback(from.stop)

## Позиция камеры по вертикали в отметках. Зовёт CameraRig не чаще 4 Гц.
func set_camera_mark(mark: float) -> void:
	var now: float = _now()
	if now - _mark_last_set < CAMERA_THROTTLE_SEC:
		return
	_mark_last_set = now
	_mark_target = mark

## Хаптика телефона. На десктопе метод пустой, но гейт по фиче обязателен:
## часть платформ пишет предупреждение в лог на каждый вызов.
func vibrate(kind: String) -> void:
	if not Settings.haptics:
		return
	if not OS.has_feature("mobile"):
		return
	Input.vibrate_handheld(int(HAPTIC_MS.get(kind, 30)))

## Срез для дебаг-панели: что звучит прямо сейчас.
func debug_state() -> String:
	var g: Vector2 = ambient_gains(_mark_now)
	return "музыка %s · верх %.2f низ %.2f дождь %.2f · вода %.2f" % [
		music_name(_music_state), g.x, g.y, _rain_gain, _water_gain]

# --- Статика: вся арифметика звука ---------------------------------------

## Равномощностный кроссфейд верх/низ: сумма энергий постоянна, провала
## громкости в середине нет. smoothstep сужает полосу смешивания до средней
## трети высоты — вне её слышен ровно один слой.
static func ambient_gains(mark: float) -> Vector2:
	var t: float = clampf(inverse_lerp(MARK_TOP, MARK_BOTTOM, mark), 0.0, 1.0)
	var mix: float = smoothstep(MIX_FROM, MIX_TO, t)
	return Vector2(cos(mix * PI * 0.5), sin(mix * PI * 0.5))

## Линейная громкость -> дБ. Ноль — это тишина, а не −80 дБ: на технике
## −80 дБ всё ещё слышно.
static func gain_to_db(gain: float) -> float:
	if gain <= 0.001:
		return WATER_FLOOR_DB
	return maxf(linear_to_db(gain), WATER_FLOOR_DB)

## Громкость шума подъёма по скорости изменения уровня (отметок в секунду).
static func water_gain(speed: float) -> float:
	return clampf(speed / WATER_SPEED_FULL, 0.0, 1.0)

static func water_noise_db(speed: float) -> float:
	return gain_to_db(water_gain(speed))

## Музыка по фазе: спокойная на Отливе и Низкой, тревожная с Сигнала.
static func music_for_phase(phase: int) -> MusicState:
	if phase == SimTypes.Phase.SIGNAL or phase == SimTypes.Phase.HIGH:
		return MusicState.TENSE
	return MusicState.CALM

static func music_file(s: MusicState) -> String:
	return "music_tense.wav" if s == MusicState.TENSE else "music_calm.wav"

static func music_name(s: MusicState) -> String:
	match s:
		MusicState.CALM: return "CALM"
		MusicState.TENSE: return "TENSE"
	return "—"

## Расписание трёх ударов: [задержка с, питч, громкость дБ].
static func bell_schedule() -> Array[Array]:
	var out: Array[Array] = []
	for i: int in BELL_STRIKES:
		out.append([float(i) * BELL_GAP_SEC,
			1.0 - float(i) * BELL_PITCH_STEP,
			-float(i) * BELL_DB_STEP])
	return out

## Смещение громкости шины под дакингом: спад, удержание, возврат в НОЛЬ.
## Возврат именно в ноль — поэтому два дакинга подряд не «запоминают»
## уже пониженную базу (research/23 §5).
static func duck_offset_db(elapsed: float, hold: float, depth_db: float) -> float:
	if elapsed <= 0.0:
		return 0.0
	if elapsed < DUCK_ATTACK_SEC:
		return depth_db * (elapsed / DUCK_ATTACK_SEC)
	if elapsed < DUCK_ATTACK_SEC + hold:
		return depth_db
	var rel: float = elapsed - DUCK_ATTACK_SEC - hold
	if rel >= DUCK_RELEASE_SEC:
		return 0.0
	return depth_db * (1.0 - rel / DUCK_RELEASE_SEC)

## Пересекла ли вода целую отметку, поднимаясь. Всплеск — на ярус, а не на
## каждое изменение уровня.
static func crossed_mark_up(prev: float, now: float) -> bool:
	return now > prev and floorf(now) > floorf(prev)

# --- Обработчики Events ---------------------------------------------------

func _on_phase_changed(phase: int, _cycle: int) -> void:
	set_music_state(music_for_phase(phase))
	if _quiet():
		return
	# Глухой сдвиг — на каждой смене фазы; колокол — только на Сигнале.
	play_sfx("phase_shift", -3.0)
	if phase == SimTypes.Phase.SIGNAL:
		_bell_three_times()
		vibrate("signal")

func _on_water_level_changed(level: float) -> void:
	var now: float = _now()
	if not _water_seen:
		_water_seen = true
		_water_level = level
		_water_last_t = now
		return
	var dt: float = maxf(now - _water_last_t, 0.001)
	var speed: float = absf(level - _water_level) / dt
	_water_target = water_gain(speed)
	if crossed_mark_up(_water_level, level) and not _quiet():
		if _allow("splash", THROTTLE_SPLASH_SEC):
			play_sfx("splash")
	_water_level = level
	_water_last_t = now

func _on_agent_died(_id: int, _cause: String) -> void:
	play_sfx("bell_low", 1.0, 1.0)
	_duck("Ambient", DUCK_DEATH_DB, DUCK_DEATH_SEC)
	vibrate("death")

## Станции и стройка своих сигналов не имеют (docs/02 §3.2), поэтому звук
## работы вешается на смену состояния агента. РЕШЕНИЕ: один общий звук
## инструмента вместо горна и канатной по отдельности — различить их можно
## только по задаче агента, а её в контракте запроса нет.
func _on_agent_updated(id: int) -> void:
	if _quiet():
		return
	# query_agent_look, а не query_agent: полный срез агента копирует черты
	# и рюкзак, а звуку нужно одно поле — и спрашивают его шестнадцать раз
	# в секунду.
	var a: Dictionary = Game.query_agent_look(id)
	if a.is_empty() or int(a.get("state", -1)) != SimTypes.AgentState.WORK:
		return
	if _allow("work", THROTTLE_WORK_SEC):
		play_sfx("work", -4.0)

func _on_crisis_started(type: int) -> void:
	# У Прихода своего звука нет намеренно: существа озвучены поштучно через
	# creature_spawned, и второй звук в тот же момент слышен как каша.
	if type != SimTypes.CrisisType.STORM:
		return
	_rain_target = 1.0
	if not _quiet():
		play_sfx("thunder", -2.0)

func _on_crisis_ended(type: int) -> void:
	if type == SimTypes.CrisisType.STORM:
		_rain_target = 0.0

func _on_creature_spawned(_id: int) -> void:
	if not _quiet():
		play_sfx("creature")

func _on_building_placed(id: int) -> void:
	_remember_building(id)
	if not _quiet():
		play_sfx("build", -2.0)

## Из всех источников building_state_changed звучат три случая: постройка
## сломалась, достроилась, работающая станция что-то сделала. Остальные —
## затопление, ремонтные флаги, топливо — идут в картинку, но не в звук.
##
## Станция озвучена именно так — «работающая постройка прислала событие», а не
## «начала работать»: своего события у производства в контракте нет, а флаг
## working у горна за цикл не падает ни разу, и звук по фронту не прозвучал бы
## никогда (проверено прогоном). Троттлинг держит частоту в рамках.
func _on_building_state_changed(id: int) -> void:
	var b: Dictionary = Game.query_building(id)
	if b.is_empty():
		return
	var was: Array = _building_flags.get(id, [])
	_remember_building(id)
	if was.is_empty() or _quiet():
		return
	var now: Array = _building_flags[id]
	if bool(now[1]) and not bool(was[1]):
		play_sfx("break", -1.0)
		return
	if int(now[0]) == SimTypes.BuildState.ACTIVE \
			and int(was[0]) != SimTypes.BuildState.ACTIVE:
		play_sfx("build_done", -2.0)
		return
	if bool(now[2]) and _allow("station", THROTTLE_STATION_SEC):
		play_sfx("station", -6.0)

func _on_building_removed(id: int) -> void:
	_building_flags.erase(id)

func _on_recall_issued(_hard: bool) -> void:
	play_sfx("bell", 0.0, 1.0)
	vibrate("signal")

func _on_draft_ready(_card_ids: Array[String]) -> void:
	play_ui("ui_draft")

func _on_card_picked(_card_id: String) -> void:
	play_ui("ui_confirm")

func _on_run_started(_seed_value: int) -> void:
	_in_menu = false
	_building_flags.clear()
	_water_seen = false
	_rain_target = 0.0
	# Смена состояния «в лоб»: забег начинается с Отлива, музыка — спокойная.
	_music_state = MusicState.NONE
	set_music_state(MusicState.CALM)

func _on_run_ended(_report: Dictionary) -> void:
	_in_menu = true
	_rain_target = 0.0
	_music_state = MusicState.NONE
	set_music_state(MusicState.CALM)

# --- Внутреннее -----------------------------------------------------------

## Три удара по расписанию. Tween, а не Timer: меньше узлов и легко отменить,
## если Сигнал пришёл дважды подряд (перемотка).
func _bell_three_times() -> void:
	if _bell_tween != null and _bell_tween.is_valid():
		_bell_tween.kill()
	_bell_tween = create_tween()
	var prev: float = 0.0
	for strike: Array in bell_schedule():
		var wait: float = float(strike[0]) - prev
		prev = float(strike[0])
		if wait > 0.0:
			_bell_tween.tween_interval(wait)
		var pitch: float = float(strike[1])
		var db: float = float(strike[2])
		_bell_tween.tween_callback(func() -> void:
			play_sfx("bell", db, pitch)
			# Колокол слышен не громкостью, а тишиной вокруг него.
			_duck("Ambient", DUCK_BELL_DB, DUCK_BELL_SEC))

func _duck(bus: String, depth_db: float, hold: float) -> void:
	_ducks[bus] = [_now(), hold, depth_db]
	_note("duck:" + bus)

func _apply_ducks() -> void:
	if _ducks.is_empty():
		return
	var done: Array[String] = []
	for bus: String in _ducks:
		var d: Array = _ducks[bus]
		var offset: float = duck_offset_db(_now() - float(d[0]), float(d[1]),
			float(d[2]))
		_set_bus_db(bus, _bus_base(bus) + offset)
		if offset == 0.0 and _now() - float(d[0]) > DUCK_ATTACK_SEC:
			done.append(bus)
	for bus: String in done:
		_ducks.erase(bus)
		_set_bus_db(bus, _bus_base(bus))

func _advance_ambient(delta: float) -> void:
	# Сглаживание кадрозависимое, но звук — не симуляция: детерминизм тут
	# не нужен, а рывок громкости слышен.
	var k: float = clampf(AMBIENT_LERP * delta * 60.0, 0.0, 1.0)
	_mark_now = lerpf(_mark_now, _mark_target, k)
	var g: Vector2 = ambient_gains(_mark_now)
	_set_loop_db("amb_top", gain_to_db(g.x))
	_set_loop_db("amb_bottom", gain_to_db(g.y))
	_set_loop_db("amb_sea", 0.0)
	_rain_gain = lerpf(_rain_gain, _rain_target,
		clampf(delta / RAIN_FADE_SEC, 0.0, 1.0))
	_set_loop_db("amb_rain", gain_to_db(_rain_gain))
	# Скачки громкости слышны щелчками: цель подтягиваем, а не ставим.
	_water_gain = lerpf(_water_gain, _water_target, clampf(WATER_LERP * delta * 60.0, 0.0, 1.0))
	_set_loop_db("water_rise", gain_to_db(_water_gain))

func _set_loop_db(id: String, db: float) -> void:
	var p: AudioStreamPlayer = _amb.get(id, null)
	if p == null or p.stream == null:
		return
	p.volume_db = db

func _set_bus_db(bus: String, db: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, db)

## База шины — настройка игрока, а не текущая громкость: читать текущую во
## время дакинга значит запомнить уже пониженное значение.
func _bus_base(bus: String) -> float:
	match bus:
		"Master": return Settings.master_db
		"Music": return Settings.music_db
		"SFX": return Settings.sfx_db
		"UI": return Settings.ui_db
		"Ambient": return Settings.ambient_db
	return 0.0

## Разовые звуки молчат на перемотке: за секунду debug_fast_forward проходит
## сотни тиков, и каждый из них попытался бы что-то сыграть.
func _quiet() -> bool:
	return Game.fast_forwarding

func _allow(key: String, gap: float) -> bool:
	var now: float = _now()
	if now - float(_throttle.get(key, -999.0)) < gap:
		return false
	_throttle[key] = now
	return true

func _remember_building(id: int) -> void:
	var b: Dictionary = Game.query_building(id)
	if b.is_empty():
		return
	_building_flags[id] = [int(b.get("state", 0)), bool(b.get("damaged", false)),
		bool(b.get("working", false))]

func _stream(path: String) -> AudioStream:
	if _silent:
		return null
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		if not _missing.has(path):
			_missing[path] = true
			push_warning("AudioService: нет файла %s" % path)
		return null
	var s: AudioStream = load(path) as AudioStream
	_cache[path] = s
	return s

func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

func _note(what: String) -> void:
	if not OS.is_debug_build():
		return
	call_log.append("%.1f %s" % [_now(), what])
	if call_log.size() > LOG_MAX:
		call_log.remove_at(0)
