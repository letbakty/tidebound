extends SceneTree
## Плейсхолдеры звука: короткие тоны и шумовые лупы в assets/sfx и assets/music.
##   godot --headless -s res://tools/gen_placeholder_sfx.gd
##   godot --headless --import --quit        # после генерации
##
## Зачем синтетика, а не тишина (research/23 §6): маппинг событий проверяется
## на слух за один запуск, а не «по логу». Каждый файл помечен PLACEHOLDER
## в assets/sfx/README.md — это же ТЗ на замену настоящими звуками.
##
## Правила, без которых плейсхолдеры звучат как дефекты:
## — огибающая обязательна: тон, оборванный на ненулевой амплитуде, щёлкает;
## — сид шума фиксирован именем файла: перегенерация не должна менять байты,
##   иначе git показывает изменения в бинарниках на пустом месте;
## — у лупов шов сшивается кроссфейдом, иначе на стыке слышен щелчок.

const SFX_DIR: String = "res://assets/sfx/"
const MUSIC_DIR: String = "res://assets/music/"

## Одноразовые звуки: id, частота Гц, длительность с, форма, пиковая амплитуда.
## Формы: sine (тон), bell (тон + обертоны, быстрый спад), noise (шум),
## click (щелчок), thud (низкий удар).
const TONES: Array[Array] = [
	["bell", 420.0, 0.80, "bell", 0.34],
	["bell_low", 165.0, 1.40, "bell", 0.30],
	["splash", 0.0, 0.35, "noise", 0.26],
	["phase_shift", 90.0, 0.50, "thud", 0.24],
	["build", 240.0, 0.22, "thud", 0.22],
	["build_done", 560.0, 0.35, "bell", 0.24],
	["break", 0.0, 0.45, "noise", 0.28],
	["station", 300.0, 0.40, "thud", 0.20],
	["work", 700.0, 0.16, "click", 0.20],
	["creature", 70.0, 0.70, "noise", 0.26],
	["thunder", 45.0, 1.80, "thud", 0.32],
	["ui_tap", 1100.0, 0.05, "click", 0.16],
	["ui_confirm", 880.0, 0.10, "sine", 0.18],
	["ui_cancel", 300.0, 0.10, "sine", 0.16],
	["ui_draft", 640.0, 0.30, "bell", 0.20],
	["ui_error", 140.0, 0.18, "sine", 0.20],
]

## Лупы: id, длительность с, форма, пиковая амплитуда, «цвет» шума (0 — глухой
## низ, 1 — яркий верх). Длины НАМЕРЕННО разные и взаимно непериодичные:
## совпадающие лупы дают слышимый повтор через минуту (research/35 §2.2).
const LOOPS: Array[Array] = [
	["amb_sea", 6.0, "surf", 0.10, 0.35],
	["amb_top", 5.0, "wind", 0.09, 0.80],
	["amb_bottom", 4.0, "drips", 0.09, 0.15],
	["amb_rain", 3.5, "wind", 0.11, 0.65],
	["water_rise", 3.0, "surf", 0.16, 0.50],
]

## Музыка: id, длительность с, основной тон Гц, набор интервалов (полутоны).
## Мажорная терция в CALM, малая секунда в TENSE — разница слышна сразу,
## а это всё, что от плейсхолдера нужно.
const MUSIC: Array[Array] = [
	["music_calm", 8.0, 110.0, [0, 7, 16]],
	["music_tense", 8.0, 98.0, [0, 6, 13]],
]

## Лупы шумные и без верхней детали — 11 кГц хватает и вдвое экономит вес.
const RATE_LOOP: int = 11025
const RATE_ONESHOT: int = 22050
## Доля лупа, уходящая в кроссфейд шва.
const SEAM: float = 0.12

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SFX_DIR)
	DirAccess.make_dir_recursive_absolute(MUSIC_DIR)
	var written: int = 0
	for row: Array in TONES:
		written += _write(SFX_DIR + str(row[0]) + ".wav",
			_one_shot(str(row[0]), float(row[1]), float(row[2]), str(row[3]), float(row[4])),
			RATE_ONESHOT, false)
	for row: Array in LOOPS:
		written += _write(SFX_DIR + str(row[0]) + ".wav",
			_loop(str(row[0]), float(row[1]), str(row[2]), float(row[3]), float(row[4])),
			RATE_LOOP, true)
	for row: Array in MUSIC:
		written += _write(MUSIC_DIR + str(row[0]) + ".wav",
			_drone(float(row[1]), float(row[2]), row[3] as Array), RATE_LOOP, true)
	print("плейсхолдеры записаны: %d" % written)
	quit(0 if written == TONES.size() + LOOPS.size() + MUSIC.size() else 1)

# --- Синтез ---------------------------------------------------------------

func _one_shot(id: String, freq: float, sec: float, shape: String,
		peak: float) -> PackedFloat32Array:
	var n: int = int(float(RATE_ONESHOT) * sec)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var rng: RandomNumberGenerator = _rng(id)
	# Однополюсный фильтр: белый шум звучит как радиопомеха, приглушённый —
	# как вода и камень.
	var lp: float = 0.0
	for i: int in n:
		var t: float = float(i) / float(RATE_ONESHOT)
		var k: float = float(i) / float(n)
		var s: float = 0.0
		match shape:
			"sine":
				s = sin(TAU * freq * t)
			"bell":
				# Обертоны 2× и 2.76× (несгармонично — так звучит металл),
				# каждый тише и короче основного.
				s = sin(TAU * freq * t)
				s += 0.45 * sin(TAU * freq * 2.0 * t) * exp(-6.0 * k)
				s += 0.25 * sin(TAU * freq * 2.76 * t) * exp(-10.0 * k)
				s *= 0.6
			"thud":
				# Питч-спад вниз: удар, а не тон.
				var f: float = freq * (1.0 - 0.45 * k)
				s = sin(TAU * f * t) * 0.8 + 0.2 * rng.randf_range(-1.0, 1.0)
			"noise":
				lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.22)
				s = lp * 3.0
			"click":
				s = sin(TAU * freq * t) if i < RATE_ONESHOT / 40 else 0.0
		out[i] = s * _env(shape, k) * peak
	return out

## Огибающая по форме. Общее правило одно: в конце строго ноль.
func _env(shape: String, k: float) -> float:
	match shape:
		"bell":
			return exp(-4.0 * k) * minf(1.0, k * 60.0) * (1.0 - k * k)
		"click":
			return (1.0 - k) * (1.0 - k)
		"thud":
			return exp(-3.5 * k) * minf(1.0, k * 40.0) * (1.0 - k)
		"noise":
			return exp(-2.5 * k) * minf(1.0, k * 30.0) * (1.0 - k)
	return minf(1.0, k * 50.0) * (1.0 - k) * (1.0 - k)

func _loop(id: String, sec: float, shape: String, peak: float,
		color: float) -> PackedFloat32Array:
	var n: int = int(float(RATE_LOOP) * sec)
	var raw: PackedFloat32Array = PackedFloat32Array()
	raw.resize(n)
	var rng: RandomNumberGenerator = _rng(id)
	var lp: float = 0.0
	var lp2: float = 0.0
	# Чем «ярче» слой, тем слабее фильтрация: чайки и ветер живут наверху
	# спектра, гул и капель — внизу.
	var cut: float = lerpf(0.03, 0.5, color)
	for i: int in n:
		var t: float = float(i) / float(RATE_LOOP)
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), cut)
		var s: float = lp
		match shape:
			"surf":
				# Медленное дыхание прибоя: два несовпадающих периода.
				s *= 0.55 + 0.45 * sin(TAU * t / sec) * sin(TAU * t / (sec * 0.37))
				s *= 3.0
			"wind":
				lp2 = lerpf(lp2, rng.randf_range(-1.0, 1.0), 0.004)
				s = (s * 0.7 + lp2 * 1.4) * 2.6
			"drips":
				# Редкие капли поверх гула: тон с быстрым спадом раз в ~0.9 с.
				var period: int = int(float(RATE_LOOP) * 0.9)
				var since: float = float(i % period) / float(RATE_LOOP)
				s = s * 2.2 + 0.35 * sin(TAU * 900.0 * since) * exp(-14.0 * since)
		raw[i] = s * peak
	return _seam(raw)

## Гудящий аккорд: частоты подобраны так, чтобы уложить ЦЕЛОЕ число периодов
## в длину лупа — тогда шов сходится сам, без кроссфейда.
func _drone(sec: float, base: float, semitones: Array) -> PackedFloat32Array:
	var n: int = int(float(RATE_LOOP) * sec)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var freqs: PackedFloat32Array = PackedFloat32Array()
	for v: Variant in semitones:
		var f: float = base * pow(2.0, float(int(v)) / 12.0)
		# Округление до целого числа периодов на луп.
		freqs.append(maxf(1.0, roundf(f * sec)) / sec)
	for i: int in n:
		var t: float = float(i) / float(RATE_LOOP)
		var s: float = 0.0
		for j: int in freqs.size():
			# Верхние голоса тише: иначе аккорд звучит как сирена.
			s += sin(TAU * freqs[j] * t) / float(j + 2)
		# Медленное «дыхание» громкости — целое число периодов на луп.
		out[i] = s * 0.28 * (0.75 + 0.25 * sin(TAU * 2.0 * t / sec))
	return out

## Сшивает шов лупа: хвост подмешивается в голову встречными косинусами.
## Без этого шумовой луп щёлкает раз в несколько секунд, и это слышно.
func _seam(src: PackedFloat32Array) -> PackedFloat32Array:
	var n: int = src.size()
	var m: int = int(float(n) * SEAM)
	if m < 2:
		return src
	var out: PackedFloat32Array = src.duplicate()
	for i: int in m:
		var k: float = float(i) / float(m)
		var g: float = 0.5 - 0.5 * cos(PI * k)          # 0 -> 1
		out[i] = src[i] * g + src[n - m + i] * (1.0 - g)
	out.resize(n - m)                                    # хвост уже вмешан в голову
	return out

# --- Запись ---------------------------------------------------------------

func _rng(id: String) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(id.hash())
	return rng

func _write(path: String, samples: PackedFloat32Array, rate: int, looped: bool) -> int:
	var n: int = samples.size()
	var buf: PackedByteArray = PackedByteArray()
	buf.resize(n * 2)
	for i: int in n:
		buf.encode_s16(i * 2, clampi(int(samples[i] * 32000.0), -32768, 32767))
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = buf
	if looped:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = n - 1
	var err: Error = wav.save_to_wav(path)
	if err != OK:
		push_error("gen_placeholder_sfx: %s не записан, ошибка %d" % [path, err])
		return 0
	_write_import(path, looped)
	return 1

## ⚠️ Луп живёт НЕ в .wav, а в .import: save_to_wav пишет голый PCM, а
## loop_mode/loop_begin — параметры импортёра. Без этой правки эмбиент
## отыгрывает свои четыре секунды и молча замолкает на весь забег.
##
## Существующий .import правим построчно, а не перезаписываем: иначе Godot
## заново выдаст uid, и git будет показывать изменения на каждой перегенерации.
func _write_import(wav_path: String, looped: bool) -> void:
	var path: String = wav_path + ".import"
	var loop: String = "1" if looped else "0"
	if FileAccess.file_exists(path):
		var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
		var out: PackedStringArray = PackedStringArray()
		for line: String in lines:
			if line.begins_with("edit/loop_mode="):
				out.append("edit/loop_mode=" + loop)
			elif line.begins_with("compress/mode="):
				out.append("compress/mode=0")
			else:
				out.append(line)
		_save_text(path, "\n".join(out))
		return
	_save_text(path, IMPORT_TEMPLATE % [wav_path, loop])

## Компрессия выключена намеренно: QOA — сжатие с потерями, а на шве лупа
## потери слышны щелчком. Файлы плейсхолдеров и так меньше двух мегабайт.
const IMPORT_TEMPLATE: String = """[remap]

importer="wav"
type="AudioStreamWAV"

[deps]

source_file="%s"
dest_files=[]

[params]

force/8_bit=false
force/mono=false
force/max_rate=false
force/max_rate_hz=44100
edit/trim=false
edit/normalize=false
edit/loop_mode=%s
edit/loop_begin=0
edit/loop_end=-1
compress/mode=0
"""

func _save_text(path: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("gen_placeholder_sfx: не открыть %s" % path)
		return
	f.store_string(text)
	f.close()
