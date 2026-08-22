class_name BuildRadial
extends Control
## Радиал стройки: долгое нажатие по месту (или B у курсора) — до шести
## доступных построек, седьмой слот «ещё» открывает вторую страницу.
##
## Сам ничего не строит: выбор уходит наружу сигналом, размещением занимается
## призрак в мире (game/build_ghost.gd) и Game.cmd_place_building.

signal building_chosen(def_id: String, at_world: Vector2)
signal cancelled()

const PER_PAGE: int = RadialMenu.MAX_SLOTS - 1     # шестой слот — «ещё»

var _radial: RadialMenu = null
var _ids: Array[String] = []
var _page: int = 0
var _world_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radial = RadialMenu.new()
	_radial.name = "Radial"
	add_child(_radial)
	_radial.slot_picked.connect(_on_slot_picked)
	_radial.cancelled.connect(func() -> void: cancelled.emit())

## screen_pos — точка жеста, world_pos — она же в координатах мира.
func open_at(screen_pos: Vector2, world_pos: Vector2, gesture_active: bool) -> void:
	_ids = Game.query_unlocked_buildings()
	_page = 0
	_world_pos = world_pos
	_radial.open_at(screen_pos, _slots(), gesture_active)

func close() -> void:
	_radial.close()

func is_open() -> bool:
	return _radial.is_open()

## Страница построек плюс слот «ещё», если их больше шести.
func _slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var from: int = _page * PER_PAGE
	var page_ids: Array[String] = _ids.slice(from, from + PER_PAGE)
	for id: String in page_ids:
		var d: BuildingDef = DB.building(id)
		out.append({
			"label": d.display_key, "letter": id.substr(0, 1).to_upper(),
			"color": UIPalette.warm(), "enabled": true, "def_id": id,
		})
	if _ids.size() > PER_PAGE:
		out.append({"label": "RADIAL_MORE", "letter": "+",
			"color": UIPalette.accent(), "enabled": true, "def_id": ""})
	return out

func _on_slot_picked(index: int) -> void:
	var slots: Array[Dictionary] = _slots()
	if index >= slots.size():
		return
	var def_id: String = str(slots[index].get("def_id", ""))
	if def_id.is_empty():
		# «Ещё»: следующая страница по кругу, радиал остаётся на месте.
		_page = (_page + 1) % maxi(int(ceil(float(_ids.size()) / float(PER_PAGE))), 1)
		_radial.open_at(_radial.center(), _slots(), false)
		return
	building_chosen.emit(def_id, _world_pos)
