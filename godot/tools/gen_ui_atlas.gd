extends SceneTree
## Атлас интерфейса (промпт 18 п.8).
##   godot --headless -s res://tools/gen_ui_atlas.gd
##   godot --headless --import --quit
##   godot --headless -s res://tools/gen_theme.gd     # пересобрать тему
##
## Рисовать нечем, поэтому рамки собираются программно и «в стиле»: однотон,
## светлая кромка сверху и слева, тёмная снизу и справа. Это ровно та фактура,
## которую даёт нормальный пиксельный 9-patch, и художнику останется
## перерисовать PNG, не трогая ни тему, ни компоненты.
##
## Контракт с ui/theme/theme_factory.gd: кадры лежат в ряд по CELL пикселей,
## порядок = константа FRAMES, поля 9-patch = MARGIN.

const OUT: String = "res://assets/sprites/ui_atlas.png"
const CELL: int = 16
## Поле 9-patch: угол 5 px, центр растягивается.
const MARGIN: int = 5

## Порядок кадров = их индекс в атласе. Имена читает theme_factory.
##
## Акцентных и опасных кнопок в атласе НЕТ намеренно: их цвет зависит от
## пресета для дальтоников (UIPalette), а кадр атласа — запечён. Такие стили
## остаются плоскими, иначе доступность ломается ради текстуры.
const FRAMES: Array[String] = ["panel", "raise", "hover", "pressed", "dark"]

func _initialize() -> void:
	var img: Image = Image.create(CELL * FRAMES.size(), CELL, false,
		Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i: int in FRAMES.size():
		_frame(img, i * CELL, _bg_of(FRAMES[i]), _border_of(FRAMES[i]))
	if img.save_png(OUT) != OK:
		push_error("gen_ui_atlas: не записан %s" % OUT)
		quit(1)
		return
	print("атлас интерфейса: %s, кадров %d" % [OUT, FRAMES.size()])
	quit(0)

static func _bg_of(kind: String) -> Color:
	match kind:
		"panel": return UITokens.PANEL_BG
		"dark": return UITokens.PAPER
		"raise": return UITokens.RAISE
		"hover": return UITokens.RAISE.lightened(0.08)
		"pressed": return UITokens.RAISE.darkened(0.20)
	return UITokens.RAISE

static func _border_of(kind: String) -> Color:
	match kind:
		"panel": return UITokens.BORDER
		"dark": return UITokens.BORDER
		"hover": return UITokens.BORDER_STRONG
		"pressed": return UITokens.ACCENT_SHADE
	return UITokens.BORDER

## Один кадр: заливка, рамка, светлая внутренняя кромка сверху-слева и
## тёмная снизу-справа. Без этих двух линий рамка выглядит нарисованной
## в редакторе, а не собранной художником.
static func _frame(img: Image, ox: int, bg: Color, border: Color) -> void:
	for x: int in CELL:
		for y: int in CELL:
			img.set_pixel(ox + x, y, bg)
	for i: int in CELL:
		img.set_pixel(ox + i, 0, border)
		img.set_pixel(ox + i, CELL - 1, border)
		img.set_pixel(ox, i, border)
		img.set_pixel(ox + CELL - 1, i, border)
	if bg.a <= 0.01:
		return
	var hi: Color = bg.lightened(0.18)
	var lo: Color = bg.darkened(0.22)
	for i: int in range(1, CELL - 1):
		img.set_pixel(ox + i, 1, hi)
		img.set_pixel(ox + 1, i, hi)
		img.set_pixel(ox + i, CELL - 2, lo)
		img.set_pixel(ox + CELL - 2, i, lo)
