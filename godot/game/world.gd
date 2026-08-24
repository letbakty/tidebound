class_name WorldView
extends Node2D
## Корень мира внутри мирового SubViewport: тайлмапы, депозиты, вода, камера.
##
## View-нода: только рисует состояние sim и пробрасывает ввод. Игровой логики
## здесь нет и быть не может (docs/02 §1).

## Индексы тайлов в заглушечном атласе (tools/gen_placeholder_tileset.gd).
const T_CLIFF: int = 0
const T_SAND: int = 1
const T_RUINS: int = 2
const T_LADDER: int = 3
const T_BACK: int = 4
const SOURCE_ID: int = 0

## Визуальный материал яруса по отметке: утёс сверху, песок на пляже и отмели,
## руины на глубине (docs/00 §3.1). Числа визуальные, не игровые.
const MARK_SAND_TOP: int = -1
const MARK_RUINS_TOP: int = -6

## Цвет заглушки депозита по виду. Ключи обязаны покрывать ВЕСЬ
## Balance.DEPOSIT_KINDS: неизвестный вид уходил в Color.MAGENTA, и после
## первой волны контента четыре депозита из восьми светились на карте
## ядовито-розовым (#EE13E6 пипеткой на кадре чистого клона). Покрытие
## сторожит tests/test_project_integrity.gd.
const DEPOSIT_COLORS: Dictionary = {
	"ruins_near": Color("8a8f7a"),
	"ruins_deep": Color("6f7f8a"),
	"shallow": Color("c9a26b"),
	"kelp": Color("4f7a4a"),
	# Волна контента. Цвета взяты именами из art/tidebound.gpl, а не подобраны
	# на глаз: lamp — сухая соляная корка, surf — холодная пресная линза,
	# bone — бледная кость отмели, rust_warm — ржавое дерево обломков.
	"brine_pool": Color("f0d6aa"),
	"fresh_seep": Color("2d6b7a"),
	"bone_shoal": Color("d8d4c4"),
	"shipwreck": Color("965836"),
}

@onready var ground: TileMapLayer = $Ground
@onready var ladders: TileMapLayer = $Ladders
@onready var deposits_root: Node2D = $Deposits
@onready var agents_root: Node2D = $Agents
@onready var buildings_root: Node2D = $Buildings
@onready var creatures_root: Node2D = $Creatures
@onready var ghost: BuildGhost = $BuildGhost
@onready var camera: CameraRig = $CameraRig
## Этап 18: бюджет света, пул частиц и два экранных оверлея мира.
@onready var lights: LightBudget = $Lights
@onready var fx: Node2D = $Fx
@onready var fog: ColorRect = $FogLayer/DepthFog
@onready var rain: ColorRect = $RainLayer/Rain
@onready var clouds: Parallax2D = $ParallaxClouds
@onready var mist: Parallax2D = $ParallaxMist

## Дрейф дальних слоёв, px в секунду СИМУЛЯЦИИ. Через autoscroll ноды нельзя:
## он идёт по реальному времени и на паузе облака продолжают ехать — пауза
## перестаёт читаться как пауза (проверено сравнением двух кадров).
const CLOUD_DRIFT: float = -6.0
const MIST_DRIFT: float = -2.0

## Как часто пересчитывать мокрые тайлы, в СИМ-тиках. Раньше это делалось
## каждый кадр — включая паузу, — и каждый раз строился словарь query_clock()
## с копиями внутри (аудит B3). Три тика — та же частота, что у
## water_level_changed: чаще глазу и не надо.
const WET_EVERY_TICKS: int = 3

## Игровые оверлеи (этап 13): отметки ярусов, зона затопления, занятия.
var overlay: GameOverlay = null
## Маркер маяка (этап 14).
var beacon: BeaconView = null

func get_overlay() -> GameOverlay:
	return overlay

## Ноды для WeatherView: она дирижирует эффектами, но не ищет их сама.
func fog_rect() -> ColorRect:
	return fog

func rain_rect() -> ColorRect:
	return rain

func fx_root() -> Node2D:
	return fx

var _deposit_nodes: Dictionary[int, Node2D] = {}
var _agent_views: Dictionary[int, AgentView] = {}
var _building_views: Dictionary[int, BuildingView] = {}
var _creature_views: Dictionary[int, CreatureView] = {}
var _drawn_graph_version: int = -1
var _wet_tick: int = 0
var _light_nodes: Dictionary[int, PointLight2D] = {}

func _ready() -> void:
	overlay = GameOverlay.new()
	overlay.name = "GameOverlay"
	add_child(overlay)
	beacon = BeaconView.new()
	beacon.name = "BeaconView"
	add_child(beacon)
	Events.run_started.connect(_on_run_started)
	# Мокрые тайлы — по тику симуляции: на паузе пересчёта нет вовсе.
	Events.sim_ticked.connect(_on_sim_ticked)
	Events.phase_changed.connect(_update_wet_tiles.unbind(2))
	Events.deposit_changed.connect(_on_deposit_changed)
	Events.agent_spawned.connect(_on_agent_spawned)
	Events.agent_died.connect(_on_agent_died)
	Events.run_ended.connect(_clear_agent_views.unbind(1))
	Events.building_placed.connect(_on_building_placed)
	Events.building_state_changed.connect(_on_building_changed)
	Events.building_removed.connect(_on_building_removed)
	Events.creature_spawned.connect(_on_creature_spawned)
	Events.creature_left.connect(_on_creature_left)
	if _terrain() != null:
		_rebuild_all()

func _process(_delta: float) -> void:
	# Лестницы строят и смывает — перерисовываем только при смене версии графа,
	# а не каждый кадр.
	var t: Terrain = _terrain()
	if t != null and t.graph_version != _drawn_graph_version:
		_draw_ladders(t)
	# Облака и гряда идут по сим-времени: замирают на паузе, ускоряются на ×3.
	var sim_t: float = Game.sim_seconds()
	clouds.scroll_offset.x = floorf(sim_t * CLOUD_DRIFT)
	mist.scroll_offset.x = floorf(sim_t * MIST_DRIFT)

# --- Мокрые тайлы (промпт 18 п.5, docs/00 §5) -----------------------------

## Тайлы ниже последнего максимума воды за цикл остаются мокрыми до конца
## цикла: граница уезжает в шейдер Ground в МИРОВЫХ координатах, потому что
## она про отметку, а не про экран.
##
## Сила блеска гаснет к концу цикла: «мокро» — это состояние, а не метка,
## и оно обязано быть видно как проходящее.
func _on_sim_ticked(tick: int) -> void:
	if tick - _wet_tick < WET_EVERY_TICKS:
		return
	_wet_tick = tick
	_update_wet_tiles()

func _update_wet_tiles() -> void:
	var mat: ShaderMaterial = ground.material as ShaderMaterial
	if mat == null or Game.world == null:
		return
	var clock: Dictionary = Game.query_clock()
	if clock.is_empty():
		return
	var last_high: float = float(clock.get("last_high", Balance.HIGH_LEVEL))
	var level: float = float(clock.get("level", Balance.HIGH_LEVEL))
	# Под водой мокрое не рисуем: там и так вода. Граница — максимум цикла,
	# но не выше текущего уровня.
	mat.set_shader_parameter(&"u_wet_world_y",
		WorldGeo.mark_to_world_y(maxf(last_high, level)))
	var phase: int = int(clock.get("phase", 0))
	var progress: float = 0.0
	var phase_len: float = maxf(1.0, float(int(clock.get("phase_len", 1))))
	progress = float(int(clock.get("tick_in_phase", 0))) / phase_len
	# Полная сила на Отливе, к концу Низкой воды тайлы высыхают.
	var amount: float = 1.0
	if phase == SimTypes.Phase.LOW:
		amount = clampf(1.0 - progress, 0.0, 1.0)
	elif phase == SimTypes.Phase.SIGNAL:
		amount = 0.0
	mat.set_shader_parameter(&"u_wet_amount", amount)

func _terrain() -> Terrain:
	if Game.world == null:
		return null
	return Game.world.terrain

func _on_run_started(_seed_value: int) -> void:
	_wet_tick = 0
	_rebuild_all()
	_update_wet_tiles()

func _rebuild_all() -> void:
	var t: Terrain = _terrain()
	if t == null:
		return
	_draw_ground(t)
	_draw_ladders(t)
	_rebuild_deposits(t)
	_rebuild_agents()
	_rebuild_buildings()
	_clear_creature_views()
	camera.setup(Game.cliff_def())

# --- Отрисовка рельефа ----------------------------------------------------

## Срез утёса: у каждой площадки рисуется пол, а колонки, над которыми есть
## площадка повыше, заливаются сплошняком — это «тело» скалы под террасой.
## Без него ярусы висят в воздухе и срез не читается.
func _draw_ground(t: Terrain) -> void:
	ground.clear()
	var cliff: CliffDef = Game.cliff_def()
	# Для каждой колонки — самая высокая отметка, где есть площадка.
	var top_mark_at: Dictionary[int, int] = {}
	for p: Dictionary in t.platforms:
		var mark: int = int(p["mark"])
		for x: int in range(int(p["x0"]), int(p["x1"]) + 1):
			if mark > int(top_mark_at.get(x, -9999)):
				top_mark_at[x] = mark

	for p2: Dictionary in t.platforms:
		var mark2: int = int(p2["mark"])
		var y: int = Balance.mark_to_floor_cell_y(mark2)
		var first_y2: int = Balance.mark_to_first_cell_y(mark2)
		for x2: int in range(int(p2["x0"]), int(p2["x1"]) + 1):
			ground.set_cell(Vector2i(x2, y), SOURCE_ID, Vector2i(_tile_for_mark(mark2), 0))
			# Задняя стенка ниши — только там, где над колонкой ЕСТЬ ярус повыше.
			# Под открытым небом её быть не должно.
			if int(top_mark_at.get(x2, -9999)) <= mark2:
				continue
			for dy2: int in Balance.TILES_PER_MARK - 1:
				ground.set_cell(Vector2i(x2, first_y2 + dy2), SOURCE_ID, Vector2i(T_BACK, 0))

	for x3: int in range(cliff.width):
		if not top_mark_at.has(x3):
			continue
		var top: int = top_mark_at[x3]
		for mark3: int in range(Balance.BOTTOM_MARK, top):
			# Ярус, в котором эта колонка не принадлежит площадке, но выше по
			# ней площадка есть → под террасой сплошная порода.
			if t.platform_at(Vector2i(x3, Balance.mark_to_floor_cell_y(mark3))) >= 0:
				continue
			var first_y: int = Balance.mark_to_first_cell_y(mark3)
			for dy: int in Balance.TILES_PER_MARK:
				ground.set_cell(Vector2i(x3, first_y + dy),
					SOURCE_ID, Vector2i(_tile_for_mark(mark3), 0))

func _tile_for_mark(mark: int) -> int:
	if mark <= MARK_RUINS_TOP:
		return T_RUINS
	if mark <= MARK_SAND_TOP:
		return T_SAND
	return T_CLIFF

## Лестница 1×3: занимает колонку от пола верхней площадки до пола нижней.
func _draw_ladders(t: Terrain) -> void:
	ladders.clear()
	for l: Dictionary in t.ladders:
		var x: int = int(l["x"])
		var y0: int = Balance.mark_to_floor_cell_y(int(l["mark_top"]))
		for dy: int in range(1, Balance.TILES_PER_MARK + 1):
			ladders.set_cell(Vector2i(x, y0 + dy), SOURCE_ID, Vector2i(T_LADDER, 0))
	_drawn_graph_version = t.graph_version

# --- Депозиты -------------------------------------------------------------

func _rebuild_deposits(t: Terrain) -> void:
	for n: Node2D in _deposit_nodes.values():
		n.queue_free()
	_deposit_nodes.clear()
	for d: Dictionary in t.deposits:
		_add_deposit_node(d)

func _add_deposit_node(d: Dictionary) -> void:
	var kind: String = str(d["kind"])
	var id: int = int(d["id"])
	# Заглушка вместо арта: квадрат цвета ресурса с его буквой (CONVENTIONS —
	# нет ассета, делаем программную заглушку, а не блокируемся).
	var root: Node2D = Node2D.new()
	root.position = WorldGeo.cell_to_world(d["cell"] as Vector2i)
	var rect: ColorRect = ColorRect.new()
	rect.size = Vector2(float(WorldGeo.TILE), float(WorldGeo.TILE))
	rect.color = DEPOSIT_COLORS.get(kind, Color.MAGENTA)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(rect)
	var label: Label = Label.new()
	label.text = _letter_for(kind)
	label.size = rect.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(label)
	deposits_root.add_child(root)
	_deposit_nodes[id] = root

func _letter_for(kind: String) -> String:
	var def: Dictionary = Balance.DEPOSIT_KINDS.get(kind, {}) as Dictionary
	var item: String = str(def.get("item", "?"))
	return item.substr(0, 1).to_upper()

func _on_deposit_changed(id: int) -> void:
	var t: Terrain = _terrain()
	if t == null:
		return
	var i: int = t.deposit_index(id)
	if i < 0:
		if _deposit_nodes.has(id):
			_deposit_nodes[id].queue_free()
			_deposit_nodes.erase(id)
		return
	var d: Dictionary = t.deposits[i]
	if not _deposit_nodes.has(id):
		_add_deposit_node(d)
		return
	# Плавник появляется и исчезает пачками — проще пересобрать узлы, которых
	# больше нет в sim, чем вести их синхронно.
	_sync_removed(t)

func _sync_removed(t: Terrain) -> void:
	var alive: Dictionary[int, bool] = {}
	for d: Dictionary in t.deposits:
		alive[int(d["id"])] = true
	for id: int in _deposit_nodes.keys():
		if not alive.has(id):
			_deposit_nodes[id].queue_free()
			_deposit_nodes.erase(id)
	for d2: Dictionary in t.deposits:
		if not _deposit_nodes.has(int(d2["id"])):
			_add_deposit_node(d2)

# --- Агенты ---------------------------------------------------------------

func _rebuild_agents() -> void:
	_clear_agent_views()
	if Game.world == null:
		return
	for a: SimAgent in Game.world.agents.agents:
		if a.is_alive():
			_on_agent_spawned(a.id)

## Полная очистка, а не по одному: утечки View рождаются именно здесь
## (research/15 §6.2), и границы забега — единственное надёжное место чистки.
func _clear_agent_views() -> void:
	for v: AgentView in _agent_views.values():
		v.queue_free()
	_agent_views.clear()

func _on_agent_spawned(id: int) -> void:
	if _agent_views.has(id):
		return
	var v: AgentView = AgentView.new()
	v.setup(id)
	agents_root.add_child(v)
	_agent_views[id] = v

func _on_agent_died(id: int, cause: String) -> void:
	var v: AgentView = _agent_views.get(id, null)
	if v == null:
		return
	# Стереть из словаря ДО анимации: иначе повторная эмиссия agent_spawned
	# после загрузки создаст второй view, пока первый ещё доигрывает.
	_agent_views.erase(id)
	v.play_death_and_free(cause)

# --- Постройки ------------------------------------------------------------

func _rebuild_buildings() -> void:
	for v: BuildingView in _building_views.values():
		v.queue_free()
	_building_views.clear()
	# Свет живёт отдельным реестром: без сброса при перезапуске забега огни
	# прошлой колонии остались бы висеть в пустоте.
	lights.clear()
	_light_nodes.clear()
	if Game.world == null:
		return
	for id: int in Game.world.buildings.order:
		_on_building_placed(id)

func _on_building_placed(id: int) -> void:
	if _building_views.has(id) or Game.world == null:
		return
	var b: Dictionary = Game.world.buildings.buildings.get(id, {})
	if b.is_empty():
		return
	var v: BuildingView = BuildingView.new()
	v.setup(id, str(b["def_id"]))
	v.position = WorldGeo.cell_to_world(b["cell"] as Vector2i)
	buildings_root.add_child(v)
	_building_views[id] = v
	_sync_light(id)

func _on_building_changed(id: int) -> void:
	var v: BuildingView = _building_views.get(id, null)
	if v == null:
		_on_building_placed(id)
		return
	v.refresh()
	_sync_light(id)

func _on_building_removed(id: int) -> void:
	var v: BuildingView = _building_views.get(id, null)
	_drop_light(id)
	if v == null:
		return
	_building_views.erase(id)
	v.queue_free()

# --- Свет (промпт 18 п.2) -------------------------------------------------

## Настоящий PointLight2D — только у источников, которые обязаны освещать
## проходящих мимо агентов: очаг, горн, фонарь (у фонаря свет ещё и игровой —
## радиус против существ, docs/00 §9). Всё декоративное свечение делается
## спрайтами, иначе бюджет в восемь светов уходит на украшения.
const LIT_BUILDINGS: Dictionary[String, String] = {
	"hearth": "hearth", "forge": "forge", "lantern": "lantern",
}

## Свет появляется у ДОСТРОЕННОЙ и целой постройки и гаснет, когда её сломало
## или затопило: горящий фонарь под водой — это дефект, который замечают все.
func _sync_light(id: int) -> void:
	var b: Dictionary = Game.query_building(id)
	if b.is_empty():
		_drop_light(id)
		return
	var kind: String = LIT_BUILDINGS.get(str(b.get("def_id", "")), "")
	if kind.is_empty():
		return
	var on: bool = int(b.get("state", 0)) == SimTypes.BuildState.ACTIVE \
		and not bool(b.get("damaged", false)) and not bool(b.get("flooded", false))
	# Очагу и горну нужен ещё и огонь: погасший очаг не светит.
	if kind != "lantern":
		on = on and bool(b.get("lit", false))
	if not on:
		_drop_light(id)
		return
	if _light_nodes.has(id):
		return
	var cell: Vector2i = b["cell"] as Vector2i
	_light_nodes[id] = lights.add_light(kind, WorldGeo.cell_center_world(cell))

func _drop_light(id: int) -> void:
	var l: PointLight2D = _light_nodes.get(id, null)
	if l == null:
		return
	_light_nodes.erase(id)
	lights.remove_light(l)

# --- Существа -------------------------------------------------------------

func _clear_creature_views() -> void:
	for v: CreatureView in _creature_views.values():
		v.queue_free()
	_creature_views.clear()

func _on_creature_spawned(id: int) -> void:
	if _creature_views.has(id):
		return
	var v: CreatureView = CreatureView.new()
	v.setup(id)
	creatures_root.add_child(v)
	_creature_views[id] = v

func _on_creature_left(id: int) -> void:
	var v: CreatureView = _creature_views.get(id, null)
	if v == null:
		return
	_creature_views.erase(id)
	v.queue_free()

# --- Координаты и хит-тест ------------------------------------------------
# ЕДИНСТВЕННЫЙ хелпер конверсии вьюпорт↔мир на весь проект (docs/01 §1.1).
# Конвертировать «на месте» в других файлах запрещено.
#
# ⚠️ Здесь именно МИРОВОЙ SubViewport (640×360), а не окно: точку окна сначала
# делит на stretch_shrink Main._to_viewport. Прежние имена screen_to_world и
# world_to_screen врали ровно в том месте, где на этом уже один раз ошиблись
# (клик уезжал на 34 клетки) — поэтому в имени стоит «viewport».

func viewport_to_world(viewport_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * viewport_pos

func world_to_viewport(world_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_pos

## Один хит-тест без физики на все будущие этапы (07, 09, 14).
## Приоритет целей: агент → постройка → склад → депозит → пустая клетка.
## Постройки и существа появятся на этапах 07/09 — их ветки добавляются СЮДА,
## а не отдельными хит-тестами в панелях (research/15 §7).
func pick_at(world_pos: Vector2) -> Dictionary:
	var cell: Vector2i = WorldGeo.world_to_cell(world_pos)
	# Проверка по убыванию Y: клик попадает в того, кто нарисован сверху,
	# а не «сквозь» ближнего агента в дальнего.
	var hit_id: int = -1
	var best_y: float = -INF
	for id: int in _agent_views:
		var v: AgentView = _agent_views[id]
		if v.hit_rect().has_point(world_pos) and v.position.y > best_y:
			best_y = v.position.y
			hit_id = id
	if hit_id >= 0:
		return {"kind": "agent", "id": hit_id, "cell": cell}
	if Game.world != null:
		var bid: int = Game.world.buildings.building_at(cell)
		if bid >= 0:
			return {"kind": "building", "id": bid, "cell": cell}
	var t: Terrain = _terrain()
	if t != null:
		var dep: int = t.deposit_at(cell)
		if dep >= 0:
			return {"kind": "deposit", "id": dep, "cell": cell}
	return {"kind": "cell", "id": -1, "cell": cell}


## Ввод по миру разбирает Main (жесты InputService + pick_at): держать второй
## обработчик здесь значит ловить один тап дважды.
