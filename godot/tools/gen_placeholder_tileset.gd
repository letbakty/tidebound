extends SceneTree
## Генератор заглушечного тайлсета (этап 02; на этапе 18 его заменит арт).
##   godot --headless -s res://tools/gen_placeholder_tileset.gd
##   godot --headless --import --quit          # если PNG создан впервые
##   godot --headless -s res://tools/gen_placeholder_tileset.gd
##
## Двухпроходность неизбежна: .tres должен ССЫЛАТЬСЯ на PNG (тогда художник
## просто перерисует файл), а сослаться можно только на уже импортированный
## ресурс. Первый проход пишет PNG, второй — тайлсет.

const TILE: int = 32
const OUT_PNG: String = "res://assets/sprites/placeholder_tiles.png"
const OUT_TILESET: String = "res://data/tilesets/placeholder.tres"

## Порядок = atlas_coords.x. Индексы фиксированы: на них ссылается world.gd.
const KINDS: Array[String] = ["cliff", "sand", "ruins", "ladder", "back", "water_edge"]
const COLORS: Array[Color] = [
	Color("6b6257"),   # 0 камень утёса
	Color("d8c08a"),   # 1 песок отмели
	Color("4a5b63"),   # 2 руины
	Color("8a6a3f"),   # 3 лестница
	Color("3a352f"),   # 4 задняя стенка ниши: без неё срез читается как
	                   #   парящие полки, а не как утёс
	Color("2d6b7a"),   # 5 кромка (запас под этап 18)
]

## ⚠️ С этапа 18 PNG атласа собирает tools/gen_tiles.gd из отобранного арта
## (art-rd/processed/*_pick). Здесь остался только тайлсет: запустить этот
## генератор без флага значило бы затереть арт шестью квадратами.
## Заглушки нужны разве что для «чистого» проекта — тогда: `-- stub`.
func _initialize() -> void:
	if OS.get_cmdline_user_args().has("stub"):
		_write_png()
	elif not ResourceLoader.exists(OUT_PNG):
		push_warning("gen_placeholder_tileset: атласа нет; собери tools/gen_tiles.gd")
	var tex: Texture2D = load(OUT_PNG) as Texture2D
	if tex == null:
		print("PNG записан. Теперь: godot --headless --import --quit, затем повтори запуск.")
		quit(0)
		return
	_write_tileset(tex)
	quit(0)

func _write_png() -> void:
	var img: Image = Image.create(TILE * COLORS.size(), TILE, false, Image.FORMAT_RGBA8)
	for i: int in COLORS.size():
		var c: Color = COLORS[i]
		img.fill_rect(Rect2i(i * TILE, 0, TILE, TILE), c)
		# Тёмная кромка сверху: без неё ярусы не читаются вообще без арта.
		img.fill_rect(Rect2i(i * TILE, 0, TILE, 2), c.darkened(0.35))
		# Светлая линия снизу — «пол» яруса.
		img.fill_rect(Rect2i(i * TILE, TILE - 1, TILE, 1), c.lightened(0.12))
	var err: int = img.save_png(OUT_PNG)
	if err != OK:
		push_error("save_png: код %d" % err)

func _write_tileset(tex: Texture2D) -> void:
	var src: TileSetAtlasSource = TileSetAtlasSource.new()
	# texture ДО create_tile: иначе источник не знает своей сетки и
	# create_tile молча ничего не делает (research/12 §2).
	src.texture = tex
	src.texture_region_size = Vector2i(TILE, TILE)
	for i: int in COLORS.size():
		src.create_tile(Vector2i(i, 0))

	var ts: TileSet = TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_source(src, 0)                       # source_id = 0
	var err: int = ResourceSaver.save(ts, OUT_TILESET)
	if err != OK:
		push_error("ResourceSaver.save: код %d" % err)
		return
	print("тайлсет готов: ", OUT_TILESET, " (виды: ", ", ".join(KINDS), ")")
