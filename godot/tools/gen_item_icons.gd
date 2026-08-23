extends SceneTree
## Атлас иконок предметов из отобранного арта.
##
## ⚠️ Не путать с tools/gen_icon.gd: тот рисует иконку ПРИЛОЖЕНИЯ (ART-integration §2 п.6).
##
##   godot --headless -s res://tools/gen_item_icons.gd
##   godot --headless --import --quit
##
## Один файл вместо тринадцати: иконка предмета встречается в чипе ресурса, в
## сетке склада, в котомке агента и в тостах — то есть в десятках Control сразу.
## Атлас нужен ради удобства скина, а не ради производительности (research/29 §4).
##
## Порядок кадров — АЛФАВИТ id предмета: он же считается в
## ui/components/icon_stub.gd, и оба списка сторожит tests/test_ui.gd.

const Art: GDScript = preload("res://tools/art_lib.gd")

const CELL: int = 16
const OUT_PNG: String = "res://assets/sprites/item_icons.png"

## id предмета (data/items/*.tres) -> файл. Взята первая серия v1_01: вторая
## (v1_02) осталась запасной, но мешать серии нельзя — набор обязан выглядеть
## нарисованным одной рукой (ART-generation §5).
const ITEMS: Dictionary = {
	"catch": "icon_catch_v1_01_pick.png",
	"driftwood": "icon_driftwood_v1_01_pick.png",
	"fiber": "icon_fiber_v1_01_pick.png",
	"freshwater": "icon_freshwater_v1_01_pick.png",
	"gear": "icon_gear_v1_01_pick.png",
	"ingot": "icon_ingot_v1_01_pick.png",
	"kelp": "icon_kelp_v1_01_pick.png",
	"part": "icon_part_v1_01_pick.png",
	"rations": "icon_rations_v1_01_pick.png",
	"relic": "icon_relic_v1_01_pick.png",
	"rope": "icon_rope_v1_01_pick.png",
	"salt": "icon_salt_v1_01_pick.png",
	"scrap": "icon_scrap_v1_01_pick.png",
}

func _initialize() -> void:
	var ids: Array[String] = order()
	var atlas: Image = Image.create(CELL * ids.size(), CELL, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	for i: int in ids.size():
		var img: Image = Art.load_pick(str(ITEMS[ids[i]]), CELL, CELL)
		if img == null:
			continue
		atlas.blit_rect(img, Rect2i(0, 0, CELL, CELL), Vector2i(i * CELL, 0))
	Art.save(atlas, OUT_PNG)
	print("иконок предметов: %d" % ids.size())
	quit(1 if Art.fails > 0 else 0)

static func order() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(ITEMS.keys())
	ids.sort()
	return ids
