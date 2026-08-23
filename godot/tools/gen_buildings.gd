extends SceneTree
## Генератор 18 построек из таблицы docs/00 §8.
##   godot --headless -s res://tools/gen_buildings.gd && godot --headless --import --quit

const OUT_DIR: String = "res://data/buildings/"
const ANY_LO: int = Balance.BOTTOM_MARK
const ANY_HI: int = Balance.TOP_MARK

# id, ключ, размер, стоимость, min_mark, max_mark, затопление,
# ломается штормом, срывается всегда, hp, special, разблокировка, строится ли
#
# ⚠️ Последняя колонка появилась после того, как этот генератор перезаписал
# raincatcher.tres и снял с него `buildable = false`, выставленный руками на
# этапе 07: пустая смета давала стройку за один тик из ничего (C2.4). Правило
# общее — в таблице обязано быть КАЖДОЕ поле дефа, иначе перегенерация тихо
# возвращает значения по умолчанию.
const TABLE: Array[Array] = [
	["ladder_wood", "BLD_LADDER_WOOD", Vector2i(1, 3), {"driftwood": 3},
		ANY_LO, ANY_HI, SimTypes.FloodRule.OK, true, false, 1, "ladder", "", true],
	["ladder_steel", "BLD_LADDER_STEEL", Vector2i(1, 3), {"part": 2},
		ANY_LO, ANY_HI, SimTypes.FloodRule.OK, false, false, 1, "ladder", "u_steel_ladder", true],
	["platform", "BLD_PLATFORM", Vector2i(3, 1), {"driftwood": 4},
		ANY_LO, ANY_HI, SimTypes.FloodRule.OK, true, false, 1, "platform", "", true],
	["storage", "BLD_STORAGE", Vector2i(2, 2), {"driftwood": 5},
		ANY_LO, ANY_HI, SimTypes.FloodRule.OK, true, false, 2, "storage", "", true],
	["hearth", "BLD_HEARTH", Vector2i(2, 1), {"scrap": 2},
		1, ANY_HI, SimTypes.FloodRule.OK, false, false, 1, "hearth", "", true],
	["bunk", "BLD_BUNK", Vector2i(2, 1), {"driftwood": 2},
		1, ANY_HI, SimTypes.FloodRule.DISABLED, false, false, 1, "bunk", "", true],
	# Дождесборник — стартовая постройка (docs/00 §8: «стоимость: стартовый»),
	# поэтому цены у него нет и в радиале стройки он не появится.
	["raincatcher", "BLD_RAINCATCHER", Vector2i(2, 1), {},
		4, ANY_HI, SimTypes.FloodRule.OK, true, false, 1, "raincatcher", "", false],
	["forge", "BLD_FORGE", Vector2i(2, 2), {"scrap": 6},
		1, ANY_HI, SimTypes.FloodRule.DISABLED, false, false, 1, "forge", "", true],
	["workbench", "BLD_WORKBENCH", Vector2i(2, 1), {"ingot": 2, "driftwood": 2},
		1, ANY_HI, SimTypes.FloodRule.DISABLED, false, false, 1, "workbench", "", true],
	["evaporator", "BLD_EVAPORATOR", Vector2i(3, 1), {"scrap": 4},
		-2, 0, SimTypes.FloodRule.OK, true, false, 1, "evaporator", "", true],
	["saltery", "BLD_SALTERY", Vector2i(2, 1), {"driftwood": 3, "ingot": 1},
		1, ANY_HI, SimTypes.FloodRule.DISABLED, false, false, 1, "saltery", "", true],
	["dryer", "BLD_DRYER", Vector2i(2, 2), {"driftwood": 3},
		2, ANY_HI, SimTypes.FloodRule.OK, true, true, 1, "dryer", "", true],
	["ropery", "BLD_ROPERY", Vector2i(2, 1), {"driftwood": 2, "ingot": 2},
		1, ANY_HI, SimTypes.FloodRule.DISABLED, false, false, 1, "ropery", "", true],
	["sluice", "BLD_SLUICE", Vector2i(1, 2), {"part": 3},
		-4, 0, SimTypes.FloodRule.OK, false, false, 1, "sluice", "", true],
	["lantern", "BLD_LANTERN", Vector2i(1, 1), {"ingot": 1},
		ANY_LO, ANY_HI, SimTypes.FloodRule.OK, false, false, 1, "lantern", "", true],
	["condenser", "BLD_CONDENSER", Vector2i(1, 2), {"part": 2},
		4, ANY_HI, SimTypes.FloodRule.OK, false, false, 1, "condenser", "u_condenser", true],
	["winch", "BLD_WINCH", Vector2i(1, 2), {"part": 2, "rope": 1},
		ANY_LO, ANY_HI, SimTypes.FloodRule.DISABLED, false, false, 1, "winch", "u_winch", true],
	# Верша (CONTENT-wave-1 §2) — первая постройка, которой затопление ПОЛЕЗНО:
	# она отдаёт улов ровно за ту фазу, в которой её накрыло. Отсюда и
	# FloodRule.OK: «не работает под водой» отменило бы её смысл.
	# РЕШЕНИЕ: storm_breaks = true. Промпт про шторм молчит, а колонка
	# docs/00 §8 читается однозначно — плетёная снасть на отметках −3..−1
	# стоит там же, где ломает деревянную лестницу и помост.
	["weir", "BLD_WEIR", Vector2i(2, 1), {"rope": 1, "driftwood": 3},
		-3, -1, SimTypes.FloodRule.OK, true, false, 1, "weir", "", true],
]

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var written: int = 0
	for row: Array in TABLE:
		var d: BuildingDef = BuildingDef.new()
		d.id = str(row[0])
		d.display_key = str(row[1])
		d.size = row[2] as Vector2i
		var cost: Dictionary[String, int] = {}
		for k: Variant in (row[3] as Dictionary):
			cost[str(k)] = int((row[3] as Dictionary)[k])
		d.cost = cost
		d.min_mark = int(row[4])
		d.max_mark = int(row[5])
		d.flood_rule = int(row[6]) as SimTypes.FloodRule
		d.storm_breaks = bool(row[7])
		d.storm_always = bool(row[8])
		d.hp = int(row[9])
		d.special = str(row[10])
		d.unlock_id = str(row[11])
		d.buildable = bool(row[12])
		var err: int = ResourceSaver.save(d, OUT_DIR + d.id + ".tres")
		if err != OK:
			push_error("не сохранён %s: код %d" % [d.id, err])
		else:
			written += 1
	print("buildings: записано %d/%d" % [written, TABLE.size()])
	quit(0 if written == TABLE.size() else 1)
