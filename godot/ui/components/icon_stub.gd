class_name IconStub
extends Control
## Иконка предмета или постройки. Настоящий арт лежит атласами
## (tools/gen_icons.gd, tools/gen_buildings.gd); если атласа нет или id
## незнаком, остаётся прежняя заглушка — квадрат в цвете и буква. Имя класса
## менять не стали: заглушка никуда не делась и остаётся честным запасным путём
## (CONVENTIONS «нужен ассет, которого нет — не блокируйся»).
##
## ⚠️ Номер кадра считается по DB.item_ids()/DB.building_ids() — тому же
## отсортированному списку, по которому атлас собирается. Второго списка в
## интерфейсе нет намеренно: он бы разъехался с генератором молча, а
## разъехавшийся атлас показывает не ту иконку и не падает.

const ITEM_ATLAS: String = "res://assets/sprites/item_icons.png"
const BUILDING_ATLAS: String = "res://assets/sprites/building_icons.png"
const ITEM_CELL: int = 16
const BUILDING_CELL: int = 24

var letter: String = "?"
var tint: Color = UITokens.MUTED

## Атласы грузятся один раз на весь интерфейс: IconStub живёт десятками.
static var _item_tex: Texture2D = null
static var _building_tex: Texture2D = null
static var _loaded: bool = false

var _tex: Texture2D = null
var _region: Rect2 = Rect2()
var _font: Font = null
var _font_size: int = UITokens.FONT_S

func setup(letter_text: String, color: Color, px: int = 16) -> void:
	_tex = null
	_apply(letter_text, color, px)

## Иконка предмета по его id (data/items/*.tres).
func setup_item(item_id: String, color: Color, px: int = 16) -> void:
	_ensure_atlases()
	var idx: int = DB.item_ids().find(item_id)
	_tex = _item_tex if idx >= 0 else null
	if _tex != null:
		_region = Rect2(float(idx * ITEM_CELL), 0.0, float(ITEM_CELL),
			float(ITEM_CELL))
	_apply(item_id.substr(0, 1), color, px)

## Иконка постройки по её def_id (data/buildings/*.tres).
func setup_building(def_id: String, color: Color, px: int = BUILDING_CELL) -> void:
	_ensure_atlases()
	var idx: int = DB.building_ids().find(def_id)
	_tex = _building_tex if idx >= 0 else null
	if _tex != null:
		_region = Rect2(float(idx * BUILDING_CELL), 0.0, float(BUILDING_CELL),
			float(BUILDING_CELL))
	_apply(def_id.substr(0, 1), color, px)

func _apply(letter_text: String, color: Color, px: int) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	letter = letter_text.substr(0, 1).to_upper()
	tint = color
	custom_minimum_size = Vector2(float(px), float(px))
	if is_inside_tree():
		_apply_theme()
	queue_redraw()

static func _ensure_atlases() -> void:
	if _loaded:
		return
	_loaded = true
	_item_tex = load(ITEM_ATLAS) as Texture2D
	_building_tex = load(BUILDING_ATLAS) as Texture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_theme()

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_apply_theme()

## Тема кэшируется: get_theme_* внутри _draw заметно дороже (research/19 §5).
func _apply_theme() -> void:
	_font = get_theme_font("font", "Label")
	_font_size = get_theme_font_size("font_size", "Label")
	queue_redraw()

func _draw() -> void:
	if _tex != null:
		_draw_icon()
		return
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(tint.r, tint.g, tint.b, 0.25), true)
	# Ширина линий задаётся явно: в 4.7 CanvasItem больше не добавляет
	# AA-feather, и рамка при -1.0 почти не видна (research/06 §9).
	draw_rect(r, tint, false, 1.0)
	if _font == null:
		return
	var fs: int = mini(_font_size, int(size.y) - 2)
	if fs < 6:
		return
	var text_size: Vector2 = _font.get_string_size(letter,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs)
	var pos: Vector2 = Vector2(
		roundf((size.x - text_size.x) * 0.5),
		roundf((size.y + float(fs) * 0.7) * 0.5))
	draw_string(_font, pos, letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, tint)

## ⚠️ Иконка рисуется в РОДНОМ размере и по целым координатам, даже если
## контрол больше. Растянуть 16 px на 24 значит получить дробный масштаб — те
## самые «то два, то три экранных пикселя», ради которых весь пиксель-арт и
## затевался. Меньше родного размера — единственный случай, когда масштаб
## оправдан, и он всё равно целый.
func _draw_icon() -> void:
	var src: Vector2 = _region.size
	var scale: int = maxi(1, mini(int(size.x / src.x), int(size.y / src.y)))
	var dst: Vector2 = src * float(scale)
	var at: Vector2 = ((size - dst) * 0.5).floor()
	draw_texture_rect_region(_tex, Rect2(at, dst), _region)
