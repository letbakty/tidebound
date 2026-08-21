class_name UITokens
extends RefCounted
## Единственный источник значений интерфейса: цвета, кегли, отступы, размеры.
## Правишь здесь -> перегенерируешь тему (ui/theme/theme_builder.gd, File -> Run
## или tools/gen_theme.gd headless) -> меняется вид ВСЕХ компонентов.
##
## Значения взяты из принятого UI-кита design/tidebound-ui-kit.dc.html (артборд A),
## а не выведены из текста docs/01: кит — источник правды по визуалу.
##
## В сценах компонентов цвета и кегли задавать ЗАПРЕЩЕНО (docs/01 §1.2):
## только theme items и theme_type_variation.

# --- Палитра: 16 рабочих цветов, четыре группы (кит, артборд A) -----------

# Поверхности (6)
const PAPER: Color = Color("0a1216")     # фон экрана, вырезы шкалы
const PANEL_BG: Color = Color("0e1a20")     # подложка панели (см. PANEL_ALPHA)
const RAISE: Color = Color("16262e")     # вложенный блок, слот
const BORDER: Color = Color("2a4550")     # кромка панели, 2 px
const BORDER_STRONG: Color = Color("3d6270")   # активная кромка, ховер
const DIVIDER: Color = Color("1e343d")     # разделитель 1 px

# Текст (3). INK — «чернила» на тёмной подложке, не наоборот.
const INK: Color = Color("e8eff0")      # всё читаемое
const MUTED: Color = Color("9aabb0")     # подписи, вторичное
const FAINT: Color = Color("64757c")     # disabled, мета, единицы

# Семантика (4)
const ACCENT: Color = Color("e8c170")     # действие, фокус, свет
const ACCENT_SHADE: Color = Color("8a7442")    # нажатие, disabled-акцент
const DANGER: Color = Color("d4553a")     # сигнал, шторм, смерть
const SUCCESS: Color = Color("7aa85e")     # рост, завершение

# Декор: вертикаль как ось смысла (3)
const WATER_COLD: Color = Color("2d6b7a")    # вода, кромка воды
const COLD_DEEP: Color = Color("1a3a4a")    # глубина ниже −6
const WARM: Color = Color("c9a15e")      # верх утёса, жильё, очаг

## Прозрачность подложки панели: мир под ней читается, текст — нет (кит).
const PANEL_ALPHA: float = 0.92

# --- Отступы: единственная шкала ------------------------------------------
const SPACE_1: int = 4
const SPACE_2: int = 8
const SPACE_3: int = 12
const SPACE_4: int = 16
const SPACE_5: int = 24
const SPACE_6: int = 32
const SPACE_7: int = 48

# --- Кегли: кратно 8, иначе пиксель-шрифт мылит (research/19 §4) ----------
const FONT_S: int = 16   # подпись, ПК
const FONT_M: int = 24   # корпус, телефон
const FONT_L: int = 32   # экранный титул
const FONT_TITLE: int = 48  # заголовок <= 24 знаков

# --- Рамки и фокус --------------------------------------------------------
const BORDER_HAIR: int = 1  # разделитель внутри панели
const BORDER_W: int = 2   # кромка панели и кнопки
const BORDER_FOCUS: int = 3  # рамка фокуса (клавиатура и геймпад)
## Скруглений в пиксель-арте нет; потолок оставлен на случай исключения.
const RADIUS_MAX: int = 0

# --- Тач и цели -----------------------------------------------------------
const TOUCH_MIN: int = 48  # любая интерактивная цель, dp
const TOUCH_GAP: int = 8  # зазор между целями, dp
## Правая нижняя четверть под кнопкой «Отзыв»: тостов и панелей там нет.
const DEADZONE_PX: int = 176

# --- Шкала прилива (этап 13) ---------------------------------------------
const TIDE_WIDTH: int = 56
const TIDE_TIER_H: int = 32  # высота яруса на ПК; на телефоне сжимается

# --- Движение -------------------------------------------------------------
const MOTION_PHASE_SEC: float = 0.9  # ход поплавка шкалы
const MOTION_FAST_SEC: float = 0.12  # вход тоста, подсветка
const MOTION_PANEL_SEC: float = 0.18 # шторки и bottom sheet
## Прмпт 13 п.4 требует 5 с (в ките 4 с) — приоритет у промпта.
const TOAST_LIFE_SEC: float = 5.0

# --- Шрифты ---------------------------------------------------------------
const FONT_UI_PATH: String = "res://assets/fonts/handjet.ttf"
const FONT_NUM_PATH: String = "res://assets/fonts/jetbrains_mono.ttf"

## Цвет полосы состояния агента по худшей потребности (0..100).
static func need_color(value_0_100: float) -> Color:
	if value_0_100 < 30.0:
		return UIPalette.danger()
	if value_0_100 < 55.0:
		return WARM
	return UIPalette.success()

## Цвет тренда: −1 / 0 / +1. Цвет НЕ единственный канал — рядом всегда стрелка.
static func trend_color(trend: int) -> Color:
	if trend > 0:
		return UIPalette.success()
	if trend < 0:
		return UIPalette.danger()
	return FAINT

## Подложка панели с проектной прозрачностью.
static func panel_color() -> Color:
	return Color(PANEL_BG.r, PANEL_BG.g, PANEL_BG.b, PANEL_ALPHA)
