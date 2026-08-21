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
var master_db: float = 0.0
var music_db: float = -6.0
var sfx_db: float = 0.0
var ui_db: float = 0.0
var ambient_db: float = -3.0
var haptics: bool = true

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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	# Локаль по системе — только если игрок ещё ничего не выбирал.
	apply()

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
	root.content_scale_factor = snappedf(ui_scale, UI_SCALE_STEP)
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
	mark_dirty()

## Шины появятся на этапе 17: до тех пор молча пропускаем.
func _apply_bus(bus_name: String, db: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, db)

## Язык по системной локали — предлагается на первом запуске (docs/03 §3.2).
static func system_locale() -> String:
	return "ru" if OS.get_locale().begins_with("ru") else "en"

func set_locale(value: String) -> void:
	locale = value
	TranslationServer.set_locale(value)
	mark_dirty()

# --- Файл -----------------------------------------------------------------

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
	master_db = float(d.get("master_db", 0.0))
	music_db = float(d.get("music_db", -6.0))
	sfx_db = float(d.get("sfx_db", 0.0))
	ui_db = float(d.get("ui_db", 0.0))
	ambient_db = float(d.get("ambient_db", -3.0))
	haptics = bool(d.get("haptics", true))
	font_scale = clampf(float(d.get("font_scale", 1.0)), 0.75, 2.0)
	colorblind = int(d.get("colorblind", 0)) as Colorblind
	reduce_motion = bool(d.get("reduce_motion", false))
	high_contrast = bool(d.get("high_contrast", false))
	toast_seconds = maxf(float(d.get("toast_seconds", UITokens.TOAST_LIFE_SEC)), 0.0)
	screen_reader = bool(d.get("screen_reader", false))

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
