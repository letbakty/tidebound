extends SceneTree
## Генератор рецептов из таблицы docs/00 §9.1 (плюс вода из §8).
##   godot --headless -s res://tools/gen_recipes.gd && godot --headless --import --quit
##
## Сушки плавника здесь нет намеренно: docs/00 §9.1 описывает её не рецептом,
## а параллельным свойством Сушил («параллельно сушат до 2 мокрых плавников»),
## и в ProductionSystem она так и реализована.

const OUT_DIR: String = "res://data/recipes/"

# id, ключ, станция, входы, выходы, секунды, пассивность, нужен агент, 🔒
const TABLE: Array[Array] = [
	["forge_ingot", "RCP_FORGE_INGOT", "forge",
		{"scrap": 2, "driftwood": 1}, {"ingot": 1}, 20.0, "", true, ""],
	["workbench_part", "RCP_WORKBENCH_PART", "workbench",
		{"ingot": 2}, {"part": 1}, 15.0, "", true, ""],
	["saltery_rations", "RCP_SALTERY_RATIONS", "saltery",
		{"salt": 1, "catch": 2, "freshwater": 1}, {"rations": 2}, 10.0, "", true, ""],
	["ropery_rope", "RCP_ROPERY_ROPE", "ropery",
		{"fiber": 2}, {"rope": 1}, 12.0, "", true, ""],
	["ropery_gear", "RCP_ROPERY_GEAR", "ropery",
		{"rope": 1, "fiber": 1}, {"gear": 1}, 15.0, "", true, "u_gear"],
	["evaporator_salt", "RCP_EVAPORATOR_SALT", "evaporator",
		{}, {"salt": 1}, 0.0, "low_phase", false, ""],
	["dryer_fiber", "RCP_DRYER_FIBER", "dryer",
		{"kelp": 3}, {"fiber": 1}, 0.0, "cycle", false, ""],
	["raincatcher_water", "RCP_RAINCATCHER_WATER", "raincatcher",
		{}, {"freshwater": 1}, 0.0, "cycle", false, ""],
	["condenser_water", "RCP_CONDENSER_WATER", "condenser",
		{}, {"freshwater": 2}, 0.0, "cycle", false, ""],
]

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var written: int = 0
	for row: Array in TABLE:
		var r: RecipeDef = RecipeDef.new()
		r.id = str(row[0])
		r.display_key = str(row[1])
		r.station_special = str(row[2])
		var ins: Dictionary[String, int] = {}
		for k: Variant in (row[3] as Dictionary):
			ins[str(k)] = int((row[3] as Dictionary)[k])
		r.inputs = ins
		var outs: Dictionary[String, int] = {}
		for k2: Variant in (row[4] as Dictionary):
			outs[str(k2)] = int((row[4] as Dictionary)[k2])
		r.outputs = outs
		r.work_seconds = float(row[5])
		r.passive_per = str(row[6])
		r.needs_agent = bool(row[7])
		r.unlock_id = str(row[8])
		var err: int = ResourceSaver.save(r, OUT_DIR + r.id + ".tres")
		if err != OK:
			push_error("не сохранён %s: код %d" % [r.id, err])
		else:
			written += 1
	print("recipes: записано %d/%d" % [written, TABLE.size()])
	quit(0 if written == TABLE.size() else 1)
