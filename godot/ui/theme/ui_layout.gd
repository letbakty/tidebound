class_name UILayout
extends RefCounted
## Мелкие правила раскладки, которые иначе повторяются в каждой панели.

## ⚠️ Label с автопереносом и БЕЗ заданной ширины сообщает минимальную ширину 1
## и считает высоту так, будто каждая буква на своей строке: подсказка в четыре
## строки требует 1500 px и выпихивает панель за экран.
## Поэтому автоперенос включаем ТОЛЬКО вместе с шириной.
static func wrap(label: Label, min_width: float) -> void:
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(min_width, label.custom_minimum_size.y)
