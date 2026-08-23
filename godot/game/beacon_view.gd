class_name BeaconView
extends Node2D
## Маркер маяка: спрайт (assets/sprites/beacon.png, сборщик tools/gen_decor.gd)
## и полупрозрачный круг радиуса притяжения работ, пока идёт установка
## (docs/00 §6.7).

const SPRITE: String = "res://assets/sprites/beacon.png"
## Высота флажка-заглушки, если спрайта нет.
const FLAG_H: float = 18.0

var _cell: Vector2i = Balance.NO_BEACON
var _show_radius: bool = false
var _sprite: Sprite2D = null

func _ready() -> void:
	z_index = 92
	var tex: Texture2D = load(SPRITE) as Texture2D
	if tex != null:
		_sprite = Sprite2D.new()
		_sprite.texture = tex
		# Древко стоит на клетке: якорь снизу по центру, как у агентов.
		_sprite.centered = false
		_sprite.offset = Vector2(-float(tex.get_width()) * 0.5,
			-float(tex.get_height()))
		_sprite.visible = false
		add_child(_sprite)
	Events.beacon_moved.connect(_on_moved)
	Events.run_started.connect(func(_s: int) -> void:
		_cell = Balance.NO_BEACON
		_sync_sprite()
		queue_redraw())

## Радиус показываем только в режиме установки: постоянный круг — шум.
func set_placing(on: bool) -> void:
	_show_radius = on
	queue_redraw()

func _on_moved(cell: Vector2i) -> void:
	_cell = cell
	_sync_sprite()
	queue_redraw()

func _sync_sprite() -> void:
	if _sprite == null:
		return
	_sprite.visible = _cell != Balance.NO_BEACON
	if _sprite.visible:
		_sprite.position = WorldGeo.cell_center_world(_cell)

func _draw() -> void:
	if _cell == Balance.NO_BEACON:
		return
	var p: Vector2 = WorldGeo.cell_center_world(_cell)
	var accent: Color = UIPalette.accent()
	if _show_radius:
		draw_circle(p, Balance.BEACON_RADIUS * float(WorldGeo.TILE),
			Color(accent.r, accent.g, accent.b, 0.10))
		draw_arc(p, Balance.BEACON_RADIUS * float(WorldGeo.TILE), 0.0, TAU, 48,
			accent, 1.0)
	if _sprite != null:
		return
	# Запасной флажок, если спрайта нет.
	draw_line(p, p - Vector2(0.0, FLAG_H), accent, 2.0)
	draw_colored_polygon(PackedVector2Array([
		p - Vector2(0.0, FLAG_H),
		p - Vector2(-10.0, FLAG_H - 5.0),
		p - Vector2(0.0, FLAG_H - 10.0)]), accent)
