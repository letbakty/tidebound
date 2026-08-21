class_name PixelButton
extends Button
## Кнопка проекта: вариация темы выбирается полем, а не локальными цветами.
## Локальные цвета и шрифты в компонентах запрещены (docs/01 §1.2).

enum Variant { NORMAL, PRIMARY, DANGER, GHOST }

const VARIATION_NAMES: Dictionary[int, String] = {
	Variant.NORMAL: "",
	Variant.PRIMARY: "ButtonPrimary",
	Variant.DANGER: "ButtonDanger",
	Variant.GHOST: "ButtonGhost",
}

@export var variant: Variant = Variant.NORMAL:
	set(v):
		variant = v
		_apply_variant()

func _ready() -> void:
	_apply_defaults()
	# На таче наведения нет: подсказку показывает удержание (docs/01 §5).
	var hold: TouchTooltip = TouchTooltip.new()
	hold.name = "Hold"
	add_child(hold)
	hold.setup(self)

func _make_custom_tooltip(for_text: String) -> Object:
	return TooltipView.make(for_text)

## Зовётся и из _ready, и из setup: компонент обязан быть настроенным ещё до
## входа в дерево — иначе его нельзя ни проверить тестом, ни собрать заранее.
func _apply_defaults() -> void:
	_apply_variant()
	# Цели касания задаются из токенов, а не в инспекторе: смена TOUCH_MIN
	# должна двигать ВСЕ цели разом (research/19 §5, п.5).
	custom_minimum_size = custom_minimum_size.max(
		Vector2(float(UITokens.TOUCH_MIN), float(UITokens.TOUCH_MIN)))
	focus_mode = Control.FOCUS_ALL
	# Ни обрезки, ни принудительного переноса: кнопка растёт под текст. Длинное
	# русское слово переносится там, где ширину задали явно (docs/03 §8);
	# автоперенос по умолчанию складывал бы узкие кнопки в столбик по букве.
	clip_text = false

## text_key — ключ локализации; Button переводит text сам при смене языка.
func setup(text_key: String, v: Variant = Variant.NORMAL) -> void:
	_apply_defaults()
	text = text_key
	variant = v

func _apply_variant() -> void:
	theme_type_variation = StringName(VARIATION_NAMES.get(int(variant), ""))
