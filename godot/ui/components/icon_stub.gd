class_name IconStub
extends Control
## Заглушка иконки: квадрат в цвете + буква. Реальные спрайты — этап 18,
## до тех пор ни один компонент не должен блокироваться отсутствием арта
## (CONVENTIONS «нужен ассет, которого нет — программная заглушка»).

var letter: String = "?"
var tint: Color = UITokens.MUTED

var _font: Font = null
var _font_size: int = UITokens.FONT_S

func setup(letter_text: String, color: Color, px: int = 16) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	letter = letter_text.substr(0, 1).to_upper()
	tint = color
	custom_minimum_size = Vector2(float(px), float(px))
	if is_inside_tree():
		_apply_theme()
	queue_redraw()

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
