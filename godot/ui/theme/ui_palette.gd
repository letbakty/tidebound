class_name UIPalette
extends RefCounted
## Живая палитра: токены — источник значений, а этот класс отдаёт их с учётом
## настроек доступности (docs/03 §3.6).
##
## Пресеты для дальтоников не «фильтр поверх экрана», а подмена ровно четырёх
## семантических цветов: опасность, успех, акцент и вода. Остальные цвета
## различаются светлотой и в подмене не нуждаются.
##
## ⚠️ Цвет никогда не единственный канал (docs/01 §6): у тренда есть стрелка,
## у опасности — иконка. Пресеты чинят различимость, а не заменяют форму.

## Красный и зелёный сливаются: опасность уводим в оранжево-розовое,
## успех — в сине-зелёное.
const PROTAN: Dictionary[String, Color] = {
	"danger": Color("e06a3f"), "success": Color("4a9ec9"),
	"accent": Color("e8c170"), "water": Color("2d6b7a"),
}
const DEUTER: Dictionary[String, Color] = {
	"danger": Color("d4553a"), "success": Color("57a8d8"),
	"accent": Color("f0d060"), "water": Color("2d6b7a"),
}
## Сине-жёлтая пара: акцент уводим в розовый, воду — в зелёно-бирюзовую.
const TRITAN: Dictionary[String, Color] = {
	"danger": Color("d4553a"), "success": Color("7aa85e"),
	"accent": Color("e88fb0"), "water": Color("3f9c8a"),
}

static var _mode: int = 0
static var _contrast: bool = false

## Зовётся из Settings.apply(): 0 — выключено, 1..3 — пресеты.
static func apply(colorblind_mode: int, high_contrast: bool) -> void:
	_mode = colorblind_mode
	_contrast = high_contrast

static func mode() -> int:
	return _mode

static func high_contrast() -> bool:
	return _contrast

static func _preset() -> Dictionary[String, Color]:
	match _mode:
		1: return PROTAN
		2: return DEUTER
		3: return TRITAN
	return {}

## Подменяет семантический цвет. Несемантические возвращает как есть.
static func map(c: Color) -> Color:
	var preset: Dictionary[String, Color] = _preset()
	if preset.is_empty():
		return c
	if c.is_equal_approx(UITokens.DANGER):
		return preset["danger"]
	if c.is_equal_approx(UITokens.SUCCESS):
		return preset["success"]
	if c.is_equal_approx(UITokens.ACCENT):
		return preset["accent"]
	if c.is_equal_approx(UITokens.WATER_COLD):
		return preset["water"]
	return c

static func danger() -> Color:
	return map(UITokens.DANGER)

static func success() -> Color:
	return map(UITokens.SUCCESS)

static func accent() -> Color:
	return map(UITokens.ACCENT)

static func water() -> Color:
	return map(UITokens.WATER_COLD)

## Подложка панели: при повышенном контрасте она непрозрачна и темнее.
static func panel() -> Color:
	if _contrast:
		return UITokens.PAPER
	return UITokens.panel_color()

## Кромка панели: при повышенном контрасте — светлее и заметнее.
static func border() -> Color:
	return UITokens.BORDER_STRONG if _contrast else UITokens.BORDER
