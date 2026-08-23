extends SceneTree
## Атмосфера: параллакс, фон меню, маяк, портреты, эффекты воды, буи
## (ART-integration §1, «атмосфера» и §2 п.7).
##
##   godot --headless -s res://tools/gen_decor.gd
##   godot --headless --import --quit
##
## ⚠️ Ширина слоя параллакса — это repeat_size соответствующей Parallax2D в
## game/world.tscn. Разъезд даёт шов при повторе, и заметен он только в
## движении. Числа сторожит tests/test_visual.gd.

const Art: GDScript = preload("res://tools/art_lib.gd")

const OUT: String = "res://assets/sprites/"

## Слои параллакса: файл в игре -> исходник. Полоса тумана приходит
## непрозрачным холстом — фон выбивается в альфу, иначе слой закроет небо.
const PARALLAX: Array[Dictionary] = [
	# skirt — дальний слой продлевается вниз последней строкой пикселей.
	# ⚠️ Без этого под горизонтом зияет пустота: утёс занимает 14 ярусов, а
	# полоса берега — 128 px, и всё, что ниже неё и правее среза, приезжало
	# на экран чёрным. Видно это только в игре, на дальнем зуме.
	{"out": "parallax_far.png", "src": "par_shore_v1_01_pick.png",
		"size": Vector2i(512, 128), "skirt": 1280},
	{"out": "parallax_clouds.png", "src": "par_clouds_v1_01_pick.png",
		"size": Vector2i(512, 128)},
	{"out": "parallax_mist.png", "src": "amb_fog_v1_02_pick.png",
		"size": Vector2i(320, 64), "key_bg": true},
]

## Одиночные файлы: исходник -> имя в игре и ожидаемый размер.
const SINGLES: Array[Dictionary] = [
	{"out": "menu_bg.png", "src": "menu_bg_v1_01_pick.png", "size": Vector2i(512, 288)},
	{"out": "beacon.png", "src": "beacon_v1_02_pick.png", "size": Vector2i(16, 32)},
	{"out": "fx_splash.png", "src": "fx_splash_v1_01_pick.png", "size": Vector2i(96, 96)},
	{"out": "fx_ripple.png", "src": "fx_ripple_v1_01_pick.png", "size": Vector2i(128, 128)},
]

## Портреты агентов для карточки: восемь силуэтов в ряд.
const PORTRAITS: PackedStringArray = [
	"amb_portraits_v1_01_pick.png", "amb_portraits_v1_02_pick.png",
	"amb_portraits_v1_03_pick.png", "amb_portraits_v1_04_pick.png",
	"amb_portraits_v1_05_pick.png", "amb_portraits_v1_06_pick.png",
	"amb_portraits_v1_07_pick.png", "amb_portraits_v1_08_pick.png",
]
const PORTRAIT: int = 32

## Буи на воде. v1_03 не берём: он приехал с непрозрачной подложкой, то есть
## серым прямоугольником поверх воды.
const BUOYS: PackedStringArray = [
	"amb_buoy_v1_01_pick.png", "amb_buoy_v1_04_pick.png",
]
const BUOY: int = 16

func _initialize() -> void:
	var deep: Color = Art.darkest(Art.palette())
	for layer: Dictionary in PARALLAX:
		var size: Vector2i = layer["size"]
		var img: Image = Art.load_pick(str(layer["src"]), size.x, size.y)
		if img == null:
			continue
		if bool(layer.get("key_bg", false)):
			img = Art.key_color(img, deep)
		var skirt: int = int(layer.get("skirt", 0))
		if skirt > size.y:
			img = _with_skirt(img, skirt)
		Art.save(img, OUT + str(layer["out"]))
	for one: Dictionary in SINGLES:
		var s: Vector2i = one["size"]
		var i2: Image = Art.load_pick(str(one["src"]), s.x, s.y)
		if i2 != null:
			Art.save(i2, OUT + str(one["out"]))
	_strip(PORTRAITS, PORTRAIT, PORTRAIT, OUT + "portraits.png")
	_strip(BUOYS, BUOY, BUOY, OUT + "buoys.png")
	quit(1 if Art.fails > 0 else 0)

## Продление слоя вниз — ровным цветом нижней строки. Плоская заливка PNG жмёт
## почти в ноль, а альтернатива — большой ColorRect в сцене, то есть второй
## источник правды по цвету глубины.
##
## ⚠️ Именно ЦВЕТОМ, а не повтором самой строки: повтор растягивает камни и
## пену в вертикальные полосы на треть экрана, и они читаются как дефект.
func _with_skirt(img: Image, height: int) -> Image:
	var out: Image = Image.create(img.get_width(), height, false, Image.FORMAT_RGBA8)
	out.blit_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i.ZERO)
	var last: int = img.get_height() - 1
	var area: Dictionary[Color, int] = {}
	for x: int in img.get_width():
		var c: Color = img.get_pixel(x, last)
		area[c] = int(area.get(c, 0)) + 1
	var fill: Color = Color(0, 0, 0, 0)
	var best: int = -1
	for c2: Color in area:
		if int(area[c2]) > best:
			best = int(area[c2])
			fill = c2
	out.fill_rect(Rect2i(0, img.get_height(), img.get_width(),
		height - img.get_height()), fill)
	return out

## Лента из отдельных файлов одного размера: кадр = порядковый номер.
func _strip(files: PackedStringArray, w: int, h: int, out_path: String) -> void:
	var strip: Image = Image.create(w * files.size(), h, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0, 0, 0, 0))
	for i: int in files.size():
		var img: Image = Art.load_pick(files[i], w, h)
		if img == null:
			continue
		strip.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(i * w, 0))
	Art.save(strip, out_path)
