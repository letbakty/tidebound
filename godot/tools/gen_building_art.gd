extends SceneTree
## Спрайты построек и иконки построек из отобранного арта.
##
## ⚠️ Не путать с tools/gen_buildings.gd: тот собирает ДЕФЫ построек
## (data/buildings/*.tres) из таблицы docs/00 §8. Здесь только картинки.
## (prompts/ART-integration §2 п.5 и п.6).
##
##   godot --headless -s res://tools/gen_building_art.gd
##   godot --headless --import --quit
##
## Постройки идут ОТДЕЛЬНЫМИ файлами, а не одним атласом: размеры у них от
## 32×32 до 96×32, упаковка дала бы таблицу регионов на ровном месте, а
## выигрыш атласа (меньше смен текстуры) при десятке текстур на экране нулевой
## (research/29 §4).
##
## ⚠️ Размер спрайта — это size постройки из data/buildings/*.tres, умноженный
## на 32. Несовпадение ловится здесь, а не в игре: постройка «на клетку шире»
## наезжает на соседнюю и молчит. Таблицу сторожит tests/test_visual.gd,
## сверяя её с настоящими дефами.

const Art: GDScript = preload("res://tools/art_lib.gd")

const TILE: int = 32
const OUT_DIR: String = "res://assets/sprites/buildings/"
const OUT_ICONS: String = "res://assets/sprites/building_icons.png"
## Клетка иконки постройки — 24×24 (ART-generation §0).
const ICON: Vector2i = Vector2i(24, 24)

## def_id -> {src: файл в art-rd/processed, cells: размер в клетках,
##            icon: файл иконки}. Ключи идут в атлас иконок по алфавиту.
const BUILDINGS: Dictionary = {
	"bunk": {"src": "bld_bunk_v1_02_pick.png", "cells": Vector2i(2, 1),
		"icon": "iconb_bunk_v1_01_pick.png"},
	"condenser": {"src": "bld_condenser_v1_01_pick.png", "cells": Vector2i(1, 2),
		"icon": "iconb_condenser_v1_01_pick.png"},
	"dryer": {"src": "bld_dryer_v1_01_pick.png", "cells": Vector2i(2, 2),
		"icon": "iconb_dryer_v1_01_pick.png"},
	"evaporator": {"src": "bld_evaporator_v1_01_pick.png", "cells": Vector2i(3, 1),
		"icon": "iconb_evaporator_v1_01_pick.png"},
	"forge": {"src": "bld_forge_v1_01_pick.png", "cells": Vector2i(2, 2),
		"icon": "iconb_forge_v1_01_pick.png"},
	"hearth": {"src": "bld_hearth_v1_01_pick.png", "cells": Vector2i(2, 1),
		"icon": "iconb_hearth_v1_01_pick.png"},
	"ladder_steel": {"src": "bld_ladder_steel_v1_01_pick.png", "cells": Vector2i(1, 3),
		"icon": "iconb_ladder_steel_v1_01_pick.png"},
	"ladder_wood": {"src": "bld_ladder_wood_v1_01_pick.png", "cells": Vector2i(1, 3),
		"icon": "iconb_ladder_wood_v1_01_pick.png"},
	"lantern": {"src": "bld_lantern_v1_01_pick.png", "cells": Vector2i(1, 1),
		"icon": "iconb_lantern_v1_01_pick.png"},
	"platform": {"src": "bld_platform_v2_01_pick.png", "cells": Vector2i(3, 1),
		"icon": "iconb_platform_v1_01_pick.png"},
	"raincatcher": {"src": "bld_raincatcher_v1_01_pick.png", "cells": Vector2i(2, 1),
		"icon": "iconb_raincatcher_v1_01_pick.png"},
	"ropery": {"src": "bld_ropery_v1_01_pick.png", "cells": Vector2i(2, 1),
		"icon": "iconb_ropery_v1_01_pick.png"},
	"saltery": {"src": "bld_saltery_v1_01_pick.png", "cells": Vector2i(2, 1),
		"icon": "iconb_saltery_v1_01_pick.png"},
	"sluice": {"src": "bld_sluice_v1_01_pick.png", "cells": Vector2i(1, 2),
		"icon": "iconb_sluice_v1_01_pick.png"},
	"storage": {"src": "bld_storage_v1_01_pick.png", "cells": Vector2i(2, 2),
		"icon": "iconb_storage_v1_01_pick.png"},
	"winch": {"src": "bld_winch_v1_01_pick.png", "cells": Vector2i(1, 2),
		"icon": "iconb_winch_v1_01_pick.png"},
	"workbench": {"src": "bld_workbench_v1_01_pick.png", "cells": Vector2i(2, 1),
		"icon": "iconb_workbench_v1_01_pick.png"},
}

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var ids: Array[String] = icon_order()
	var icons: Image = Image.create(ICON.x * ids.size(), ICON.y, false,
		Image.FORMAT_RGBA8)
	icons.fill(Color(0, 0, 0, 0))
	for i: int in ids.size():
		var id: String = ids[i]
		var b: Dictionary = BUILDINGS[id]
		var cells: Vector2i = b["cells"]
		var img: Image = Art.load_pick(str(b["src"]), cells.x * TILE, cells.y * TILE)
		if img != null:
			Art.save(img, OUT_DIR + id + ".png")
		# Иконки построек намеренно РАЗНОЙ формы (8×24 у лестницы, 24×8 у
		# испарителя) — они повторяют пропорции постройки. Вписываем в клетку
		# прозрачным полем: растянуть значит соврать о постройке.
		var ic: Image = Art.load_pick(str(b["icon"]))
		if ic == null:
			continue
		icons.blit_rect(Art.fit_into(ic, ICON), Rect2i(Vector2i.ZERO, ICON),
			Vector2i(i * ICON.x, 0))
	Art.save(icons, OUT_ICONS)
	print("построек: %d" % ids.size())
	quit(1 if Art.fails > 0 else 0)

## Порядок иконок в атласе. Алфавит, а не порядок словаря: он же считается
## в ui/components/icon_stub.gd, и оба обязаны сойтись без общего файла.
static func icon_order() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(BUILDINGS.keys())
	ids.sort()
	return ids
