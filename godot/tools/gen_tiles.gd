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
## data/tilesets/placeholder.tres, а data/ правит другой агент.
##
## Источник — art-rd/processed/, ТОЛЬКО файлы с суффиксом _pick (§0 промпта).

const Art: GDScript = preload("res://tools/art_lib.gd")

const TILE: int = 32
const OUT_PNG: String = "res://assets/sprites/placeholder_tiles.png"

## Слоты в порядке atlas_coords.x. Порядок фиксирован: на него ссылается
## world.gd (T_CLIFF=0, T_SAND=1, T_RUINS=2, T_LADDER=3, T_BACK=4, кромка=5).
##
## Ключи слота:
##   src     — файл в art-rd/processed;
##   module  — Vector2i(y0, высота): взять полосу исходника и повторить её до
##             32 px. Нужно там, где арт выше тайла и обязан стыковаться сам с
##             собой по вертикали (лестница);
##   darken  — производный тайл: тот же исходник, затемнённый К ПАЛИТРЕ;
##   color   — цвет прежней программной заглушки, если исходник не прочитался.
const SLOTS: Array[Dictionary] = [
	{"name": "cliff", "src": "tile_dry_v1_04_pick.png", "color": "6b6257"},
	{"name": "sand", "src": "tile_wet_v1_04_pick.png", "color": "d8c08a"},
	{"name": "ruins", "src": "tile_ruin_v1_04_pick.png", "color": "4a5b63"},
	# Лестница выше тайла: 32×96 — это ровно ярус, а слот в атласе один, и в
	# мире он повторяется трижды. Берём полосу с ОДНОЙ перекладиной и
	# повторяем её с шагом 16: у исходника перекладины идут неровно (10–13 px),
	# и любая честная нарезка дала бы двойной просвет на каждом стыке.
	{"name": "ladder", "src": "bld_ladder_wood_v1_01_pick.png",
		"module": Vector2i(24, 16), "color": "8a6a3f"},
	# Задняя стенка ниши: отдельного арта нет и не будет — это та же порода в
	# тени. Плоская заливка рядом с настоящим тайлом читается как дыра.
	{"name": "back", "src": "tile_dry_v1_04_pick.png", "darken": 0.42,
		"color": "3a352f"},
	{"name": "water_edge", "src": "tile_edge_v2_02_pick.png", "color": "2d6b7a"},
]

func _initialize() -> void:
	var pal: PackedColorArray = Art.palette()
	var img: Image = Image.create(TILE * SLOTS.size(), TILE, false, Image.FORMAT_RGBA8)
	for i: int in SLOTS.size():
		var slot: Dictionary = SLOTS[i]
		var tile: Image = _build(slot, pal)
		if tile == null:
			_draw_stub(img, i, Color(str(slot["color"])))
			print("слот %d %-11s — заглушка" % [i, str(slot["name"])])
			continue
		img.blit_rect(tile, Rect2i(0, 0, TILE, TILE), Vector2i(i * TILE, 0))
		print("слот %d %-11s ← %s%s" % [i, str(slot["name"]), str(slot["src"]),
			" (затемнён)" if slot.has("darken") else ""])
	if not Art.save(img, OUT_PNG):
		quit(2)
		return
	quit(1 if Art.fails > 0 else 0)

func _build(slot: Dictionary, pal: PackedColorArray) -> Image:
	var src: String = str(slot.get("src", ""))
	if src.is_empty():
		return null
	if slot.has("module"):
		var m: Vector2i = slot["module"]
		var sheet: Image = Art.load_pick(src, TILE, 0)
		if sheet == null or sheet.get_height() < m.x + m.y:
			return null
		var out: Image = Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
		out.fill(Color(0, 0, 0, 0))
		var y: int = 0
		while y < TILE:
			var h: int = mini(m.y, TILE - y)
			out.blit_rect(sheet, Rect2i(0, m.x, TILE, h), Vector2i(0, y))
			y += h
		return out
	var tile: Image = Art.load_pick(src, TILE, TILE)
	if tile == null:
		return null
	if slot.has("darken"):
		return Art.darken_to_palette(tile, float(slot["darken"]), pal)
	return tile

## Прежняя программная заглушка (tools/gen_placeholder_tileset.gd): тёмная
## кромка сверху и светлая линия снизу, иначе ярусы не читаются вовсе.
func _draw_stub(img: Image, i: int, c: Color) -> void:
	img.fill_rect(Rect2i(i * TILE, 0, TILE, TILE), c)
	img.fill_rect(Rect2i(i * TILE, 0, TILE, 2), c.darkened(0.35))
	img.fill_rect(Rect2i(i * TILE, TILE - 1, TILE, 1), c.lightened(0.12))
