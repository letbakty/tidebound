class_name RunState
extends RefCounted
## Состояние забега: драфт планов вылазки и разблокировки (docs/00 §10, §11).
## Очки, конец забега и Журнал наполняет этап 11.

## Разблокировки Журнала. На этом этапе наполняются тестом напрямую;
## этап 11 подключит сюда Meta через параметр new_run.
var unlocks: Array[String] = []
var draft: Array[String] = []
var active_card: String = ""
var drafted_this_cycle: bool = false

const UNLOCK_DRAFT_PLUS: String = "u_draft_plus"
const DRAFT_SIZE: int = 3
const DRAFT_SIZE_PLUS: int = 4

var _pending: Array[SimEvent] = []

func new_run(unlock_list: Array[String]) -> void:
	unlocks = unlock_list.duplicate()
	draft.clear()
	active_card = ""
	drafted_this_cycle = false
	_pending.clear()

func has_unlock(id: String) -> bool:
	return unlocks.has(id)

# --- Драфт ----------------------------------------------------------------

## Драфт собирается на каждом Спаде. Базовые карты в пуле всегда, редкие —
## только после разблокировки (docs/00 §10).
func start_draft(w: SimWorld) -> void:
	draft.clear()
	drafted_this_cycle = false
	var pool: Array[String] = []
	for id: String in DB.card_ids():
		var c: CardDef = DB.card(id)
		if c.rarity == "rare" and not has_unlock(c.unlock_id):
			continue
		pool.append(id)
	var take: int = DRAFT_SIZE_PLUS if has_unlock(UNLOCK_DRAFT_PLUS) else DRAFT_SIZE
	# Выбор без повторов: тянем из копии пула, удаляя выбранное.
	for i: int in mini(take, pool.size()):
		var idx: int = w.rng.randi_range(0, pool.size() - 1)
		draft.append(pool[idx])
		pool.remove_at(idx)
	if draft.is_empty():
		return
	_pending.append(SimEvent.make("draft_ready", {"cards": draft.duplicate()}))

## Возвращает false, если карты нет в текущем драфте.
func pick_card(card_id: String, w: SimWorld) -> bool:
	if drafted_this_cycle or not draft.has(card_id):
		return false
	drafted_this_cycle = true
	active_card = card_id
	_apply(card_id, w)
	_pending.append(SimEvent.make("card_picked", {"card": card_id}))
	return true

## Защита от «игрок не выбрал за весь Спад»: автопауза этого не допускает,
## но без страховки цикл остался бы без карты и без объяснения.
func auto_pick_if_needed(w: SimWorld) -> void:
	if drafted_this_cycle or draft.is_empty():
		return
	pick_card(draft[0], w)

# --- Эффекты --------------------------------------------------------------

## Эффекты складываются в cycle_modifiers — общий «блокнот» цикла, который
## читают все системы. Прямых правок чужого состояния здесь ровно три:
## плато отлива, длительность фазы и метка реликвии.
func _apply(card_id: String, w: SimWorld) -> void:
	var c: CardDef = DB.card(card_id)
	if c == null:
		return
	for key: String in c.effects:
		if not CardKeys.is_known(key):
			push_error("карта %s: неизвестный ключ '%s'" % [card_id, key])
			continue
		w.cycle_modifiers[key] = float(c.effects[key])
	w.refresh_cycle_effects()
	if float(c.effects.get("next_spring_add", 0.0)) > 0.0:
		w.crisis.next_spring_bonus += float(c.effects["next_spring_add"])
	if float(c.effects.get("mark_relic", 0.0)) > 0.0:
		_mark_relic(w)

## «Находка»: помечает случайный глубокий депозит гарантированной реликвией.
func _mark_relic(w: SimWorld) -> void:
	var candidates: Array[int] = []
	for i: int in w.terrain.deposits.size():
		var d: Dictionary = w.terrain.deposits[i]
		if str(d["kind"]) != "ruins_deep" or bool(d["relic_taken"]):
			continue
		if Balance.cell_to_mark(d["cell"] as Vector2i) > Balance.RELIC_MARK_MAX:
			continue
		candidates.append(i)
	if candidates.is_empty():
		return
	var idx: int = int(w.rng.pick(candidates))
	w.terrain.deposits[idx]["relic_marked"] = true
	_pending.append(SimEvent.make("deposit_changed",
		{"id": int(w.terrain.deposits[idx]["id"])}))

## Эффект живёт ровно один цикл (docs/00 §10).
func end_cycle(w: SimWorld) -> Dictionary:
	var used: String = active_card
	w.cycle_modifiers.clear()
	w.refresh_cycle_effects()
	active_card = ""
	draft.clear()
	drafted_this_cycle = false
	return {"card": used}

func drain_events() -> Array[SimEvent]:
	var out: Array[SimEvent] = _pending
	_pending = []
	return out

# --- Сериализация ---------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"unlocks": unlocks.duplicate(),
		"draft": draft.duplicate(),
		"active_card": active_card,
		"drafted": drafted_this_cycle,
	}

func from_dict(d: Dictionary) -> void:
	unlocks.clear()
	for v: Variant in d.get("unlocks", []) as Array:
		unlocks.append(str(v))
	draft.clear()
	for c: Variant in d.get("draft", []) as Array:
		draft.append(str(c))
	active_card = str(d.get("active_card", ""))
	drafted_this_cycle = bool(d.get("drafted", false))
	_pending.clear()
