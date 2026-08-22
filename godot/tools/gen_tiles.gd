extends SceneTree
## Сборка атласа тайлов из отобранного арта (prompts/ART-integration §1–§3).
##
##   godot --headless -s res://tools/gen_tiles.gd
##   godot --headless --import --quit
##
## Почему тул, а не «положить PNG руками»: атлас — это ШЕСТЬ слотов в одном
## файле, и порядок слотов — контракт с game/world.gd и data/tilesets/
## placeholder.tres. Собирать его вручную значит однажды перепутать колонку и
## получить руины на верхнем ярусе.
##
## ⚠️ Имя выходного файла и размер атласа НЕ меняются: на них ссылается
## data/tilesets/placeholder.tres, а data/ правит другой агент. Слот, для
## которого арта ещё нет, заполняется прежней программной заглушкой — чтобы
## интеграция шла по одному семейству, а не всем сразу.
##
## Источник — art-rd/processed/, ТОЛЬКО файлы с суффиксом _pick (§0 промпта).

const TILE: int = 32
const OUT_PNG: String = "res://assets/sprites/placeholder_tiles.png"
const SRC_DIR: String = "res://../art-rd/processed/"

## Слоты в порядке atlas_coords.x. Порядок фиксирован: на него ссылается
## world.gd (T_CLIFF=0, T_SAND=1, T_RUINS=2, T_LADDER=3, T_BACK=4, кромка=5).
## `src` пустой = арта ещё нет, рисуем прежнюю заглушку цветом `color`.
const SLOTS: Array[Dictionary] = [
	{"name": "cliff",      "src": "tile_dry_v1_04_pick.png", "color": "6b6257"},
	{"name": "sand",       "src": "",                        "color": "d8c08a"},
	{"name": "ruins",      "src": "",                        "color": "4a5b63"},
	{"name": "ladder",     "src": "",                        "color": "8a6a3f"},
	{"name": "back",       "src": "",                        "color": "3a352f"},
	{"name": "water_edge", "src": "",                        "color": "2d6b7a"},
]

var _fails: int = 0

func _initialize() -> void:
	var img: Image = Image.create(TILE * SLOTS.size(), TILE, false, Image.FORMAT_RGBA8)
	for i: int in SLOTS.size():
		var slot: Dictionary = SLOTS[i]
		var src: String = str(slot["src"])
		if src.is_empty():
			_draw_stub(img, i, Color(str(slot["color"])))
			print("слот %d %-11s — заглушка" % [i, str(slot["name"])])
			continue
		var tile: Image = _load_pick(src)
		if tile == null:
			_draw_stub(img, i, Color(str(slot["color"])))
			continue
		img.blit_rect(tile, Rect2i(0, 0, TILE, TILE), Vector2i(i * TILE, 0))
		print("слот %d %-11s ← %s" % [i, str(slot["name"]), src])
	var err: int = img.save_png(OUT_PNG)
	if err != OK:
		push_error("gen_tiles: save_png код %d" % err)
		quit(1)
		return
	print("атлас: %s (%dx%d)" % [OUT_PNG, img.get_width(), img.get_height()])
	quit(1 if _fails > 0 else 0)

## Загрузка исходника с проверками, которые иначе всплывут в игре: не тот
## размер (тайл поедет), полупрозрачность (в пиксель-арте это всегда
## случайный антиалиасинг кисти — research/29 §3.3).
func _load_pick(file: String) -> Image:
	if not file.contains("_pick"):
		push_error("gen_tiles: %s без суффикса _pick — в игру идут только отобранные" % file)
		_fails += 1
		return null
	var img: Image = Image.new()
	var err: int = img.load(SRC_DIR + file)
	if err != OK:
		push_error("gen_tiles: не читается %s (код %d)" % [file, err])
		_fails += 1
		return null
	if img.get_width() != TILE or img.get_height() != TILE:
		push_error("gen_tiles: %s имеет %dx%d, ждали %dx%d"
			% [file, img.get_width(), img.get_height(), TILE, TILE])
		_fails += 1
		return null
	img.convert(Image.FORMAT_RGBA8)
	var semi: int = 0
	for y: int in TILE:
		for x: int in TILE:
			var a: float = img.get_pixel(x, y).a
			if a > 0.004 and a < 0.996:
				semi += 1
	if semi > 0:
		push_error("gen_tiles: %s — %d полупрозрачных пикселей" % [file, semi])
		_fails += 1
		return null
	return img

## Прежняя программная заглушка (tools/gen_placeholder_tileset.gd): тёмная
## кромка сверху и светлая линия снизу, иначе ярусы не читаются вовсе.
func _draw_stub(img: Image, i: int, c: Color) -> void:
	img.fill_rect(Rect2i(i * TILE, 0, TILE, TILE), c)
	img.fill_rect(Rect2i(i * TILE, 0, TILE, 2), c.darkened(0.35))
	img.fill_rect(Rect2i(i * TILE, TILE - 1, TILE, 1), c.lightened(0.12))
