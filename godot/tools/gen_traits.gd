extends SceneTree
## Генератор 20 черт из таблицы docs/00 §6.4.
##   godot --headless -s res://tools/gen_traits.gd && godot --headless --import --quit
##
## Множители выражены дробью от БАЗОВОГО числа спеки, чтобы связь была видна:
## Прожорливый — 24 вместо 18 за цикл, Верхолаз — 1.6 вместо 1.2 тайла/с.

const OUT_DIR: String = "res://data/traits/"

# id, display_key, desc_key, модификаторы
const TABLE: Array[Array] = [
	["diver", "TRAIT_DIVER", "TRAIT_DIVER_D", {"drown_seconds": 10.0}],
	["deep_fear", "TRAIT_DEEP_FEAR", "TRAIT_DEEP_FEAR_D", {"min_mark": -5.0}],
	["sinew", "TRAIT_SINEW", "TRAIT_SINEW_D", {"bag_slots_add": 1.0}],
	["glutton", "TRAIT_GLUTTON", "TRAIT_GLUTTON_D", {"hunger_rate_mult": 24.0 / 18.0}],
	["smith", "TRAIT_SMITH", "TRAIT_SMITH_D", {"forge_mult": 1.25}],
	["salter", "TRAIT_SALTER", "TRAIT_SALTER_D", {"saltery_mult": 1.25}],
	["climber", "TRAIT_CLIMBER", "TRAIT_CLIMBER_D", {"ladder_speed_mult": 1.6 / 1.2}],
	["clumsy", "TRAIT_CLUMSY", "TRAIT_CLUMSY_D", {"drop_chance": 0.05}],
	["hardy", "TRAIT_HARDY", "TRAIT_HARDY_D", {"warmth_rate_mult": 6.0 / 10.0}],
	["chilly", "TRAIT_CHILLY", "TRAIT_CHILLY_D", {"warmth_rate_mult": 14.0 / 10.0}],
	["cheerful", "TRAIT_CHEERFUL", "TRAIT_CHEERFUL_D", {"mood_aura": 2.0}],
	["gloomy", "TRAIT_GLOOMY", "TRAIT_GLOOMY_D", {"mood_aura": -2.0}],
	["sharp_eye", "TRAIT_SHARP_EYE", "TRAIT_SHARP_EYE_D", {"relic_chance_mult": 1.5}],
	["skittish", "TRAIT_SKITTISH", "TRAIT_SKITTISH_D", {"panic_range": 8.0}],
	["grinder", "TRAIT_GRINDER", "TRAIT_GRINDER_D",
		{"work_mult": 1.1, "idle_mood_penalty": 5.0}],
	["sleepy", "TRAIT_SLEEPY", "TRAIT_SLEEPY_D", {"rest_need_mult": 1.5}],
	["veteran", "TRAIT_VETERAN", "TRAIT_VETERAN_D", {"no_panic": 1.0}],
	["light_sleep", "TRAIT_LIGHT_SLEEP", "TRAIT_LIGHT_SLEEP_D", {"rest_gain_mult": 1.25}],
	["thrifty", "TRAIT_THRIFTY", "TRAIT_THRIFTY_D", {"carry_mult": 1.15}],
	["chipper", "TRAIT_CHIPPER", "TRAIT_CHIPPER_D", {"no_rest_cycles": 4.0}],
]

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var written: int = 0
	var bad: int = 0
	for row: Array in TABLE:
		var d: TraitDef = TraitDef.new()
		d.id = str(row[0])
		d.display_key = str(row[1])
		d.desc_key = str(row[2])
		var mods: Dictionary[String, float] = {}
		for k: Variant in (row[3] as Dictionary):
			var key: String = str(k)
			if TraitKeys.fold_of(key).is_empty():
				push_error("черта %s: ключ '%s' не из TraitKeys" % [d.id, key])
				bad += 1
				continue
			mods[key] = float((row[3] as Dictionary)[k])
		d.modifiers = mods
		var err: int = ResourceSaver.save(d, OUT_DIR + d.id + ".tres")
		if err != OK:
			push_error("не сохранён %s: код %d" % [d.id, err])
		else:
			written += 1
	print("traits: записано %d/%d, плохих ключей %d" % [written, TABLE.size(), bad])
	quit(0 if written == TABLE.size() and bad == 0 else 1)
