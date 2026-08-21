class_name UIThemeFactory
extends RefCounted
## Сборка Theme из токенов. Логика вынесена сюда, чтобы её звали двое:
## ui/theme/theme_builder.gd (EditorScript, File -> Run) и
## tools/gen_theme.gd (headless, как остальные генераторы проекта).
##
## Правило скина (docs/01 §1.2): вид меняется правкой токенов и перегенерацией,
## сцены компонентов не трогаются НИКОГДА.

const OUT_PATH: String = "res://ui/theme/main_theme.tres"

## Этап 18 переключит в true: те же _build_* будут звать текстурную фабрику
## стилей поверх атласа. Тело сборки при этом не меняется.
const USE_ATLAS: bool = false

## Вариации типов из docs/01 §1.2. Ключ — имя вариации, значение — базовый тип.
const VARIATIONS: Dictionary[String, String] = {
	"PanelDark": "PanelContainer",
	"PanelHud": "PanelContainer",
	"PanelRaised": "PanelContainer",
	"CardPanel": "PanelContainer",
	"TooltipPanel": "PanelContainer",
	"ButtonPrimary": "Button",
	"ButtonDanger": "Button",
	"ButtonGhost": "Button",
	"LabelTitle": "Label",
	"LabelSmall": "Label",
	"LabelNum": "Label",
	"TooltipLabel": "Label",
}

static func build() -> Theme:
	var th: Theme = Theme.new()
	th.default_font = ui_font()
	th.default_font_size = UITokens.FONT_S

	_build_panel(th)
	_build_button(th)
	_build_label(th)
	_build_slider(th)
	_build_checkbox(th)
	_build_lineedit(th)
	_build_containers(th)
	_build_tabs(th)
	_build_scroll(th)
	_build_progress(th)
	_build_tooltip(th)
	_build_variations(th)
	return th

static func save(th: Theme, path: String = OUT_PATH) -> Error:
	return ResourceSaver.save(th, path)

# --- Шрифты ---------------------------------------------------------------

## Фолбэк обязателен: без файла шрифта этап не должен блокироваться
## (CONVENTIONS «если нет ассета — заглушка»).
static func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		return load(path) as Font
	push_warning("UIThemeFactory: нет шрифта %s, взят системный (TODO)" % path)
	return ThemeDB.get_default_theme().default_font

static func ui_font() -> Font:
	return _load_font(UITokens.FONT_UI_PATH)

## Моноширинный для чисел, которые сравнивают глазами (docs/01 §4),
## и для стрелок-символов, которых нет в основном шрифте.
static func num_font() -> Font:
	return _load_font(UITokens.FONT_NUM_PATH)

# --- Фабрики стилей -------------------------------------------------------

## anti_aliasing = false обязателен: дефолт true даёт полупрозрачные кромки,
## в пиксель-арте это грязь (research/19 §2).
static func flat(bg: Color, border: Color, w: int = UITokens.BORDER_W,
		margin: int = UITokens.SPACE_2) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(w)
	sb.set_corner_radius_all(UITokens.RADIUS_MAX)
	sb.anti_aliasing = false
	sb.set_content_margin_all(margin)
	return sb

static func empty(margin: int = 0) -> StyleBoxEmpty:
	var sb: StyleBoxEmpty = StyleBoxEmpty.new()
	sb.set_content_margin_all(margin)
	return sb

## Рамка фокуса рисуется ПОВЕРХ обычного стиля: фон прозрачный, кромка ACCENT.
static func focus_box() -> StyleBoxFlat:
	var sb: StyleBoxFlat = flat(Color(0, 0, 0, 0), UITokens.ACCENT,
		UITokens.BORDER_FOCUS)
	return sb

# --- Базовые типы ---------------------------------------------------------

static func _build_panel(th: Theme) -> void:
	th.set_stylebox("panel", "Panel", flat(UITokens.panel_color(), UITokens.BORDER))
	th.set_stylebox("panel", "PanelContainer",
		flat(UITokens.panel_color(), UITokens.BORDER, UITokens.BORDER_W, UITokens.SPACE_3))

static func _build_button(th: Theme) -> void:
	th.set_stylebox("normal", "Button",
		flat(UITokens.RAISE, UITokens.BORDER, UITokens.BORDER_W, UITokens.SPACE_3))
	th.set_stylebox("hover", "Button",
		flat(UITokens.RAISE.lightened(0.08), UITokens.BORDER_STRONG,
			UITokens.BORDER_W, UITokens.SPACE_3))
	th.set_stylebox("pressed", "Button",
		flat(UITokens.RAISE.darkened(0.2), UITokens.ACCENT,
			UITokens.BORDER_W, UITokens.SPACE_3))
	th.set_stylebox("disabled", "Button",
		flat(UITokens.PANEL_BG, UITokens.DIVIDER, UITokens.BORDER_W, UITokens.SPACE_3))
	th.set_stylebox("focus", "Button", focus_box())
	th.set_color("font_color", "Button", UITokens.INK)
	th.set_color("font_hover_color", "Button", UITokens.INK)
	th.set_color("font_pressed_color", "Button", UITokens.ACCENT)
	th.set_color("font_focus_color", "Button", UITokens.INK)
	th.set_color("font_disabled_color", "Button", UITokens.FAINT)
	th.set_font_size("font_size", "Button", UITokens.FONT_S)
	th.set_constant("h_separation", "Button", UITokens.SPACE_2)

static func _build_label(th: Theme) -> void:
	th.set_color("font_color", "Label", UITokens.INK)
	th.set_color("font_outline_color", "Label", UITokens.PAPER)
	th.set_constant("outline_size", "Label", 0)
	th.set_constant("line_spacing", "Label", UITokens.SPACE_1)
	th.set_font_size("font_size", "Label", UITokens.FONT_S)
	th.set_stylebox("normal", "Label", empty())

static func _build_slider(th: Theme) -> void:
	th.set_stylebox("slider", "HSlider", flat(UITokens.RAISE, UITokens.BORDER,
		UITokens.BORDER_HAIR, 0))
	th.set_stylebox("grabber_area", "HSlider", flat(UITokens.WATER_COLD,
		UITokens.BORDER, UITokens.BORDER_HAIR, 0))
	th.set_stylebox("grabber_area_highlight", "HSlider", flat(UITokens.ACCENT_SHADE,
		UITokens.ACCENT, UITokens.BORDER_HAIR, 0))
	th.set_constant("center_grabber", "HSlider", 1)
	th.set_stylebox("focus", "HSlider", focus_box())

static func _build_checkbox(th: Theme) -> void:
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		th.set_stylebox(state, "CheckBox", empty(UITokens.SPACE_2))
	th.set_stylebox("focus", "CheckBox", focus_box())
	th.set_color("font_color", "CheckBox", UITokens.INK)
	th.set_color("font_disabled_color", "CheckBox", UITokens.FAINT)
	th.set_font_size("font_size", "CheckBox", UITokens.FONT_S)
	th.set_constant("h_separation", "CheckBox", UITokens.SPACE_2)

static func _build_lineedit(th: Theme) -> void:
	th.set_stylebox("normal", "LineEdit",
		flat(UITokens.PAPER, UITokens.BORDER, UITokens.BORDER_W, UITokens.SPACE_2))
	th.set_stylebox("focus", "LineEdit", focus_box())
	th.set_stylebox("read_only", "LineEdit",
		flat(UITokens.PAPER, UITokens.DIVIDER, UITokens.BORDER_W, UITokens.SPACE_2))
	th.set_color("font_color", "LineEdit", UITokens.INK)
	th.set_color("font_placeholder_color", "LineEdit", UITokens.FAINT)
	th.set_color("caret_color", "LineEdit", UITokens.ACCENT)
	th.set_color("selection_color", "LineEdit", UITokens.ACCENT_SHADE)
	th.set_font_size("font_size", "LineEdit", UITokens.FONT_S)

static func _build_containers(th: Theme) -> void:
	th.set_constant("separation", "HBoxContainer", UITokens.SPACE_2)
	th.set_constant("separation", "VBoxContainer", UITokens.SPACE_2)
	th.set_constant("h_separation", "GridContainer", UITokens.SPACE_2)
	th.set_constant("v_separation", "GridContainer", UITokens.SPACE_2)
	th.set_constant("margin_left", "MarginContainer", UITokens.SPACE_3)
	th.set_constant("margin_right", "MarginContainer", UITokens.SPACE_3)
	th.set_constant("margin_top", "MarginContainer", UITokens.SPACE_3)
	th.set_constant("margin_bottom", "MarginContainer", UITokens.SPACE_3)
	th.set_stylebox("separator", "HSeparator",
		flat(UITokens.DIVIDER, UITokens.DIVIDER, 0, 0))
	th.set_constant("separation", "HSeparator", UITokens.BORDER_HAIR)

static func _build_tabs(th: Theme) -> void:
	th.set_stylebox("panel", "TabContainer",
		flat(UITokens.panel_color(), UITokens.BORDER, UITokens.BORDER_W, UITokens.SPACE_3))
	th.set_stylebox("tab_selected", "TabContainer",
		flat(UITokens.RAISE, UITokens.ACCENT, UITokens.BORDER_W, UITokens.SPACE_3))
	th.set_stylebox("tab_unselected", "TabContainer",
		flat(UITokens.PANEL_BG, UITokens.BORDER, UITokens.BORDER_W, UITokens.SPACE_3))
	th.set_stylebox("tab_hovered", "TabContainer",
		flat(UITokens.RAISE, UITokens.BORDER_STRONG, UITokens.BORDER_W, UITokens.SPACE_3))
	th.set_stylebox("tab_focus", "TabContainer", focus_box())
	th.set_color("font_selected_color", "TabContainer", UITokens.ACCENT)
	th.set_color("font_unselected_color", "TabContainer", UITokens.MUTED)
	th.set_color("font_hovered_color", "TabContainer", UITokens.INK)
	th.set_font_size("font_size", "TabContainer", UITokens.FONT_S)
	th.set_stylebox("tab_selected", "TabBar",
		flat(UITokens.RAISE, UITokens.ACCENT, UITokens.BORDER_W, UITokens.SPACE_3))
	th.set_stylebox("tab_unselected", "TabBar",
		flat(UITokens.PANEL_BG, UITokens.BORDER, UITokens.BORDER_W, UITokens.SPACE_3))
	th.set_stylebox("tab_focus", "TabBar", focus_box())
	th.set_color("font_selected_color", "TabBar", UITokens.ACCENT)
	th.set_color("font_unselected_color", "TabBar", UITokens.MUTED)
	th.set_font_size("font_size", "TabBar", UITokens.FONT_S)

static func _build_scroll(th: Theme) -> void:
	th.set_stylebox("panel", "ScrollContainer", empty())
	th.set_stylebox("scroll", "VScrollBar", flat(UITokens.PAPER, UITokens.DIVIDER,
		UITokens.BORDER_HAIR, 0))
	th.set_stylebox("grabber", "VScrollBar", flat(UITokens.BORDER, UITokens.BORDER,
		0, 0))
	th.set_stylebox("grabber_highlight", "VScrollBar", flat(UITokens.BORDER_STRONG,
		UITokens.BORDER_STRONG, 0, 0))
	th.set_stylebox("grabber_pressed", "VScrollBar", flat(UITokens.ACCENT_SHADE,
		UITokens.ACCENT, 0, 0))

static func _build_progress(th: Theme) -> void:
	th.set_stylebox("background", "ProgressBar", flat(UITokens.PAPER,
		UITokens.BORDER, UITokens.BORDER_HAIR, 0))
	th.set_stylebox("fill", "ProgressBar", flat(UITokens.WATER_COLD,
		UITokens.WATER_COLD, 0, 0))
	th.set_font_size("font_size", "ProgressBar", UITokens.FONT_S)
	th.set_color("font_color", "ProgressBar", UITokens.INK)

## Тултип рисуется как PanelContainer + Label с типами TooltipPanel/TooltipLabel —
## вариация от Panel не сработает (research/19 §2).
static func _build_tooltip(th: Theme) -> void:
	th.set_stylebox("panel", "TooltipPanel",
		flat(UITokens.PAPER, UITokens.BORDER, UITokens.BORDER_W, UITokens.SPACE_3))
	th.set_color("font_color", "TooltipLabel", UITokens.INK)
	th.set_font_size("font_size", "TooltipLabel", UITokens.FONT_S)

# --- Вариации типов -------------------------------------------------------

static func _build_variations(th: Theme) -> void:
	for name: String in VARIATIONS:
		th.set_type_variation(name, VARIATIONS[name])

	th.set_stylebox("panel", "PanelDark",
		flat(UITokens.PAPER, UITokens.BORDER, UITokens.BORDER_W, UITokens.SPACE_3))
	th.set_stylebox("panel", "PanelRaised",
		flat(UITokens.RAISE, UITokens.BORDER_STRONG, UITokens.BORDER_W, UITokens.SPACE_3))
	# Полоса HUD: отступы минимальные, иначе строка съедает восьмую часть экрана.
	th.set_stylebox("panel", "PanelHud",
		flat(UITokens.panel_color(), UITokens.BORDER, UITokens.BORDER_W, UITokens.SPACE_1))
	th.set_stylebox("panel", "CardPanel",
		flat(UITokens.RAISE, UITokens.BORDER, UITokens.BORDER_W, UITokens.SPACE_4))

	th.set_stylebox("normal", "ButtonPrimary",
		flat(UITokens.ACCENT, UITokens.ACCENT, UITokens.BORDER_W, UITokens.SPACE_3))
	th.set_stylebox("hover", "ButtonPrimary",
		flat(UITokens.ACCENT.lightened(0.1), UITokens.INK, UITokens.BORDER_W, UITokens.SPACE_3))
	th.set_stylebox("pressed", "ButtonPrimary",
		flat(UITokens.ACCENT_SHADE, UITokens.ACCENT, UITokens.BORDER_W, UITokens.SPACE_3))
	th.set_stylebox("disabled", "ButtonPrimary",
		flat(UITokens.ACCENT_SHADE.darkened(0.3), UITokens.DIVIDER,
			UITokens.BORDER_W, UITokens.SPACE_3))
	# Текст на янтаре — тёмный: контраст светлого по светлому не проходит.
	th.set_color("font_color", "ButtonPrimary", UITokens.PAPER)
	th.set_color("font_hover_color", "ButtonPrimary", UITokens.PAPER)
	th.set_color("font_pressed_color", "ButtonPrimary", UITokens.INK)
	th.set_color("font_focus_color", "ButtonPrimary", UITokens.PAPER)
	th.set_color("font_disabled_color", "ButtonPrimary", UITokens.FAINT)

	th.set_stylebox("normal", "ButtonDanger",
		flat(UITokens.DANGER, UITokens.DANGER, UITokens.BORDER_W, UITokens.SPACE_3))
	th.set_stylebox("hover", "ButtonDanger",
		flat(UITokens.DANGER.lightened(0.1), UITokens.INK, UITokens.BORDER_W, UITokens.SPACE_3))
	th.set_stylebox("pressed", "ButtonDanger",
		flat(UITokens.DANGER.darkened(0.2), UITokens.DANGER, UITokens.BORDER_W, UITokens.SPACE_3))
	th.set_color("font_color", "ButtonDanger", UITokens.INK)
	th.set_color("font_hover_color", "ButtonDanger", UITokens.INK)

	th.set_stylebox("normal", "ButtonGhost",
		flat(Color(0, 0, 0, 0), UITokens.BORDER, UITokens.BORDER_HAIR, UITokens.SPACE_3))
	th.set_stylebox("hover", "ButtonGhost",
		flat(Color(0, 0, 0, 0), UITokens.BORDER_STRONG, UITokens.BORDER_HAIR, UITokens.SPACE_3))
	th.set_stylebox("pressed", "ButtonGhost",
		flat(UITokens.RAISE, UITokens.ACCENT, UITokens.BORDER_HAIR, UITokens.SPACE_3))
	th.set_color("font_color", "ButtonGhost", UITokens.MUTED)
	th.set_color("font_hover_color", "ButtonGhost", UITokens.INK)

	th.set_font_size("font_size", "LabelTitle", UITokens.FONT_L)
	th.set_color("font_color", "LabelTitle", UITokens.INK)
	th.set_font_size("font_size", "LabelSmall", UITokens.FONT_S)
	th.set_color("font_color", "LabelSmall", UITokens.MUTED)
	# Числа — моноширинные: колонки ресурсов и очков сравнивают глазами.
	th.set_font("font", "LabelNum", num_font())
	th.set_font_size("font_size", "LabelNum", UITokens.FONT_S)
	th.set_color("font_color", "LabelNum", UITokens.INK)
