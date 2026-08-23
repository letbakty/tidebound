extends SceneTree
## Генератор 12 карт из таблицы docs/00 §10.
##   godot --headless -s res://tools/gen_cards.gd && godot --headless --import --quit

const OUT_DIR: String = "res://data/cards/"

# id, ключ, ключ описания, редкость, разблокировка, эффекты
const TABLE: Array[Array] = [
	["deep_dive", "CARD_DEEP_DIVE", "CARD_DEEP_DIVE_D", "base", "",
		{"low_plateau_add": -2.0, "low_time_mult": 0.75}],
	["fast_haul", "CARD_FAST_HAUL", "CARD_FAST_HAUL_D", "base", "",
		{"haul_speed_mult": 1.4, "bag_slots_add": -1.0}],
	["careful", "CARD_CAREFUL", "CARD_CAREFUL_D", "base", "",
		{"recall_earlier_sec": 30.0, "drown_bonus_sec": 3.0, "gather_speed_mult": 0.8}],
	["great_ebb", "CARD_GREAT_EBB", "CARD_GREAT_EBB_D", "rare", "u_card_ebb",
		{"low_plateau_add": -4.0, "low_time_mult": 1.5, "next_spring_add": 1.0}],
	["calm_water", "CARD_CALM_WATER", "CARD_CALM_WATER_D", "rare", "u_card_calm",
		{"cancel_visit": 1.0}],
	["the_find", "CARD_THE_FIND", "CARD_THE_FIND_D", "rare", "u_card_find",
		{"mark_relic": 1.0}],
	# Вторая шестёрка (CONTENT-wave-1 §3). Все — "base": редкая карта требует
	# разблокировки, а разблокировки — вторая волна. До этой правки базовых
	# карт было ТРИ, драфт тянул три из трёх, и выбора не было вовсе.
	["full_moon", "CARD_FULL_MOON", "CARD_FULL_MOON_D", "base", "",
		{"next_spring_add": 1.0, "low_plateau_add": -1.0}],
	["sea_loan", "CARD_SEA_LOAN", "CARD_SEA_LOAN_D", "base", "",
		{"low_time_mult": 1.4, "next_spring_add": 1.0}],
	["travel_light", "CARD_TRAVEL_LIGHT", "CARD_TRAVEL_LIGHT_D", "base", "",
		{"haul_speed_mult": 1.6, "bag_slots_add": -2.0}],
	["long_breath", "CARD_LONG_BREATH", "CARD_LONG_BREATH_D", "base", "",
		{"drown_bonus_sec": 5.0, "gather_speed_mult": 0.9}],
	["the_dash", "CARD_THE_DASH", "CARD_THE_DASH_D", "base", "",
		{"low_time_mult": 0.6, "gather_speed_mult": 1.6}],
	["muffled_bell", "CARD_MUFFLED_BELL", "CARD_MUFFLED_BELL_D", "base", "",
		{"recall_earlier_sec": -15.0, "gather_speed_mult": 1.2}],
]

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var written: int = 0
	var bad: int = 0
	for row: Array in TABLE:
		var c: CardDef = CardDef.new()
		c.id = str(row[0])
		c.display_key = str(row[1])
		c.desc_key = str(row[2])
		c.rarity = str(row[3])
		c.unlock_id = str(row[4])
		var eff: Dictionary[String, float] = {}
		for k: Variant in (row[5] as Dictionary):
			var key: String = str(k)
			if not CardKeys.is_known(key):
				push_error("карта %s: ключ '%s' не из CardKeys" % [c.id, key])
				bad += 1
				continue
			eff[key] = float((row[5] as Dictionary)[k])
		c.effects = eff
		var err: int = ResourceSaver.save(c, OUT_DIR + c.id + ".tres")
		if err != OK:
			push_error("не сохранён %s: код %d" % [c.id, err])
		else:
			written += 1
	print("cards: записано %d/%d, плохих ключей %d" % [written, TABLE.size(), bad])
	quit(0 if written == TABLE.size() and bad == 0 else 1)
