extends SceneTree
## Заглушки трёх параллакс-слоёв (промпт 18 п.7).
##   godot --headless -s res://tools/gen_parallax.gd
##   godot --headless --import --quit
##
## Дальний берег, туманная гряда, облака. Программные силуэты в палитре
## docs/01 §4: художнику останется перерисовать три PNG, не трогая сцену.
##
## Ширина 640 = ширина вьюпорта: Parallax2D повторяет ровно на этот шаг, шва
## не будет. Высота разная — слои стоят на разной высоте кадра.

const OUT_DIR: String = "res://assets/sprites/"
const W: int = 640

## Слой: имя, высота, цвет силуэта, число «горбов», их высота, зерно.
const LAYERS: Array[Array] = [
	["parallax_far", 96, Color("16262e"), 5, 46, 11],
	["parallax_mist", 64, Color("1e343d"), 3, 26, 23],
	["parallax_clouds", 48, Color("2a4550"), 7, 18, 37],
]

## ⚠️ С этапа 18 эти файлы собираются из настоящего арта (tools/gen_decor.gd).
## Запуск без флага затёр бы арт заглушками, поэтому он требует явного
## `-- stub` — заглушки нужны разве что для «чистого» проекта.
func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("stub"):
		print("заглушки не тронуты: настоящий арт собирает tools/gen_decor.gd. Нужны заглушки — добавь `-- stub`")
		quit(0)
		return
	var n: int = 0
	for row: Array in LAYERS:
		n += _write(str(row[0]), int(row[1]), row[2] as Color, int(row[3]),
			int(row[4]), int(row[5]))
	print("параллакс-слои: %d" % n)
	quit(0 if n == LAYERS.size() else 1)

func _write(name: String, h: int, col: Color, humps: int, amp: int, seed_value: int) -> int:
	var img: Image = Image.create(W, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	# Профиль силуэта: сумма синусов + мелкий шум, квантованный по 2 px —
	# гладкая кривая на пиксельном фоне читается как чужеродная.
	var top: PackedInt32Array = PackedInt32Array()
	var phase: PackedFloat32Array = PackedFloat32Array()
	for i: int in humps:
		phase.append(rng.randf_range(0.0, TAU))
	for x: int in W:
		var v: float = 0.0
		for i: int in humps:
			var k: float = float(i + 1)
			v += sin(float(x) / float(W) * TAU * k + phase[i]) / k
		var y: int = h - int(float(amp) * (0.45 + 0.35 * v))
		top.append(clampi(int(round(float(y) / 2.0)) * 2, 2, h - 1))
	# Кромка светлее тела на один тон: силуэт без кромки читается как дыра.
	var edge: Color = col.lightened(0.22)
	for x: int in W:
		for y: int in range(top[x], h):
			img.set_pixel(x, y, edge if y < top[x] + 2 else col)
	var path: String = OUT_DIR + name + ".png"
	if img.save_png(path) != OK:
		push_error("gen_parallax: не записан %s" % path)
		return 0
	return 1
