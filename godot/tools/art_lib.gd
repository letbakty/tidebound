extends RefCounted
## Общая часть сборщиков арта (gen_tiles, gen_agent, gen_creature, gen_buildings,
## gen_ui_atlas). Все они делают одно и то же: взять отобранный файл из
## art-rd/processed, проверить его и разложить по кадрам.
##
## ⚠️ Почему без class_name: res://tools/* исключён из экспортных пресетов.
## Глобальный класс из исключённой папки попал бы в список классов сборки, а
## самого файла в ней бы не было. Подключать так:
##
##     const Art: GDScript = preload("res://tools/art_lib.gd")
##     var img: Image = Art.load_pick("tile_dry_v1_04_pick.png", 32, 32)
##
## Проверки намеренно ЖЁСТКИЕ и валят сборщик: половина дефектов арта — это
## «не тот размер» и «полупрозрачная кайма», и оба видны только в игре, когда
## искать причину уже поздно.

const SRC_DIR: String = "res://../art-rd/processed/"
const GPL: String = "res://../art/tidebound.gpl"

## Счётчик отказов за прогон: сборщик обязан выйти с ненулевым кодом, а не
## молча положить в игру половину атласа.
static var fails: int = 0

## Загрузка отобранного исходника. `want_w`/`want_h` = 0 — размер не проверяем
## (лист режется на кадры дальше по коду).
static func load_pick(file: String, want_w: int = 0, want_h: int = 0) -> Image:
	# В игру идут только отобранные файлы (ART-integration §0). Остальное —
	# черновики: они остаются в art-rd/ как история.
	if not file.contains("_pick"):
		return _fail("%s без суффикса _pick — в игру идут только отобранные" % file)
	var img: Image = Image.new()
	var err: int = img.load(SRC_DIR + file)
	if err != OK:
		return _fail("не читается %s (код %d)" % [file, err])
	img.convert(Image.FORMAT_RGBA8)
	if want_w > 0 and img.get_width() != want_w:
		return _fail("%s шириной %d, ждали %d" % [file, img.get_width(), want_w])
	if want_h > 0 and img.get_height() != want_h:
		return _fail("%s высотой %d, ждали %d" % [file, img.get_height(), want_h])
	var semi: int = semi_pixels(img)
	if semi > 0:
		return _fail("%s — %d полупрозрачных пикселей" % [file, semi])
	return img

## Полупрозрачность в пиксель-арте — почти всегда случайный антиалиасинг кисти
## (research/29 §3.3). На Nearest она даёт грязную кайму вокруг спрайта.
static func semi_pixels(img: Image) -> int:
	var n: int = 0
	for y: int in img.get_height():
		for x: int in img.get_width():
			var a: float = img.get_pixel(x, y).a
			if a > 0.004 and a < 0.996:
				n += 1
	return n

## Палитра проекта. Источник правды по цвету — art/tidebound.gpl, собранный
## из самого арта (tools/gen_palette.gd); HEX руками не копировать.
static func palette() -> PackedColorArray:
	var out: PackedColorArray = []
	var f: FileAccess = FileAccess.open(GPL, FileAccess.READ)
	if f == null:
		_fail("не читается палитра %s" % GPL)
		return out
	while not f.eof_reached():
		var line: String = f.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#") or not line[0].is_valid_int():
			continue
		var parts: PackedStringArray = line.split("\t")[0].split(" ", false)
		if parts.size() < 3:
			continue
		out.append(Color8(int(parts[0]), int(parts[1]), int(parts[2])))
	f.close()
	return out

## Ближайший цвет палитры. Расстояние — в линейном RGB: sRGB-разница врёт на
## тёмных тонах, а у нас вся нижняя половина палитры тёмная.
static func snap(c: Color, pal: PackedColorArray) -> Color:
	var best: Color = c
	var best_d: float = INF
	var cl: Color = c.srgb_to_linear()
	for p: Color in pal:
		var pl: Color = p.srgb_to_linear()
		var d: float = (cl.r - pl.r) * (cl.r - pl.r) + (cl.g - pl.g) * (cl.g - pl.g) \
			+ (cl.b - pl.b) * (cl.b - pl.b)
		if d < best_d:
			best_d = d
			best = p
	return best

## Затемнение К ПАЛИТРЕ: производный тайл остаётся в тех же 32 цветах и
## читается как та же порода в тени, а не как отдельный ассет.
##
## ⚠️ Почему не «каждый пиксель к ближайшему»: у тайла три цвета, и после
## умножения все три садятся на ОДИН ближайший — тайл становится плоской
## заливкой, то есть ровно тем, от чего уходили. Поэтому цвета разбираются
## по УБЫВАНИЮ ПЛОЩАДИ и каждый занимает свою запись палитры: главный тон
## получает лучшее совпадение, остальные — ближайшее из оставшихся, и
## текстура выживает.
static func darken_to_palette(img: Image, k: float, pal: PackedColorArray) -> Image:
	var area: Dictionary[Color, int] = {}
	for y: int in img.get_height():
		for x: int in img.get_width():
			var c: Color = img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			area[c] = int(area.get(c, 0)) + 1
	var order: Array[Color] = []
	order.assign(area.keys())
	order.sort_custom(func(a: Color, b: Color) -> bool:
		return int(area[a]) > int(area[b]))
	var used: Dictionary[Color, bool] = {}
	var map: Dictionary[Color, Color] = {}
	for c: Color in order:
		var target: Color = Color(c.r * k, c.g * k, c.b * k)
		var free: PackedColorArray = []
		for p: Color in pal:
			if not used.has(p):
				free.append(p)
		var pick: Color = snap(target, free) if not free.is_empty() else target
		used[pick] = true
		map[c] = pick
	var out: Image = Image.create(img.get_width(), img.get_height(), false,
		Image.FORMAT_RGBA8)
	for y2: int in img.get_height():
		for x2: int in img.get_width():
			var src: Color = img.get_pixel(x2, y2)
			out.set_pixel(x2, y2, Color(0, 0, 0, 0) if src.a < 0.5 else map[src])
	return out

## Самый тёмный цвет палитры. Кромку спрайта берём отсюда, а не HEX-ом:
## палитра — единственный источник правды по цвету (research/29 §3.1).
static func darkest(pal: PackedColorArray) -> Color:
	var best: Color = Color.BLACK
	var best_l: float = INF
	for p: Color in pal:
		var l: float = p.get_luminance()
		if l < best_l:
			best_l = l
			best = p
	return best

## Тёмная кромка вокруг силуэта — 1 px по четырём сторонам.
##
## ⚠️ Это не украшение, а условие читаемости. Агент занимает 6 пикселей в
## ширину, и в цвете охряного камня он на охряном камне ПРОПАДАЕТ: проверено
## снимком игры, а не глазами по файлу. Кромка даёт силуэту границу на любом
## фоне — и на камне, и на воде.
##
## По диагоналям НЕ обводим: на 16 px это утолщает силуэт до нечитаемой кляксы.
static func outline(img: Image, color: Color) -> Image:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var out: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	out.copy_from(img)
	for y: int in h:
		for x: int in w:
			if img.get_pixel(x, y).a >= 0.5:
				continue
			var near: bool = false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1),
					Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				if img.get_pixel(nx, ny).a >= 0.5:
					near = true
					break
			if near:
				out.set_pixel(x, y, color)
	return out

## Выбить фоновый цвет в прозрачность.
##
## ⚠️ Нужно там, где генерация отдала «слой» непрозрачным холстом: полоса
## тумана нарисована на сплошном deep_ink, и как слой параллакса она закрыла
## бы собой всё небо. Ключуем ТОЧНЫЙ цвет: арт уже квантован к палитре, и
## порога с допуском тут не нужно — он съел бы настоящие тёмные пиксели.
static func key_color(img: Image, bg: Color) -> Image:
	var out: Image = Image.create(img.get_width(), img.get_height(), false,
		Image.FORMAT_RGBA8)
	out.copy_from(img)
	for y: int in img.get_height():
		for x: int in img.get_width():
			var c: Color = img.get_pixel(x, y)
			if is_equal_approx(c.r, bg.r) and is_equal_approx(c.g, bg.g) \
					and is_equal_approx(c.b, bg.b):
				out.set_pixel(x, y, Color(0, 0, 0, 0))
	return out

## Нарезка листа на кадры: слева направо, сверху вниз. Лист, который не делится
## на клетку нацело, — это всегда ошибка размера, а не «почти подходит».
static func frames(img: Image, cell: Vector2i) -> Array[Image]:
	var out: Array[Image] = []
	if img.get_width() % cell.x != 0 or img.get_height() % cell.y != 0:
		_fail("лист %dx%d не делится на кадр %dx%d"
			% [img.get_width(), img.get_height(), cell.x, cell.y])
		return out
	for row: int in img.get_height() / cell.y:
		for col: int in img.get_width() / cell.x:
			var f: Image = Image.create(cell.x, cell.y, false, Image.FORMAT_RGBA8)
			f.blit_rect(img, Rect2i(col * cell.x, row * cell.y, cell.x, cell.y),
				Vector2i.ZERO)
			out.append(f)
	return out

## Прямоугольник непрозрачного содержимого. Нужен, чтобы посадить спрайт по
## контракту origin (research/29 §1), а не по границе холста: генератор часто
## отдаёт объект «по центру», и половина спрайтов иначе тонет в полу.
static func content_rect(img: Image) -> Rect2i:
	var x0: int = img.get_width()
	var y0: int = img.get_height()
	var x1: int = -1
	var y1: int = -1
	for y: int in img.get_height():
		for x: int in img.get_width():
			if img.get_pixel(x, y).a < 0.5:
				continue
			x0 = mini(x0, x)
			y0 = mini(y0, y)
			x1 = maxi(x1, x)
			y1 = maxi(y1, y)
	if x1 < 0:
		return Rect2i(0, 0, 0, 0)
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)

## Кадр, вписанный в клетку прозрачным полем. ⚠️ Именно вписанный, а не
## растянутый: иконки построек намеренно разной формы (8×24 у лестницы,
## 24×8 у испарителя), и растягивание их врёт о пропорциях постройки.
static func fit_into(img: Image, cell: Vector2i, align_bottom: bool = false) -> Image:
	var out: Image = Image.create(cell.x, cell.y, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var src: Rect2i = content_rect(img)
	if src.size.x <= 0:
		return out
	var w: int = mini(src.size.x, cell.x)
	var h: int = mini(src.size.y, cell.y)
	var dst: Vector2i = Vector2i((cell.x - w) / 2, (cell.y - h) / 2)
	if align_bottom:
		dst.y = cell.y - h
	out.blit_rect(img, Rect2i(src.position, Vector2i(w, h)), dst)
	return out

static func save(img: Image, path: String) -> bool:
	var err: int = img.save_png(path)
	if err != OK:
		_fail("save_png %s код %d" % [path, err])
		return false
	print("  → %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	return true

static func _fail(msg: String) -> Image:
	push_error("art: " + msg)
	fails += 1
	return null
