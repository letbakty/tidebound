class_name ProductionSystem
extends RefCounted
## Станции и рецепты (docs/00 §9.1). Заказов вручную нет: станция работает,
## пока есть входы и место на складах.
##
## Ключ к цепочкам — БУФЕР станции: входы должны физически лежать на ней
## до старта работы. Подвоз идёт тем же MaterialRequester, что и стройка,
## иначе задачи задваиваются (research/17 §7).

## Индекс рецептов по станции. Строится один раз; порядок — по id, чтобы
## выбор рецепта при нескольких доступных был детерминированным.
static var _by_station: Dictionary[String, Array] = {}
static var _index_built: bool = false

## building_id -> тик, когда лебёдка поднимет следующий стак.
var winch_timers: Dictionary[int, int] = {}
## Произведено за цикл: item_id -> count. Уходит в итог цикла.
var _produced_cycle: Dictionary[String, int] = {}
var _pending: Array[SimEvent] = []

static func _ensure_index() -> void:
	if _index_built:
		return
	_index_built = true
	_by_station.clear()
	for rid: String in DB.recipe_ids():
		var r: RecipeDef = DB.recipe(rid)
		if not _by_station.has(r.station_special):
			_by_station[r.station_special] = []
		(_by_station[r.station_special] as Array).append(rid)
	for k: String in _by_station:
		(_by_station[k] as Array).sort()

static func recipes_for(special: String) -> Array:
	_ensure_index()
	return _by_station.get(special, [])

func new_run() -> void:
	winch_timers.clear()
	_produced_cycle.clear()
	_pending.clear()

# --- Тик ------------------------------------------------------------------

func tick(w: SimWorld) -> void:
	for id: int in w.buildings.order:
		var b: Dictionary = w.buildings.buildings[id]
		if not w.buildings.is_working(b):
			continue
		var special: String = DB.building(str(b["def_id"])).special
		if special == "winch":
			_tick_winch(b, w)
			continue
		_request_inputs(b, w)

## Подвоз входов по ВСЕМ доступным рецептам станции. Дедупликация — через
## pending_jobs, тот же механизм, что у стройки: заказ каждого следующего
## рецепта уже видит то, что едет по предыдущему.
##
## Один рецепт (первый по алфавиту) брать нельзя (C2.8): у Канатной
## "ropery_gear" < "ropery_rope", и после разблокировки u_gear станция
## заказывала 1 волокно под снаряжение — тросу нужно 2, троса нет, значит
## нет и снаряжения: разблокировка НАВСЕГДА останавливала станцию.
## Пассивные рецепты (Сушила: 3 водоросли → волокно) тоже здесь: их вход
## не заказывал никто, и цепочка волокна не заводилась вовсе.
func _request_inputs(b: Dictionary, w: SimWorld) -> void:
	var recipes: Array[String] = available_recipes(b, w)
	if recipes.is_empty():
		return
	b["pending_jobs"] = MaterialRequester.prune(b["pending_jobs"] as Array[int], w)
	for rid: String in recipes:
		var r: RecipeDef = DB.recipe(rid)
		if r.inputs.is_empty():
			continue
		var have: Dictionary[String, int] = {}
		for k: String in r.inputs:
			have[k] = BuildingSystem.buffer_count(b, k, _dry_only(k, r))
		var need: Dictionary[String, int] = MaterialRequester.missing(
			r.inputs, have, b["pending_jobs"] as Array[int], w)
		for k2: String in need:
			if int(need[k2]) <= 0:
				continue
			var src: Dictionary = MaterialRequester.source_for_dry(k2, w, _dry_only(k2, r))
			if src.is_empty():
				continue
			var jid: int = w.jobs.request_haul(src,
				{"kind": "building", "id": int(b["id"]), "cell": b["cell"]},
				k2, int(need[k2]), w)
			if jid != -1:
				(b["pending_jobs"] as Array[int]).append(jid)

## Все рецепты станции, разрешённые прямо сейчас — и под агента, и пассивные.
## Порядок — по id (recipes_for отсортирован): подвоз обязан быть
## детерминированным.
static func available_recipes(b: Dictionary, w: SimWorld) -> Array[String]:
	var out: Array[String] = []
	var d: BuildingDef = DB.building(str(b["def_id"]))
	if d == null:
		return out
	for rid: String in recipes_for(d.special):
		var r: RecipeDef = DB.recipe(rid)
		if not r.unlock_id.is_empty() and not w.unlocked.has(r.unlock_id):
			continue
		out.append(rid)
	return out

## Правило «только сухое» выводится из данных, а не из хардкода id: мокнет
## то, у чего flood_rule == WET, и только Сушила ждут именно мокрое.
static func _dry_only(item_id: String, r: RecipeDef) -> bool:
	var d: ItemDef = DB.item(item_id)
	if d == null:
		return false
	return d.flood_rule == SimTypes.FloodRule.WET and r.station_special != "dryer"

## Рецепт, который станция может делать прямо сейчас. ignore_inputs=true
## отдаёт первый подходящий рецепт вообще — им пользуется подвоз.
func pick_recipe(b: Dictionary, w: SimWorld, ignore_inputs: bool = false) -> String:
	var special: String = DB.building(str(b["def_id"])).special
	for rid: String in recipes_for(special):
		var r: RecipeDef = DB.recipe(rid)
		if not r.needs_agent:
			continue
		if not r.unlock_id.is_empty() and not w.unlocked.has(r.unlock_id):
			continue
		if ignore_inputs or has_inputs(b, r):
			return rid
	return ""

static func has_inputs(b: Dictionary, r: RecipeDef) -> bool:
	for k: String in r.inputs:
		if BuildingSystem.buffer_count(b, k, _dry_only(k, r)) < int(r.inputs[k]):
			return false
	return true

## Почему станция стоит. Пустая строка = работает. Возвращает КОДЫ, а не ключи
## локализации: sim об интерфейсе не знает, ключи подставит панель (docs/03 §5.4).
##
## Без этой функции игрок не понимает, почему цепочка встала — главный
## источник фрустрации в жанре.
static func idle_reason(b: Dictionary, w: SimWorld) -> String:
	var d: BuildingDef = DB.building(str(b["def_id"]))
	if d == null:
		return "no_recipe"
	if int(b["state"]) != int(SimTypes.BuildState.ACTIVE):
		return "under_construction"
	if bool(b["damaged"]):
		return "damaged"
	if bool(b["flooded"]) and d.flood_rule == SimTypes.FloodRule.DISABLED:
		return "flooded"
	var rid: String = w.production.pick_recipe(b, w, true)
	if rid.is_empty():
		# Пассивные станции (испаритель, дождесборник, конденсатор) агента не
		# ждут: у них «работает» = не накрыло водой в эту фазу (docs/00 §9.1).
		var passive: String = _passive_recipe(b, w)
		if not passive.is_empty():
			if bool(b["flooded"]) or bool(b["flooded_in_phase"]):
				return "flooded"
			# Пассивная станция «работает» и с полными складами — выход просто
			# просыпается на землю. Молчать об этом нельзя: испаритель стоит
			# на затопляемой отметке, и там его соль исчезает бесследно.
			return "" if _outputs_fit(DB.recipe(passive), w) else "no_space"
		return "no_recipe"
	var r: RecipeDef = DB.recipe(rid)
	if not has_inputs(b, r):
		# «Нет топлива» отделяем от «нет материалов»: игроку это разные беды.
		var only_fuel: bool = true
		for k: String in r.inputs:
			if BuildingSystem.buffer_count(b, k, _dry_only(k, r)) >= int(r.inputs[k]):
				continue
			if k != "driftwood":
				only_fuel = false
		return "no_fuel" if only_fuel else "no_materials"
	if not _outputs_fit(r, w):
		return "no_space"
	if r.needs_agent and w.policies.get_value(SimTypes.Policy.SUPPLY) == 0:
		return "no_worker"
	return ""

## Есть ли на складах место под весь выход рецепта.
static func _outputs_fit(r: RecipeDef, w: SimWorld) -> bool:
	if r == null:
		return true
	for k: String in r.outputs:
		if not w.storage.has_space(k, int(r.outputs[k])):
			return false
	return true

## Первый доступный пассивный рецепт станции ("" — нет такого).
static func _passive_recipe(b: Dictionary, w: SimWorld) -> String:
	var special: String = DB.building(str(b["def_id"])).special
	for rid: String in recipes_for(special):
		var r: RecipeDef = DB.recipe(rid)
		if r.needs_agent:
			continue
		if not r.unlock_id.is_empty() and not w.unlocked.has(r.unlock_id):
			continue
		return rid
	return ""

## Один тик работы агента у станции. Возвращает true, когда цикл рецепта
## завершён (или стал невозможен).
func advance_work(building_id: int, ticks: int, a: SimAgent, w: SimWorld) -> bool:
	var b: Dictionary = w.buildings.buildings.get(building_id, {})
	if b.is_empty() or not w.buildings.is_working(b):
		return true
	var rid: String = pick_recipe(b, w)
	if rid.is_empty():
		return true
	var r: RecipeDef = DB.recipe(rid)
	b["progress_ticks"] = int(b["progress_ticks"]) + ticks
	if int(b["progress_ticks"]) < _work_ticks_for(r, a):
		return false
	b["progress_ticks"] = 0
	_consume_and_output(b, r, w)
	return true

## Кузнец быстрее у Горна, Солевар — в Солильне; Трудяга — везде.
## Порядок множителей фиксирован.
static func _work_ticks_for(r: RecipeDef, a: SimAgent) -> int:
	var mult: float = a.modifier("work_mult")
	match r.station_special:
		"forge":
			mult *= a.modifier("forge_mult")
		"saltery":
			mult *= a.modifier("saltery_mult")
		_:
			pass
	return maxi(1, int(round(float(r.work_ticks()) / mult)))

func work_ticks_for(r: RecipeDef, a: SimAgent) -> int:
	return _work_ticks_for(r, a)

func _consume_and_output(b: Dictionary, r: RecipeDef, w: SimWorld) -> void:
	for k: String in r.inputs:
		BuildingSystem.buffer_take(b, k, int(r.inputs[k]), _dry_only(k, r))
	for out_id: String in r.outputs:
		_produce(b, out_id, int(r.outputs[out_id]), w)
	_pending.append(SimEvent.make("building_state_changed", {"id": int(b["id"])}))

## Выход РЕЦЕПТА: станция делает НОВЫЙ предмет — сухой, с полным сроком
## годности — и он идёт в отчёт цикла как произведённое.
func _produce(b: Dictionary, item_id: String, n: int, w: SimWorld) -> void:
	_produced_cycle[item_id] = int(_produced_cycle.get(item_id, 0)) + n
	_deposit(b, StackUtil.make(item_id, n, false), w)

## Кладёт ГОТОВЫЙ стак на ближайший склад, не трогая его свойств; если складов
## нет или всё занято — на землю у станции, но НЕ молча.
##
## ⚠️ Две функции вместо одной намеренно (ARCH-02). Пока перенос звал выход
## рецепта, лебёдка пересоздавала стак через StackUtil.make: мокрый плавник
## поднимался сухим, добыча со spoil_left = 1 — свежей, а перенесённое
## попадало в отчёт как «произведено» (SIM-03). Раздельные сигнатуры не дают
## это перепутать: _produce принимает id и количество, _deposit — готовый стак.
func _deposit(b: Dictionary, stack: Dictionary, w: SimWorld) -> void:
	var item_id: String = str(stack["item_id"])
	var cell: Vector2i = BuildingSystem.storage_cell(b)
	var left: int = int(stack["count"])
	var rest: Dictionary = stack.duplicate()
	# ⚠️ Склады перебираются ПОДРЯД, от ближнего к дальнему, а не «выбрали один
	# и на этом всё». Прежний выбор отбрасывал склад, у которого нет свободного
	# СЛОТА, — хотя store() спокойно долил бы стак к такому же. На карте
	# cliff_01 склад забивается к концу первого цикла, и со второго вся соль
	# просыпалась на землю у испарителя, то есть на отметку −1, которую
	# затапливает каждый цикл: соляная цепочка производила ровно один раз
	# за забег (docs/BUG-salt-chain.md).
	for sid: int in _storages_by_distance(cell, w):
		if left <= 0:
			break
		rest["count"] = left
		left = w.storage.store(sid, rest)
	if left <= 0:
		return
	var spill: Dictionary = stack.duplicate()
	spill["count"] = left
	w.storage.drop(cell, spill)
	_pending.append(SimEvent.make("production_spilled",
		{"id": int(b["id"]), "item": item_id, "n": left}))

## Идентификаторы складов по возрастанию расстояния от клетки.
## Тай-брейк по id обязателен: без него порядок при равных расстояниях
## не определён и два забега с одним сидом разойдутся (research/11 §1.1).
## Выборка минимума, а не sort_custom: складов единицы, зато компаратор
## заведомо тотальный.
static func _storages_by_distance(cell: Vector2i, w: SimWorld) -> Array[int]:
	var out: Array[int] = []
	var used: Dictionary[int, bool] = {}
	for _i: int in w.storage.storages.size():
		var best: int = -1
		var best_d: float = INF
		for s: Dictionary in w.storage.storages:
			var sid: int = int(s["id"])
			if used.has(sid):
				continue
			var c: Vector2i = s["cell"] as Vector2i
			var d: float = absf(float(c.x - cell.x)) + absf(float(c.y - cell.y))
			if d < best_d or (is_equal_approx(d, best_d) and sid < best):
				best_d = d
				best = sid
		if best < 0:
			break
		used[best] = true
		out.append(best)
	return out

# --- Лебёдка --------------------------------------------------------------

## Корзина — клетка ярусом ниже механизма: агенты с дна складывают груз туда,
## а лебёдка поднимает его наверх сама. Первый шаг автоматизации (docs/00 §8).
static func basket_cell(b: Dictionary) -> Vector2i:
	var cell: Vector2i = b["cell"] as Vector2i
	return Vector2i(cell.x, Balance.mark_to_floor_cell_y(int(b["mark"]) - 1))

func _tick_winch(b: Dictionary, w: SimWorld) -> void:
	var id: int = int(b["id"])
	var due: int = int(winch_timers.get(id, 0))
	if w.clock.total_ticks() < due:
		return
	var cell: Vector2i = basket_cell(b)
	var stacks: Array[Dictionary] = w.storage.ground_at(cell)
	if stacks.is_empty():
		return
	# Поднимаем ровно один стак за раз.
	var taken: Array[Dictionary] = w.storage.pickup_at(cell)
	var first: Dictionary = taken[0]
	for i: int in range(1, taken.size()):
		w.storage.drop(cell, taken[i])
	# Лебёдка ПЕРЕНОСИТ груз, а не производит его: стак уходит на склад целиком,
	# с тем же wet и тем же spoil_left, и в отчёт цикла не попадает.
	_deposit(b, first, w)
	winch_timers[id] = w.clock.total_ticks() \
		+ int(Balance.WINCH_LIFT_SEC * float(Balance.TICKS_PER_SEC))

## Клетки корзин: вода не уносит из них предметы — в этом смысл лебёдки.
func basket_cells(w: SimWorld) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for b: Dictionary in w.buildings.with_special("winch"):
		out.append(basket_cell(b))
	return out

# --- Пассивные рецепты ----------------------------------------------------

## Конец Низкой воды — момент, когда испаритель отдаёт соль.
func on_phase_ended(prev_phase: int, w: SimWorld) -> void:
	if prev_phase != int(SimTypes.Phase.LOW):
		return
	_run_passive(w, "low_phase")

func on_cycle_ended(w: SimWorld) -> Dictionary:
	_run_passive(w, "cycle")
	_dry_driftwood(w)
	var report: Dictionary = {"produced": _produced_cycle.duplicate()}
	_produced_cycle.clear()
	return report

func _run_passive(w: SimWorld, when: String) -> void:
	for id: int in w.buildings.order:
		var b: Dictionary = w.buildings.buildings[id]
		if not w.buildings.is_working(b):
			continue
		var special: String = DB.building(str(b["def_id"])).special
		for rid: String in recipes_for(special):
			var r: RecipeDef = DB.recipe(rid)
			if r.needs_agent or r.passive_per != when:
				continue
			if not r.unlock_id.is_empty() and not w.unlocked.has(r.unlock_id):
				continue
			if not _passive_allowed(b, r, w):
				continue
			if not has_inputs(b, r):
				continue
			_consume_and_output(b, r, w)

## Испарителю нужны солнце и сухость: он не даёт соль в цикл, в середине
## которого его накрыло, и не даёт её в шторм (docs/00 §9.1, §9.4).
## Флаг именно «был затоплен хоть раз за фазу», а не «затоплен сейчас».
func _passive_allowed(b: Dictionary, r: RecipeDef, w: SimWorld) -> bool:
	if r.station_special == "evaporator":
		return not bool(b["flooded_in_phase"]) and not w.is_storm
	return true

## Сушила параллельно основному рецепту сушат до двух мокрых плавников
## (docs/00 §9.1 описывает это свойством станции, а не отдельным рецептом).
func _dry_driftwood(w: SimWorld) -> void:
	for b: Dictionary in w.buildings.with_special("dryer"):
		if not w.buildings.is_working(b):
			continue
		var left: int = Balance.DRYER_DRIFTWOOD_PER_CYCLE
		for s: Dictionary in w.storage.storages:
			if left <= 0:
				break
			var sid: int = int(s["id"])
			var got: Array[Dictionary] = w.storage.take(sid, "driftwood", left, false)
			for st: Dictionary in got:
				if bool(st["wet"]) and left > 0:
					StackUtil.set_wet(st, false)
					left -= int(st["count"])
				w.storage.store(sid, st)

## Дождесборник в шторм даёт больше воды (docs/00 §9.4).
func storm_water_bonus(w: SimWorld) -> void:
	if not w.is_storm:
		return
	for b: Dictionary in w.buildings.with_special("raincatcher"):
		if w.buildings.is_working(b):
			_produce(b, "freshwater",
				Balance.RAINCATCHER_STORM_WATER - 1, w)

# --- События и сериализация -----------------------------------------------

func drain_events() -> Array[SimEvent]:
	var out: Array[SimEvent] = _pending
	_pending = []
	return out

func to_dict() -> Dictionary:
	var timers: Dictionary = {}
	var ids: Array[int] = []
	ids.assign(winch_timers.keys())
	ids.sort()
	for id: int in ids:
		timers[str(id)] = int(winch_timers[id])
	var produced: Dictionary = {}
	var keys: Array[String] = []
	keys.assign(_produced_cycle.keys())
	keys.sort()
	for k: String in keys:
		produced[k] = int(_produced_cycle[k])
	return {"winch": timers, "produced": produced}

func from_dict(d: Dictionary) -> void:
	winch_timers.clear()
	for k: Variant in d.get("winch", {}) as Dictionary:
		winch_timers[str(k).to_int()] = int((d["winch"] as Dictionary)[k])
	_produced_cycle.clear()
	for k2: Variant in d.get("produced", {}) as Dictionary:
		_produced_cycle[str(k2)] = int((d["produced"] as Dictionary)[k2])
	_pending.clear()
