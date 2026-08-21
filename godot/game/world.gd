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

const DEPOSIT_COLORS: Dictionary = {
	"ruins_near": Color("8a8f7a"),
	"ruins_deep": Color("6f7f8a"),
	"shallow": Color("c9a26b"),
	"kelp": Color("4f7a4a"),
}

@onready var ground: TileMapLayer = $Ground
@onready var ladders: TileMapLayer = $Ladders
@onready var deposits_root: Node2D = $Deposits
@onready var agents_root: Node2D = $Agents
@onready var buildings_root: Node2D = $Buildings
@onready var creatures_root: Node2D = $Creatures
@onready var ghost: BuildGhost = $BuildGhost
@onready var camera: CameraRig = $CameraRig

## Игровые оверлеи (этап 13): отметки ярусов, зона затопления, занятия.
var overlay: GameOverlay = null
## Маркер маяка (этап 14).
var beacon: BeaconView = null

func get_overlay() -> GameOverlay:
	return overlay

var _deposit_nodes: Dictionary[int, Node2D] = {}
var _agent_views: Dictionary[int, AgentView] = {}
var _building_views: Dictionary[int, BuildingView] = {}
var _creature_views: Dictionary[int, CreatureView] = {}
var _drawn_graph_version: int = -1

func _ready() -> void:
	overlay = GameOverlay.new()
	overlay.name = "GameOverlay"
	add_child(overlay)
	beacon = BeaconView.new()
	beacon.name = "BeaconView"
	add_child(beacon)
	Events.run_started.connect(_on_run_started)
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

func _terrain() -> Terrain:
	if Game.world == null:
		return null
	return Game.world.terrain

func _on_run_started(_seed_value: int) -> void:
	_rebuild_all()

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

func _on_building_changed(id: int) -> void:
	var v: BuildingView = _building_views.get(id, null)
	if v == null:
		_on_building_placed(id)
		return
	v.refresh()

func _on_building_removed(id: int) -> void:
	var v: BuildingView = _building_views.get(id, null)
	if v == null:
		return
	_building_views.erase(id)
	v.queue_free()

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
# ЕДИНСТВЕННЫЙ хелпер конверсии экран↔мир на весь проект (docs/01 §1.1).
# Конвертировать «на месте» в других файлах запрещено.

func screen_to_world(viewport_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * viewport_pos

func world_to_screen(world_pos: Vector2) -> Vector2:
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
