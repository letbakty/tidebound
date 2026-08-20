# 23 — Аудио: шины, пулы, вертикальный кроссфейд, генерация плейсхолдеров

**Для этапов:** 17 (весь), 15 (слайдеры громкости), 13 (UI-звуки), 16 (хаптика).
**Дата ресерча:** 2026-08-21. **Движок:** Godot 4.7.x stable.

---

## 1. Шины: создать из кода, а не кликать в редакторе

Дефолтный layout сохраняется в `res://default_bus_layout.tres`. Четыре шины (`Music`, `SFX`, `UI`, `Ambient`) под `Master` можно набить руками, но воспроизводимее — сгенерировать:

```gdscript
@tool
extends EditorScript
## tools/gen_bus_layout.gd — File → Run.

const BUSES: Array[String] = ["Music", "SFX", "UI", "Ambient"]

func _run() -> void:
	AudioServer.set_bus_count(1 + BUSES.size())     # Master + наши
	for i: int in BUSES.size():
		var idx: int = i + 1
		AudioServer.set_bus_name(idx, BUSES[i])
		AudioServer.set_bus_send(idx, "Master")
		AudioServer.set_bus_volume_db(idx, 0.0)
	ResourceSaver.save(AudioServer.generate_bus_layout(),
		"res://default_bus_layout.tres")
	print("bus layout готов")
```

**Рантайм-API, который нужен `AudioService`:**
```gdscript
AudioServer.get_bus_index(name: StringName) -> int
AudioServer.set_bus_volume_db(idx: int, db: float) -> void
AudioServer.set_bus_mute(idx: int, mute: bool) -> void
AudioServer.add_bus_effect(idx: int, effect: AudioEffect, at: int = -1) -> void
```

**Громкость: слайдер линейный, шина в дБ.**
```gdscript
func set_volume(bus: String, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus)
	if linear <= 0.001:
		AudioServer.set_bus_mute(idx, true)          # -80 dB всё ещё слышно на технике
		return
	AudioServer.set_bus_mute(idx, false)
	AudioServer.set_bus_volume_db(idx, linear_to_db(linear))
```
⚠️ **`linear_to_db` — глобальная функция (`@GlobalScope`), не метод AudioServer.** И **обязательна**: слайдер, напрямую пишущий в `volume_db` значение 0..1, даст «тихо/громко» без середины, потому что дБ — логарифмическая шкала. `linear_to_db(0.5) ≈ -6 dB` — то, что ухо считает «вполовину тише».

⚠️ **Отдельный mute на нуле.** `linear_to_db(0.0)` = `-inf`, а `-80 dB` — всё ещё не тишина.

---

## 2. Пулы плееров: 8 SFX, 2 музыкальных

```gdscript
class_name AudioService
extends Node

const SFX_POOL: int = 8
var _sfx: Array[AudioStreamPlayer] = []
var _sfx_next: int = 0

func _ready() -> void:
	for i: int in SFX_POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx.append(p)

func play_sfx(id: String, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _stream(id)
	if stream == null: return
	# round-robin: самый старый плеер переиспользуется
	var p: AudioStreamPlayer = _sfx[_sfx_next]
	_sfx_next = (_sfx_next + 1) % SFX_POOL
	p.stream = stream
	p.volume_db = volume_db
	p.play()
```

**Альтернатива, которая может оказаться лучше: `AudioStreamPolyphonic`.**
```gdscript
var _poly_player := AudioStreamPlayer.new()
var _poly: AudioStreamPlaybackPolyphonic

func _ready() -> void:
	var s := AudioStreamPolyphonic.new()
	s.polyphony = 16
	_poly_player.stream = s
	_poly_player.bus = "SFX"
	add_child(_poly_player)
	_poly_player.play()
	_poly = _poly_player.get_stream_playback() as AudioStreamPlaybackPolyphonic

func play_sfx(id: String, volume_db: float = 0.0) -> void:
	_poly.play_stream(_stream(id), 0.0, volume_db)
```
**Плюсы:** один узел вместо восьми, автоматическая полифония, не надо крутить round-robin.
**Минусы:** нельзя остановить/зациклить конкретный звук по id (возвращается id стрима, но управление беднее).

**Рекомендация: `AudioStreamPolyphonic` для коротких one-shot SFX и UI, обычные `AudioStreamPlayer` — для музыки и эмбиента** (там нужны луп, громкость и кроссфейд по отдельности). Это и меньше кода, и меньше узлов.

⚠️ `get_stream_playback()` возвращает валидный объект **только после `play()`**. Порядок в `_ready` важен.

---

## 3. Вертикальный кроссфейд эмбиента (фича этапа 17)

Два лупа — «верх» (чайки, ветер) и «низ» (капель, гул), микс по Y камеры.

```gdscript
var _amb_top: AudioStreamPlayer
var _amb_bottom: AudioStreamPlayer

## Вызывается от CameraRig не чаще 4 Гц (throttle из промпта).
func set_camera_mark(mark: float) -> void:
	# mark: +6 (верх) .. -12 (низ) -> t: 0..1
	var t: float = clampf(inverse_lerp(6.0, -12.0, mark), 0.0, 1.0)
	# Равномощностный кроссфейд: сумма энергий постоянна, нет «провала» в середине
	var g_top: float = cos(t * PI * 0.5)
	var g_bot: float = sin(t * PI * 0.5)
	_amb_top.volume_db = linear_to_db(maxf(g_top, 0.001))
	_amb_bottom.volume_db = linear_to_db(maxf(g_bot, 0.001))
```

⚠️ **Равномощностный (`cos`/`sin`), а не линейный кроссфейд.** При линейном (`1-t` и `t`) в середине суммарная громкость проседает примерно на 3 дБ — слышно как «дырка» при прокрутке камеры. Это стандарт из звукового дизайна (Wwise/FMOD называют это constant-power crossfade), и он тут стоит две строки.

⚠️ **Троттлинг 4 Гц** — не для производительности (изменение `volume_db` дешёвое), а чтобы не дёргать значение каждый кадр при дрожании камеры. Сглаживание: `lerp` текущего значения к целевому вместо мгновенной установки.

**Третий слой — дождь шторма** поверх обоих, включается по `crisis_started(STORM)` с фейдом 1 с.

---

## 4. Музыка: два состояния и кроссфейд

```gdscript
enum MusicState { NONE, CALM, TENSE }
var _music: Array[AudioStreamPlayer] = []          # 2 плеера
var _active: int = 0

func set_music_state(s: MusicState) -> void:
	if s == _state: return
	_state = s
	var from: AudioStreamPlayer = _music[_active]
	_active = 1 - _active
	var to: AudioStreamPlayer = _music[_active]
	to.stream = _music_stream(s)
	to.volume_db = -60.0
	to.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(to, "volume_db", Settings.music_db, 2.0)
	tw.tween_property(from, "volume_db", -60.0, 2.0)
	tw.chain().tween_callback(from.stop)
```
⚠️ **`set_parallel(true)` + `chain()`** — оба фейда идут одновременно, а `stop` только после. Без `chain()` `stop` сработает сразу.

⚠️ **Целевая громкость — `Settings.music_db`, а не 0.0.** Иначе кроссфейд каждый раз сбрасывает пользовательскую настройку. (Либо держать плееры на 0 dB, а громкость — только на шине. **Это чище: плеер отвечает за микс, шина — за настройки игрока.**)

**Привязка к фазам:** CALM на EBB/LOW, TENSE на SIGNAL/HIGH — подписка на `Events.phase_changed`.

---

## 5. Маппинг событий: подписки, а не вызовы из UI

`AudioService` подписывается на `Events` сам. Ни HUD, ни sim не зовут `play_sfx` — иначе один и тот же звук будет и в двух местах, и нигде.

```gdscript
func _ready() -> void:
	Events.phase_changed.connect(_on_phase)
	Events.agent_died.connect(_on_death)
	Events.crisis_started.connect(_on_crisis)
	Events.creature_spawned.connect(_on_creature)
	Events.water_level_changed.connect(_on_water)
	Events.recall_issued.connect(func(_h: bool) -> void: play_sfx("bell_recall"))

func _on_phase(phase: int, _cycle: int) -> void:
	if phase == SimTypes.Phase.SIGNAL:
		_bell_three_times()

func _bell_three_times() -> void:
	# Три удара с интервалом. Тайминг — Tween, не Timer: меньше узлов, легко отменить.
	var tw := create_tween()
	for i: int in 3:
		tw.tween_callback(func() -> void: play_sfx("bell", 0.0))
		tw.tween_interval(0.6)
```

**Шум воды от скорости изменения уровня:**
```gdscript
var _last_level: float = 0.0
var _last_t: float = 0.0
func _on_water(level: float) -> void:
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var dt: float = maxf(now - _last_t, 0.001)
	var speed: float = absf(level - _last_level) / dt      # отметок в секунду
	_last_level = level; _last_t = now
	var target: float = linear_to_db(clampf(speed * 2.0, 0.001, 1.0))
	_water_noise.volume_db = lerpf(_water_noise.volume_db, target, 0.2)
```
⚠️ **Сглаживание `lerpf` обязательно** — `water_level_changed` приходит раз в 3 тика, скачки громкости будут слышны как щелчки.

**Дакинг эмбиента при смерти:** на 2 с опустить шину `Ambient` на −12 дБ и вернуть.
```gdscript
func _duck(bus: String, db: float, sec: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus)
	var base: float = AudioServer.get_bus_volume_db(idx)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: AudioServer.set_bus_volume_db(idx, v),
		base, base + db, 0.15)
	tw.tween_interval(sec)
	tw.tween_method(func(v: float) -> void: AudioServer.set_bus_volume_db(idx, v),
		base + db, base, 0.5)
```
⚠️ **Два дакинга подряд «запомнят» уже пониженную базу.** Хранить базовую громкость отдельно от текущей и не читать её из шины во время дакинга.

---

## 6. Плейсхолдеры: сгенерировать .wav скриптом

Промпт разрешает тишину + README. **Но синтетические тоны лучше:** они позволяют проверить весь маппинг на слух за одну сессию, а не «по логу».

```gdscript
@tool
extends EditorScript
## tools/gen_placeholder_sfx.gd — File → Run. Пишет короткие тоны в assets/sfx/.

const RATE: int = 22050

# id, частота Гц, длительность с, форма ("sine"/"noise"/"click")
const TONES: Array[Array] = [
	["bell",        660.0, 0.45, "sine"],
	["bell_low",    180.0, 0.90, "sine"],
	["ui_tap",     1200.0, 0.05, "click"],
	["ui_confirm",  880.0, 0.10, "sine"],
	["ui_cancel",   300.0, 0.10, "sine"],
	["ui_error",    140.0, 0.18, "sine"],
	["splash",        0.0, 0.30, "noise"],
	["creature",     90.0, 0.60, "noise"],
]

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/sfx/")
	for row: Array in TONES:
		var n: int = int(RATE * float(row[2]))
		var buf := PackedByteArray()
		buf.resize(n * 2)                             # 16-bit mono
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(row[0])                       # воспроизводимо
		for i: int in n:
			var t: float = float(i) / float(RATE)
			var env: float = 1.0 - float(i) / float(n)        # затухание
			env *= env
			var s: float = 0.0
			match String(row[3]):
				"sine":  s = sin(TAU * float(row[1]) * t)
				"noise": s = rng.randf_range(-1.0, 1.0)
				"click": s = 1.0 if i < 40 else 0.0
			var v: int = clampi(int(s * env * 12000.0), -32768, 32767)
			buf.encode_s16(i * 2, v)
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = RATE
		wav.stereo = false
		wav.data = buf
		wav.save_to_wav("res://assets/sfx/%s.wav" % row[0])
	print("плейсхолдеры записаны: %d" % TONES.size())
```

**Технические факты (проверено по class reference):**
- `AudioStreamWAV.format`: `FORMAT_8_BITS = 0`, `FORMAT_16_BITS = 1`, `FORMAT_IMA_ADPCM = 2`, `FORMAT_QOA = 3`.
- `data: PackedByteArray`; для 8-бит ожидается **знаковый** PCM (из беззнакового вычесть 128).
- `save_to_wav(path)` — **не сохраняет IMA ADPCM и QOA**, только 8/16 бит. Нам подходит.
- `loop_mode`: `LOOP_DISABLED/FORWARD/PINGPONG/BACKWARD`, `loop_begin`/`loop_end` — **в семплах**. Для эмбиент-лупов: `loop_mode = LOOP_FORWARD`, `loop_end = n - 1`.
- `PackedByteArray.encode_s16(offset, value)` — запись little-endian int16.

⚠️ **Огибающая (`env`) обязательна.** Тон, обрывающийся на ненулевой амплитуде, даёт щелчок. Квадратичное затухание — минимум.

⚠️ **`hash(row[0])` как сид** — чтобы шум был одинаковым между прогонами генератора и git не показывал изменения в бинарниках.

**`assets/sfx/README.md`** со списком: id, что должно звучать, длительность, где используется, `PLACEHOLDER: да/нет`. Это ТЗ для художника и одновременно чек-лист приёмки.

---

## 7. Хаптика

```gdscript
func vibrate(ms: int) -> void:
	if not Settings.haptics: return
	if not OS.has_feature("mobile"): return
	Input.vibrate_handheld(ms)
```
⚠️ **`OS.has_feature("mobile")`-гейт обязателен:** на десктопе метод ничего не делает, но на некоторых платформах может писать предупреждение в лог каждый раз.
Длительности: отзыв 30 мс, сигнал прилива 60 мс, смерть агента 120 мс. Больше 150 мс раздражает.

---

## 8. Лог звуковых вызовов для приёмки

Промпт требует «лог в дебаг-панели». Дёшево и делает приёмку проверяемой:
```gdscript
var call_log: Array[String] = []          # только в debug-сборке
func _note(what: String) -> void:
	if not OS.is_debug_build(): return
	call_log.append("%.1f %s" % [float(Time.get_ticks_msec()) / 1000.0, what])
	if call_log.size() > 200: call_log.remove_at(0)
```
Дебаг-панель (этап 03) добавляет секцию «Звук» — читает `AudioService.call_log`. Пункт приёмки «все события из docs/00 §15 дергают AudioService» становится механической сверкой.

---

## 9. Чек-лист приёмки этапа 17

- [ ] Все события §15 попадают в `call_log`.
- [ ] Громкости из настроек применяются и сохраняются; на нуле — реальная тишина (mute, не −80 дБ).
- [ ] Кроссфейд верх/низ равномощностный: при медленной прокрутке нет провала громкости в середине.
- [ ] Три удара колокола на SIGNAL — ровно три, с интервалом.
- [ ] Смерть: низкий колокол + дакинг Ambient 2 с; два подряд не «залипают».
- [ ] Музыка переключается CALM/TENSE с фейдом 2 с, без наложения трёх треков.
- [ ] Плейсхолдеры не щёлкают (огибающая).
- [ ] `assets/sfx/README.md` перечисляет все нужные файлы.
- [ ] На паузе (`speed = 0`) звук не «залипает» на цикле: эмбиент играет, разовые звуки не запускаются.

---

## Источники

- [AudioServer](https://docs.godotengine.org/en/stable/classes/class_audioserver.html) — `get_bus_index`, `set_bus_volume_db`, `generate_bus_layout`, `set_bus_send`
- [Audio buses](https://docs.godotengine.org/en/stable/tutorials/audio/audio_buses.html) — `default_bus_layout.tres`, запас по Master
- [AudioStreamWAV](https://docs.godotengine.org/en/stable/classes/class_audiostreamwav.html) — `format`, `data`, `save_to_wav`, `loop_*`
- [AudioStreamPolyphonic](https://docs.godotengine.org/en/stable/classes/class_audiostreampolyphonic.html) — полифония без пула узлов
- [@GlobalScope](https://docs.godotengine.org/en/stable/classes/class_@globalscope.html) — `linear_to_db` / `db_to_linear`
- [Input.vibrate_handheld](https://docs.godotengine.org/en/stable/classes/class_input.html) — хаптика
