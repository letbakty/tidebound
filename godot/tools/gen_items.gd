extends SceneTree
## Генератор дефов предметов.
##   godot --headless -s res://tools/gen_items.gd
##   godot --headless --import --quit
##
## SceneTree, а не EditorScript из research/14 §3: проект собирается и
## проверяется headless, редактор в этом цикле не участвует. Идемпотентен.
##
## ⚠️ Источник правды — таблица docs/00 §7, а НЕ пример в research/14 §3:
## там другие размеры стаков и очки судна. При расхождении приоритет у docs/00
## (CONVENTIONS).

const OUT_DIR: String = "res://data/items/"

# id, display_key, стак, порча (циклы), правило затопления, очки судна
const TABLE: Array[Array] = [
	["scrap",      "ITEM_SCRAP",      10, 0,  SimTypes.FloodRule.OK,         0],
	["catch",      "ITEM_CATCH",      10, 3,  SimTypes.FloodRule.LOSE_HALF,  0],
	["driftwood",  "ITEM_DRIFTWOOD",  10, 0,  SimTypes.FloodRule.WET,        0],
	["kelp",       "ITEM_KELP",       10, 0,  SimTypes.FloodRule.OK,         0],
	["freshwater", "ITEM_FRESHWATER", 10, 0,  SimTypes.FloodRule.OK,         0],
	["salt",       "ITEM_SALT",       10, 0,  SimTypes.FloodRule.DESTROY,    1],
	["ingot",      "ITEM_INGOT",      10, 0,  SimTypes.FloodRule.OK,         2],
	["fiber",      "ITEM_FIBER",      10, 0,  SimTypes.FloodRule.WET,        1],
	["rations",    "ITEM_RATIONS",    10, 12, SimTypes.FloodRule.LOSE_HALF,  1],
	# ⚠️ 6 очков пробовали (balance.md, итерация 4, прогон E) и откатили:
	# деталь есть и на верстаке, поэтому надбавка за глубину досталась
	# профилю, который на глубину не ходит. Не поднимать, не разделив
	# деталь с карты и деталь со станка.
	["part",       "ITEM_PART",        5, 0,  SimTypes.FloodRule.OK,         3],
	["rope",       "ITEM_ROPE",        5, 0,  SimTypes.FloodRule.OK,         2],
	["gear",       "ITEM_GEAR",        1, 0,  SimTypes.FloodRule.OK,         4],
	["relic",      "ITEM_RELIC",       1, 0,  SimTypes.FloodRule.OK,        10],
]

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var written: int = 0
	for row: Array in TABLE:
		var d: ItemDef = ItemDef.new()
		d.id = str(row[0])
		d.display_key = str(row[1])
		d.stack_size = int(row[2])
		d.spoil_cycles = int(row[3])
		d.flood_rule = int(row[4]) as SimTypes.FloodRule
		d.ship_points = int(row[5])
		# Имя файла == id: это контракт, на него опирается валидатор DB.
		var err: int = ResourceSaver.save(d, OUT_DIR + d.id + ".tres")
		if err != OK:
			push_error("не сохранён %s: код %d" % [d.id, err])
		else:
			written += 1
	print("items: записано %d/%d" % [written, TABLE.size()])
	quit(0 if written == TABLE.size() else 1)
