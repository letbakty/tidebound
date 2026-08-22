extends Node
## Настройки игрока в user://settings.json (docs/03 §3.6).
##
## JSON, а не ConfigFile: пользовательский файл читается ТОЛЬКО через JSON.parse
## (docs/02 §6 — ConfigFile умеет исполнять код в значениях).
##
## Применяется СРАЗУ, без кнопки «Сохранить»: любая правка вызывает apply()
## и запись файла с дебаунсом.

const PATH: String = "user://settings.json"
const VERSION: int = 1

## Ступени масштаба UI: произвольный множитель мылит пиксель-шрифт
## (research/20 §7), поэтому только четверти.
const UI_SCALE_MIN: float = 0.75
const UI_SCALE_MAX: float = 1.5
const UI_SCALE_STEP: float = 0.25

enum Colorblind { NONE, PROTANOPIA, DEUTERANOPIA, TRITANOPIA }

## Тему надо пересобрать: сменились кегль, пресет для дальтоников или контраст.
## Пересборкой и раздачей по слоям занимается Main — Settings об узлах не знает.
signal theme_changed()
## Ремап клавиш: действие -> список описаний событий (InputEventKey.as_text()).
signal bindings_changed()

# --- Игра -----------------------------------------------------------------
var locale: String = "ru"
var hints_enabled: bool = true
## Три флажка автопаузы (docs/03 §3.6): драфт, итог цикла, первый кризис.
var pause_on_draft: bool = true
var pause_on_cycle: bool = true
var pause_on_crisis: bool = true
var default_speed: int = 1

# --- Экран ----------------------------------------------------------------
var ui_scale: float = 1.0
var world_zoom: int = 3
var fullscreen: bool = false
var vsync: bool = true
var integer_scaling: bool = false

# --- Звук -----------------------------------------------------------------
## Умолчания = стартовый баланс шин из tools/gen_bus_layout.gd (research/35
## §6.3): музыка не перекрывает колокол, эмбиент остаётся фоном, клики не
## громче мира. Оба места держат ОДНИ и те же числа: apply() перезаписывает
## громкости шин, поэтому раскладка сама по себе баланс не удержит.
var master_db: float = 0.0
var music_db: float = -6.0
var sfx_db: float = -3.0
var ui_db: float = -6.0
var ambient_db: float = -9.0
var haptics: bool = true

## Нижний конец ползунка (docs/03 §3.6) — это тишина, а не «очень тихо»:
## −40 дБ ещё слышно на технике, поэтому на минимуме шина глушится.
const MUTE_DB: float = -40.0
## Верхний конец ползунка: запас вверх есть, но не бесконечный.
const MAX_DB: float = 6.0

# --- Доступность ----------------------------------------------------------
## Размер шрифта ОТДЕЛЬНО от масштаба UI (docs/03 §3.6).
var font_scale: float = 1.0
var colorblind: Colorblind = Colorblind.NONE
var reduce_motion: bool = false
var high_contrast: bool = false
## 0 = «не закрывать сами».
var toast_seconds: float = UITokens.TOAST_LIFE_SEC
var screen_reader: bool = false

var _dirty: bool = false
## Настройки доступности НИКОГДА не отключают достижения и не помечают забег
## (docs/03 §3.2) — флага «облегчённого режима» в этом файле нет и не будет.

## Первый ли это запуск игры. ⚠️ Снимается ОДИН раз в _ready до первой записи
## файла: apply() ставит mark_dirty, и файл появляется в том же кадре — к концу
## заставки has_file() отвечает «да» на любом запуске, и экран выбора языка не
## увидел бы никто (аудит B1.3).
var first_launch: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	first_launch = not has_file()
	if not load_settings():
		# Файла нет — первый запуск: подбираем умолчания по железу.
		_apply_platform_defaults()
	apply()

## Хорошие умолчания без единого вопроса игроку (промпт 16 п.5):
## Steam Deck (1280×800) — интерфейс 125% и зум мира ×2, телефон — по DPI,
## большой десктоп — как есть.
func _apply_platform_defaults() -> void:
	var screen: Vector2i = DisplayServer.screen_get_size()
	if OS.has_feature("mobile"):
		ui_scale = clampf(dpi_scale(), UI_SCALE_MIN, UI_SCALE_MAX)
		world_zoom = 2
		return
	# 1280×800 и 1280×720 — обе «палубные» диагонали: мелкий текст с вытянутой
	# руки не читается.
	if screen.x <= 1366 and screen.y <= 800:
		ui_scale = 1.25
		world_zoom = 2

func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		save_settings()

func mark_dirty() -> void:
	_dirty = true

## Применяет ВСЁ сразу: язык, масштаб, окно, синхронизацию, громкости.
func apply() -> void:
	TranslationServer.set_locale(locale)
	var root: Window = get_tree().root
	root.content_scale_factor = effective_scale()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER \
		if integer_scaling else Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN \
		if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED \
		if vsync else DisplayServer.VSYNC_DISABLED)
	_apply_bus("Master", master_db)
	_apply_bus("Music", music_db)
	_apply_bus("SFX", sfx_db)
	_apply_bus("UI", ui_db)
	_apply_bus("Ambient", ambient_db)
	# Доступность живёт в палитре и в кегле темы: и то и другое требует
	# пересборки Theme, поэтому применяем их одним заходом.
	_apply_screen_reader()
	UIPalette.apply(int(colorblind), high_contrast)
	UIThemeFactory.font_scale = font_scale
	theme_changed.emit()
	mark_dirty()

## AccessKit включён в движке с 4.5. Поддержку включаем настройкой проекта;
## сама озвучка работает, когда в системе запущен диктор.
func _apply_screen_reader() -> void:
	var key: String = "accessibility/general/accessibility_support"
	if not ProjectSettings.has_setting(key):
		return
	# 0 — авто (по наличию диктора), 1 — всегда включено.
	ProjectSettings.set_setting(key, 1 if screen_reader else 0)

## Видит ли игра системный диктор — для честной подписи в настройках.
static func screen_reader_active() -> bool:
	if not DisplayServer.has_method("accessibility_screen_reader_active"):
		return false
	return bool(DisplayServer.call("accessibility_screen_reader_active"))

## Раскладку шин собирает tools/gen_bus_layout.gd; если её нет (старый
## default_bus_layout.tres), молча пропускаем — звук просто не настроится.
func _apply_bus(bus_name: String, db: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, db <= MUTE_DB)
	AudioServer.set_bus_volume_db(idx, db)

## Масштаб UI по плотности экрана: на телефоне 100% нечитаемы, на Deck — мелки.
## Ступени по 0.25 — пиксельный шрифт при 1.37 превращается в кашу
## (research/20 §7).
static func dpi_scale() -> float:
	var dpi: int = DisplayServer.screen_get_dpi()
	if dpi <= 0:
		return 1.0
	return clampf(snappedf(float(dpi) / 160.0, UI_SCALE_STEP), 1.0, 3.0)

## Итоговый множитель контента: плотность экрана × пользовательский ползунок.
func effective_scale() -> float:
	return snappedf(dpi_scale() * ui_scale, UI_SCALE_STEP)

## Доступность обязана применяться СРАЗУ, без перезапуска и без смены языка
## (docs/03 §3.6). Полный apply() ради кегля дёргал бы окно, звук и локаль,
## поэтому пересборка темы вынесена отдельно.
func apply_accessibility() -> void:
	UIPalette.apply(int(colorblind), high_contrast)
	UIThemeFactory.font_scale = font_scale
	theme_changed.emit()
	mark_dirty()

## Язык по системной локали — предлагается на первом запуске (docs/03 §3.2).
static func system_locale() -> String:
	return "ru" if OS.get_locale().begins_with("ru") else "en"

func set_locale(value: String) -> void:
	locale = value
	TranslationServer.set_locale(value)
	mark_dirty()

# --- Файл -----------------------------------------------------------------

# --- Ремап управления (docs/03 §3.6, промпт 16 п.6) -----------------------

## Действие -> массив «текстовых» описаний событий. Пусто = умолчания проекта.
var bindings: Dictionary = {}

## Список действий, которые игрок может переназначить. Служебные (ui_*, debug)
## сюда не входят: их ремап ломает навигацию геймпадом.
const REMAPPABLE: Array[String] = ["pan_left", "pan_right", "pan_up", "pan_down",
	"recall", "policies", "build_radial", "beacon",
	"speed_1", "speed_2", "speed_3", "pause_menu"]

## Умолчания снимаем ОДИН раз при первом обращении: после ремапа InputMap уже
## изменён, и «сбросить» стало бы нечем.
static var _defaults: Dictionary = {}

static func capture_defaults() -> void:
	if not _defaults.is_empty():
		return
	for action: String in REMAPPABLE:
		if not InputMap.has_action(action):
			continue
		_defaults[action] = InputMap.action_get_events(action).duplicate()

## Переназначает действие одним событием, сохраняя остальные.
func rebind(action: String, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		return
	capture_defaults()
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)
	bindings[action] = [event.as_text()]
	bindings_changed.emit()
	mark_dirty()

func reset_bindings() -> void:
	capture_defaults()
	for action: String in _defaults:
		InputMap.action_erase_events(action)
		for e: InputEvent in _defaults[action] as Array:
			InputMap.action_add_event(action, e)
	bindings.clear()
	bindings_changed.emit()
	mark_dirty()

## Конфликт: одна и та же клавиша на двух действиях. Возвращает набор
## действий, у которых есть пересечение — панель подсветит их красным.
func conflicts() -> Dictionary:
	var by_text: Dictionary = {}
	var bad: Dictionary = {}
	for action: String in REMAPPABLE:
		if not InputMap.has_action(action):
			continue
		for e: InputEvent in InputMap.action_get_events(action):
			var key: String = e.as_text()
			if by_text.has(key):
				bad[action] = true
				bad[str(by_text[key])] = true
			else:
				by_text[key] = action
	return bad

func to_dict() -> Dictionary:
	return {
		"version": VERSION, "locale": locale, "hints_enabled": hints_enabled,
		"pause_on_draft": pause_on_draft, "pause_on_cycle": pause_on_cycle,
		"pause_on_crisis": pause_on_crisis, "default_speed": default_speed,
		"ui_scale": ui_scale, "world_zoom": world_zoom,
		"fullscreen": fullscreen, "vsync": vsync,
		"integer_scaling": integer_scaling,
		"master_db": master_db, "music_db": music_db, "sfx_db": sfx_db,
		"ui_db": ui_db, "ambient_db": ambient_db, "haptics": haptics,
		"font_scale": font_scale, "colorblind": int(colorblind),
		"reduce_motion": reduce_motion, "high_contrast": high_contrast,
		"toast_seconds": toast_seconds, "screen_reader": screen_reader,
		"bindings": bindings.duplicate(true),
	}

func from_dict(d: Dictionary) -> void:
	locale = str(d.get("locale", system_locale()))
	hints_enabled = bool(d.get("hints_enabled", true))
	pause_on_draft = bool(d.get("pause_on_draft", true))
	pause_on_cycle = bool(d.get("pause_on_cycle", true))
	pause_on_crisis = bool(d.get("pause_on_crisis", true))
	default_speed = clampi(int(d.get("default_speed", 1)), 1, 3)
	ui_scale = clampf(float(d.get("ui_scale", 1.0)), UI_SCALE_MIN, UI_SCALE_MAX)
	world_zoom = clampi(int(d.get("world_zoom", 3)), 2, 4)
	fullscreen = bool(d.get("fullscreen", false))
	vsync = bool(d.get("vsync", true))
	integer_scaling = bool(d.get("integer_scaling", false))
	# Умолчание берём из самого поля, а не из литерала: from_dict зовут на
	# свежем объекте, и второй список умолчаний рано или поздно разъедется
	# с первым.
	master_db = _db(d, "master_db", master_db)
	music_db = _db(d, "music_db", music_db)
	sfx_db = _db(d, "sfx_db", sfx_db)
	ui_db = _db(d, "ui_db", ui_db)
	ambient_db = _db(d, "ambient_db", ambient_db)
	haptics = bool(d.get("haptics", true))
	font_scale = clampf(float(d.get("font_scale", 1.0)), 0.75, 2.0)
	colorblind = int(d.get("colorblind", 0)) as Colorblind
	reduce_motion = bool(d.get("reduce_motion", false))
	high_contrast = bool(d.get("high_contrast", false))
	toast_seconds = maxf(float(d.get("toast_seconds", UITokens.TOAST_LIFE_SEC)), 0.0)
	screen_reader = bool(d.get("screen_reader", false))
	bindings = (d.get("bindings", {}) as Dictionary).duplicate(true)

func save_settings() -> void:
	SaveIO.write_json(PATH, to_dict())

## false — файла нет: это первый запуск, язык спросим у игрока.
func load_settings() -> bool:
	var d: Dictionary = SaveIO.read_json(PATH)
	if d.is_empty():
		locale = system_locale()
		return false
	if int(d.get("version", 0)) != VERSION:
		push_warning("настройки версии %d, ожидалась %d — берём умолчания"
			% [int(d.get("version", 0)), VERSION])
		locale = system_locale()
		return false
	from_dict(d)
	return true

func has_file() -> bool:
	return FileAccess.file_exists(PATH)

## Громкость из файла: зажата диапазоном ползунка настроек (docs/03 §3.6).
## Мусор в user://settings.json не должен оглушать игрока.
func _db(d: Dictionary, key: String, fallback: float) -> float:
	return clampf(float(d.get(key, fallback)), MUTE_DB, MAX_DB)
