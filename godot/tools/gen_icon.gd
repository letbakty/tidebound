extends SceneTree
## Иконка-заглушка в палитре игры (research/20 §9).
##   godot --headless -s res://tools/gen_icon.gd
## Дефолтный логотип Godot в билде — худшая из первых впечатлений.

const OUT: String = "res://icon.png"
const SIZE: int = 256

func _initialize() -> void:
	var img: Image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(UITokens.PAPER)
	# Утёс сверху, вода снизу: вертикаль — ось смысла игры.
	img.fill_rect(Rect2i(0, SIZE / 2, SIZE, SIZE / 2), UITokens.COLD_DEEP)
	img.fill_rect(Rect2i(0, SIZE / 2 - 8, SIZE, 8), UITokens.WATER_COLD)
	for step: int in 4:
		var y: int = SIZE / 2 - 8 - (step + 1) * 24
		img.fill_rect(Rect2i(step * 32, y, SIZE - step * 32, 12), UITokens.WARM)
	var err: Error = img.save_png(OUT)
	if err != OK:
		push_error("gen_icon: не сохранилась иконка (%d)" % err)
		quit(1)
		return
	print("иконка собрана: %s" % OUT)
	quit(0)
