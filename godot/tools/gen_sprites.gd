extends SceneTree
## Заглушки спрайтов мира (промпт 18 п.9).
##   godot --headless -s res://tools/gen_sprites.gd
##   godot --headless --import --quit
##
## Настоящего арта ещё нет (assets/sprites/README.md — список для художника),
## поэтому рисуем программно, но по правилам пиксель-арта: силуэт, два тона
## и светлая кромка сверху. Плоский прямоугольник читается как «программерский
## арт» именно из-за отсутствия этих трёх вещей, а не из-за цвета.
##
## Контракт с кодом: кадры лежат в ряд, размер кадра фиксирован, origin —
## низ-центр (research/29 §1). Художник перерисовывает PNG, не трогая код.

const OUT_DIR: String = "res://assets/sprites/"

const AGENT_W: int = 16
const AGENT_H: int = 24
## 4 кадра ходьбы + 2 кадра работы (промпт 18 п.9).
const AGENT_FRAMES: int = 6
const CREATURE_W: int = 32
const CREATURE_H: int = 24

# Палитра docs/01 §4: тело тёплое, кромка светлее, тень холоднее.
const SKIN: Color = Color("d8c8a8")
const SKIN_DARK: Color = Color("a4906f")
const EDGE: Color = Color("f0e6cf")
const CLOTH: Color = Color("6a7c74")
const CLOTH_DARK: Color = Color("46564f")
const CREATURE_BODY: Color = Color("1c2a30")
const CREATURE_EDGE: Color = Color("38505a")

## ⚠️ С этапа 18 эти файлы собираются из настоящего арта (tools/gen_agent.gd и tools/gen_creature.gd).
## Запуск без флага затёр бы арт заглушками, поэтому он требует явного
## `-- stub` — заглушки нужны разве что для «чистого» проекта.
func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("stub"):
		print("заглушки не тронуты: настоящий арт собирает tools/gen_agent.gd / tools/gen_creature.gd. Нужны заглушки — добавь `-- stub`")
		quit(0)
		return
	var ok: int = 0
	ok += _write_agent()
	ok += _write_creature()
	print("спрайты записаны: %d" % ok)
	quit(0 if ok == 2 else 1)

## Агент: голова, тело в робе, две ноги. Кадры ходьбы отличаются положением
## ног и покачиванием на пиксель — этого хватает, чтобы движение читалось.
func _write_agent() -> int:
	var img: Image = Image.create(AGENT_W * AGENT_FRAMES, AGENT_H, false,
		Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for f: int in AGENT_FRAMES:
		var ox: int = f * AGENT_W
		var work: bool = f >= 4
		# Рабочие кадры — наклон вперёд на пиксель: силуэт сразу читается
		# как «занят», а не «стоит».
		var lean: int = 1 if work and f == 5 else 0
		var bob: int = 1 if f == 1 or f == 3 else 0
		_fill(img, ox + 5 + lean, 2 + bob, 6, 6, SKIN)            # голова
		_fill(img, ox + 5 + lean, 2 + bob, 6, 1, EDGE)            # кромка сверху
		_fill(img, ox + 4 + lean, 8 + bob, 8, 9, CLOTH)           # роба
		_fill(img, ox + 4 + lean, 8 + bob, 8, 1, CLOTH.lightened(0.18))
		_fill(img, ox + 4 + lean, 14 + bob, 8, 3, CLOTH_DARK)     # подол в тени
		# Ноги: в кадрах 1 и 3 шаг, в 0 и 2 стойка.
		var stride: int = 2 if f == 1 else (-2 if f == 3 else 0)
		_fill(img, ox + 5 + stride, 17 + bob, 2, 7, SKIN_DARK)
		_fill(img, ox + 9 - stride, 17 + bob, 2, 7, SKIN_DARK)
		if work:
			# Инструмент в руках: короткая палка вбок.
			_fill(img, ox + 12, 10 + (1 if f == 5 else 0), 4, 1, SKIN_DARK)
	return _save(img, "agent.png")

## Существо: низкий тёмный силуэт с горбом и светлой кромкой по спине.
func _write_creature() -> int:
	var img: Image = Image.create(CREATURE_W, CREATURE_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x: int in CREATURE_W:
		var t: float = float(x) / float(CREATURE_W - 1)
		# Горб ближе к «голове» слева, хвост сходит на нет справа.
		var h: int = int(round(float(CREATURE_H) * (0.75 - 0.55 * t * t)))
		var top: int = CREATURE_H - h
		for y: int in range(top, CREATURE_H):
			img.set_pixel(x, y, CREATURE_EDGE if y < top + 2 else CREATURE_BODY)
	return _save(img, "creature.png")

func _fill(img: Image, x: int, y: int, w: int, h: int, col: Color) -> void:
	for dx: int in w:
		for dy: int in h:
			var px: int = x + dx
			var py: int = y + dy
			if px < 0 or py < 0 or px >= img.get_width() or py >= img.get_height():
				continue
			img.set_pixel(px, py, col)

func _save(img: Image, name: String) -> int:
	if img.save_png(OUT_DIR + name) != OK:
		push_error("gen_sprites: не записан %s" % name)
		return 0
	return 1
