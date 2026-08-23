extends SceneTree
## Лист существа Прихода из отобранного арта (ART-integration §1, «существа»).
##
##   godot --headless -s res://tools/gen_creature.gd
##   godot --headless --import --quit
##
## Ряд = состояние, столбец = кадр; порядок рядов — контракт с
## game/creature_view.gd (CreatureView.Row), его сторожит tests/test_visual.gd.

const Art: GDScript = preload("res://tools/art_lib.gd")

const CELL: Vector2i = Vector2i(32, 24)
const COLS: int = 8
const OUT_PNG: String = "res://assets/sprites/creature.png"

## Порядок рядов = CreatureView.Row.
##   sheet — размер листа-исходника;
##   crop  — исходник нарезан клеткой ДРУГОГО размера (плавание пришло сеткой
##           32×32) и каждый кадр вписывается в нашу клетку;
##   single — один кадр на весь ряд.
const ROWS: Array[Dictionary] = [
	{"name": "idle", "src": "creature_design_v2_03_pick.png", "single": true},
	{"name": "move", "src": "creature_move_v1_01_pick.png", "sheet": Vector2i(64, 96)},
	{"name": "gnaw", "src": "creature_gnaw_v1_01_pick.png", "sheet": Vector2i(64, 96)},
	{"name": "swim", "src": "creature_swim_v1_01_pick.png", "sheet": Vector2i(160, 128),
		"crop": Vector2i(32, 32)},
]

func _initialize() -> void:
	var edge: Color = Art.darkest(Art.palette())
	var sheet: Image = Image.create(CELL.x * COLS, CELL.y * ROWS.size(), false,
		Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))
	for r: int in ROWS.size():
		var row: Dictionary = ROWS[r]
		var src: String = str(row["src"])
		var frames: Array[Image] = []
		if bool(row.get("single", false)):
			var one: Image = Art.load_pick(src, CELL.x, CELL.y)
			if one == null:
				continue
			for _i: int in COLS:
				frames.append(one)
		else:
			var size: Vector2i = row["sheet"]
			var strip: Image = Art.load_pick(src, size.x, size.y)
			if strip == null:
				continue
			var cut: Vector2i = row.get("crop", CELL)
			for f: Image in Art.frames(strip, cut):
				frames.append(f if cut == CELL else Art.fit_into(f, CELL))
		for c: int in mini(COLS, frames.size()):
			sheet.blit_rect(Art.outline(frames[c], edge),
				Rect2i(Vector2i.ZERO, CELL), Vector2i(c * CELL.x, r * CELL.y))
		print("ряд %d %-5s ← %s (%d кадров, взято %d)"
			% [r, str(row["name"]), src, frames.size(), mini(COLS, frames.size())])
	Art.save(sheet, OUT_PNG)
	quit(1 if Art.fails > 0 else 0)
