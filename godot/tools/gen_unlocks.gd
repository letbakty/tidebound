extends SceneTree
## Генератор 12 разблокировок из таблицы docs/00 §11.3.
##   godot --headless -s res://tools/gen_unlocks.gd && godot --headless --import --quit

const OUT_DIR: String = "res://data/unlocks/"

# id, ключ, ключ описания, цена, что открывает
const TABLE: Array[Array] = [
	["u_steel_ladder", "UNL_STEEL_LADDER", "UNL_STEEL_LADDER_D", 30,
		{"building": "ladder_steel"}],
	["u_condenser", "UNL_CONDENSER", "UNL_CONDENSER_D", 40, {"building": "condenser"}],
	["u_winch", "UNL_WINCH", "UNL_WINCH_D", 50, {"building": "winch"}],
	["u_gear", "UNL_GEAR", "UNL_GEAR_D", 40, {"recipe": "ropery_gear"}],
	["u_lantern_bright", "UNL_LANTERN_BRIGHT", "UNL_LANTERN_BRIGHT_D", 30,
		{"upgrade": "lantern_radius"}],
	["u_hearth_big", "UNL_HEARTH_BIG", "UNL_HEARTH_BIG_D", 25,
		{"upgrade": "hearth_radius"}],
	["u_start_smith", "UNL_START_SMITH", "UNL_START_SMITH_D", 60,
		{"start_bonus": "smith"}],
	["u_start_stock", "UNL_START_STOCK", "UNL_START_STOCK_D", 20,
		{"start_bonus": "driftwood"}],
	["u_card_ebb", "UNL_CARD_EBB", "UNL_CARD_EBB_D", 50, {"card": "great_ebb"}],
	["u_card_calm", "UNL_CARD_CALM", "UNL_CARD_CALM_D", 50, {"card": "calm_water"}],
	["u_card_find", "UNL_CARD_FIND", "UNL_CARD_FIND_D", 40, {"card": "the_find"}],
	["u_draft_plus", "UNL_DRAFT_PLUS", "UNL_DRAFT_PLUS_D", 80, {"draft_size": 4}],
]

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var written: int = 0
	for row: Array in TABLE:
		var u: UnlockDef = UnlockDef.new()
		u.id = str(row[0])
		u.display_key = str(row[1])
		u.desc_key = str(row[2])
		u.cost = int(row[3])
		u.grants = (row[4] as Dictionary).duplicate()
		var err: int = ResourceSaver.save(u, OUT_DIR + u.id + ".tres")
		if err != OK:
			push_error("не сохранён %s: код %d" % [u.id, err])
		else:
			written += 1
	print("unlocks: записано %d/%d" % [written, TABLE.size()])
	quit(0 if written == TABLE.size() else 1)
