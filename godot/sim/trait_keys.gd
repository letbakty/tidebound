class_name TraitKeys
extends RefCounted
## Фикс-ключи модификаторов черт и ПРАВИЛО СВЁРТКИ для каждого.
##
## Ключи держим здесь, а не в комментарии: опечатка в ключе даёт молчаливый
## ноль-эффект, который всплывёт через три этапа (research/14 §1.1).
## Валидатор в tests/test_data.gd падает на любом ключе не из этого списка.
##
## Свёртка у ключей РАЗНАЯ, и это не небрежность:
##   mult    — множители, перемножаются (две черты складываются мультипликативно);
##   add     — прибавки, суммируются;
##   replace — ЗАМЕНА базового значения. Единственная семантика для
##             drown_seconds (Ныряльщик: 10 с ВМЕСТО 5, а не ×10) и min_mark.
##             Свернуть их в множитель — значит сломать Ныряльщика.
const MULT: Array[String] = [
	"speed_mult", "ladder_speed_mult", "forge_mult", "saltery_mult",
	"hunger_rate_mult", "warmth_rate_mult", "relic_chance_mult",
	"work_mult", "carry_mult", "rest_need_mult", "rest_gain_mult",
]
const ADD: Array[String] = [
	"bag_slots_add", "mood_aura", "idle_mood_penalty", "drop_chance",
]
const REPLACE: Array[String] = [
	"drown_seconds", "min_mark", "panic_range", "no_panic", "no_rest_cycles",
]

static func all() -> Array[String]:
	var out: Array[String] = []
	out.append_array(MULT)
	out.append_array(ADD)
	out.append_array(REPLACE)
	return out

static func fold_of(key: String) -> String:
	if MULT.has(key):
		return "mult"
	if ADD.has(key):
		return "add"
	if REPLACE.has(key):
		return "replace"
	return ""
