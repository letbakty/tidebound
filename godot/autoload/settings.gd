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
## Закрепление схемы ввода. AUTO — как раньше: устройство определяется по
## последнему событию. Не-auto нужен на Steam Deck, где подключённая
## клавиатура заставляет подсказки прыгать между раскладками.
enum Scheme { AUTO, MOUSE, PAD, TOUCH }
## Пресеты раскладок (Game Accessibility Guidelines: профили ВМЕСТЕ с полной
## свободой). Пресет — тот же словарь оверрайдов, что и «своя» раскладка.
enum Preset { DEFAULT, ARROWS, ONE_HAND, CUSTOM }

## Множитель чувствительности камеры и виртуального курсора.
const CAM_SENS_MIN: float = 0.5
const CAM_SENS_MAX: float = 2.0
## Мёртвая зона стика. Верх намеренно большой: у изношенных контроллеров
## дрейф — самая частая жалоба на виртуальные курсоры.
const DEADZONE_MIN: float = 0.05
const DEADZONE_MAX: float = 0.5

## Тему надо пересобрать: сменились кегль, пресет для дальтоников или контраст.
## Пересборкой и раздачей по слоям занимается Main — Settings об узлах не знает.
signal theme_changed()
## Привязки управления изменились: полоса подсказок и вкладка настроек
## перестраивают подписи (research/32 §4.1).
signal bindings_changed()
## Игрок закрепил схему ввода или вернул «авто» — InputService перестаёт
## переключать устройство сам (docs/03 §3.6).
signal input_scheme_changed()

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
# --- Управление -----------------------------------------------------------
## Закреплённая схема ввода; AUTO — определять по последнему событию.
var input_scheme: Scheme = Scheme.AUTO
## Один множитель на панораму с клавиш, панораму драгом и виртуальный курсор:
## три разные скорости под одним ползунком игрок всё равно воспринимает как
## «быстрее/медленнее» (docs/03 §3.6).
var camera_sensitivity: float = 1.0
var stick_deadzone: float = 0.2

# --- Звук (продолжение) ---------------------------------------------------
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
	# ⚠️ Порядок обязателен. capture_defaults() снимает раскладку ПРОЕКТА и
	# обязана отработать до того, как файл наложит оверрайды: иначе «сбросить к
	# умолчаниям» вернёт не умолчания, а прошлый ремап. Раньше этот вызов жил в
	# game/main.gd — то есть уже после Settings._ready.
	capture_defaults()
	if not load_settings():
		# Файла нет — первый запуск: подбираем умолчания по железу.
		_apply_platform_defaults()
	# ⚠️ Без этого вызова сохранённый ремап не применялся НИКОГДА: файл читался
	# в поле bindings, и на этом всё — InputMap никто не трогал.
	apply_bindings()
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

## Действие -> массив описаний событий (схема — ui/input_bindings.gd).
## Пусто = раскладка проекта. Храним ТОЛЬКО отличия от умолчаний: полная карта
## в конфиге означала бы, что действие, добавленное патчем, игрок не получит.
var bindings: Dictionary = {}

## Список действий, которые игрок может переназначить. Служебные (ui_*, дебаг,
## режим съёмки) сюда не входят: их ремап ломает навигацию геймпадом, а это
## прямой отказ в Steam Deck Verified.
const REMAPPABLE: Array[String] = ["pan_left", "pan_right", "pan_up", "pan_down",
	"recall", "policies", "build_radial", "beacon",
	"speed_1", "speed_2", "speed_3", "pause_menu",
	"overlay_marks", "overlay_flood", "overlay_jobs", "cursor_tap"]

## Переназначать нельзя, но в проверке конфликтов они участвуют: иначе повесить
## действие на F1 или на «принять» в меню можно молча (и остаться без меню).
const RESERVED: Array[String] = ["debug_panel", "capture_toggle", "capture_layers",
	"ui_accept", "ui_cancel", "ui_left", "ui_right", "ui_up", "ui_down"]

## Раскладки-пресеты: только клавиши, геймпад они не трогают. Значение —
## действие -> клавиши по слотам (physical_keycode).
##
## РЕШЕНИЕ: сами раскладки придуманы здесь, в docs их нет. «Стрелки» — панорама
## на стрелках, действия под левой рукой; «одна рука» — всё под левой ладонью,
## чтобы правая была свободна (мышь, костыль, что угодно).
const PRESETS: Dictionary[int, Dictionary] = {
	int(Preset.ARROWS): {
		"pan_left": [KEY_LEFT], "pan_right": [KEY_RIGHT],
		"pan_up": [KEY_UP], "pan_down": [KEY_DOWN],
		"policies": [KEY_A], "build_radial": [KEY_S], "beacon": [KEY_D],
	},
	int(Preset.ONE_HAND): {
		"recall": [KEY_Q], "policies": [KEY_E], "build_radial": [KEY_R],
		"beacon": [KEY_F],
	},
}

## Умолчания снимаем ОДИН раз при первом обращении: после ремапа InputMap уже
## изменён, и «сбросить» стало бы нечем. Служебные действия сюда тоже попадают —
## по ним считается «штатное» пересечение клавиш (см. conflicts).
static var _defaults: Dictionary[String, Array] = {}

static func capture_defaults() -> void:
	if not _defaults.is_empty():
		return
	for action: String in REMAPPABLE + RESERVED:
		if not InputMap.has_action(action):
			continue
		var events: Array[InputEvent] = []
		for e: InputEvent in InputMap.action_get_events(action):
			events.append(e)
		_defaults[action] = events

## Раскладка по умолчанию для действия — нужна ремапу и проверке конфликтов.
static func default_events(action: String) -> Array:
	capture_defaults()
	return _defaults.get(action, [] as Array)

# --- Применение -----------------------------------------------------------

## Кладёт сохранённые оверрайды в InputMap. Идемпотентна: сначала откат к
## умолчаниям, потом наложение — иначе повторный вызов копил бы события.
func apply_bindings() -> void:
	capture_defaults()
	_restore_defaults()
	for action: Variant in bindings:
		var name: String = str(action)
		if not InputMap.has_action(name):
			continue                     # действие исчезло в новой версии игры
		var events: Array[InputEvent] = _events_from_store(bindings[action])
		if events.is_empty():
			continue                     # действие без ввода недостижимо — не применяем
		InputMap.action_erase_events(name)
		for e: InputEvent in events:
			InputMap.action_add_event(name, e)
	bindings_changed.emit()

## Разбор хранимого списка. Битая запись и неизвестный type пропускаются молча:
## один испорченный ключ не имеет права уронить весь блок привязок.
func _events_from_store(raw: Variant) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for item: Variant in raw as Array:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var e: InputEvent = InputBindings.from_dict(item as Dictionary)
		if e != null:
			out.append(e)
	return out

func _restore_defaults() -> void:
	for action: String in REMAPPABLE:
		if not _defaults.has(action) or not InputMap.has_action(action):
			continue
		InputMap.action_erase_events(action)
		for e: InputEvent in _defaults[action]:
			InputMap.action_add_event(action, e)

# --- Ремап ----------------------------------------------------------------

## Пишет событие в конкретный слот действия (клавиша 1, клавиша 2, геймпад).
## false — не записали: тип события не для этого слота, действие неизвестно
## или результат оставил бы действие вовсе без ввода.
##
## ⚠️ Именно слоты, а не «одно действие — одна кнопка»: раньше ремап делал
## action_erase_events() и добавлял одно событие, то есть назначение клавиши
## стирало кнопку геймпада на том же действии, а у панорамы — вторую клавишу.
## Раздельный ремап по устройствам ввода — требование Game Accessibility
## Guidelines и Xbox Accessibility Guideline 107.
func set_slot(action: String, slot: int, event: InputEvent) -> bool:
	if not InputMap.has_action(action) or not REMAPPABLE.has(action):
		return false
	if InputBindings.slot_of(event) != slot:
		return false
	capture_defaults()
	var list: Array[InputEvent] = InputBindings.slots(action)
	list[slot] = event
	return _write_action(action, list)

## Совместимая обёртка: слот выбирается по типу события.
func rebind(action: String, event: InputEvent) -> bool:
	return set_slot(action, InputBindings.slot_of(event), event)

func _write_action(action: String, list: Array[InputEvent]) -> bool:
	var events: Array[InputEvent] = []
	for e: InputEvent in list:
		if e != null:
			events.append(e)
	# Оси стика и прочее, чего слоты не касались, обязаны пережить ремап.
	events.append_array(InputBindings.extras(action))
	if events.is_empty():
		return false                     # действие без ввода = игрок себя запер
	InputMap.action_erase_events(action)
	for e: InputEvent in events:
		InputMap.action_add_event(action, e)
	_remember(action, events)
	bindings_changed.emit()
	mark_dirty()
	return true

## В файл идут только отличия от умолчаний: раскладка, совпавшая с проектной,
## из bindings вычёркивается целиком.
func _remember(action: String, events: Array[InputEvent]) -> void:
	if _same_events(events, default_events(action)):
		bindings.erase(action)
		return
	var out: Array = []
	for e: InputEvent in events:
		var d: Dictionary = InputBindings.to_dict(e)
		if not d.is_empty():
			out.append(d)
	bindings[action] = out

static func _same_events(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i: int in a.size():
		if InputBindings.signature(a[i] as InputEvent) \
				!= InputBindings.signature(b[i] as InputEvent):
			return false
	return true

## Сброс ОДНОЙ строки: раньше единственная кнопка сбрасывала весь список.
func reset_action(action: String) -> void:
	capture_defaults()
	if not InputMap.has_action(action) or not _defaults.has(action):
		return
	InputMap.action_erase_events(action)
	for e: InputEvent in _defaults[action]:
		InputMap.action_add_event(action, e)
	bindings.erase(action)
	bindings_changed.emit()
	mark_dirty()

func reset_bindings() -> void:
	capture_defaults()
	_restore_defaults()
	bindings.clear()
	bindings_changed.emit()
	mark_dirty()

# --- Пресеты --------------------------------------------------------------

## Применяет пресет: сначала откат к умолчаниям, потом клавиши пресета.
## Геймпад пресеты не трогают — он и так у всех одинаковый.
func apply_preset(preset: int) -> void:
	reset_bindings()
	if not PRESETS.has(preset):
		return                           # Preset.DEFAULT — это и есть откат
	var map: Dictionary = PRESETS[preset]
	for action: Variant in map:
		var name: String = str(action)
		if not InputMap.has_action(name):
			continue
		var list: Array[InputEvent] = InputBindings.slots(name)
		# Клавиатурные слоты пресет задаёт целиком: иначе от прежней раскладки
		# осталась бы вторая клавиша, и «стрелки» ездили бы ещё и на WASD.
		list[int(InputBindings.Slot.KEY_1)] = null
		list[int(InputBindings.Slot.KEY_2)] = null
		var keys: Array = map[action] as Array
		for i: int in mini(keys.size(), 2):
			var e: InputEventKey = InputEventKey.new()
			e.physical_keycode = int(keys[i]) as Key
			list[i] = e
		_write_action(name, list)

## Какой пресет сейчас на экране. CUSTOM — игрок правил строки сам.
func current_preset() -> int:
	if bindings.is_empty():
		return int(Preset.DEFAULT)
	for preset: int in PRESETS:
		if _matches_preset(preset):
			return preset
	return int(Preset.CUSTOM)

func _matches_preset(preset: int) -> bool:
	var map: Dictionary = PRESETS[preset]
	if bindings.size() != map.size():
		return false
	for action: Variant in map:
		if not bindings.has(action):
			return false
		var want: Array[InputEvent] = []
		var keys: Array = map[action] as Array
		for i: int in mini(keys.size(), 2):
			var e: InputEventKey = InputEventKey.new()
			e.physical_keycode = int(keys[i]) as Key
			want.append(e)
		var pad: InputEvent = InputBindings.slots(str(action))[int(InputBindings.Slot.PAD)]
		if pad != null:
			want.append(pad)
		want.append_array(InputBindings.extras(str(action)))
		if not _same_events(_events_from_store(bindings[action]), want):
			return false
	return true

# --- Конфликты ------------------------------------------------------------

## Одна и та же кнопка на двух действиях. Возвращает набор действий, которые
## панель подсветит красным.
##
## ⚠️ Конфликтом считается пересечение, которого НЕТ в раскладке по умолчанию.
## Штатных пересечений два: Space стоит и на «Отзыве», и на ui_accept, а Esc —
## и на паузе, и на ui_cancel. Без этой поправки вкладка краснела бы на чистой
## установке.
##
## Считаем против ВСЕХ действий, включая служебные: раньше обход шёл только по
## REMAPPABLE, и повесить действие на F1 или на «принять» можно было молча.
func conflicts() -> Dictionary:
	capture_defaults()
	var now: Dictionary = _by_signature(false)
	var base: Dictionary = _by_signature(true)
	var bad: Dictionary = {}
	for sig: Variant in now:
		var actions: Array = now[sig] as Array
		if actions.size() < 2:
			continue
		var was: Array = (base.get(sig, [] as Array) as Array).duplicate()
		actions.sort()
		was.sort()
		if actions == was:
			continue                     # так было и в умолчаниях — это штатно
		for action: Variant in actions:
			bad[str(action)] = true
	return bad

## Подпись события -> список действий. from_defaults=true — из снятой раскладки
## проекта, иначе из текущего InputMap.
func _by_signature(from_defaults: bool) -> Dictionary:
	var out: Dictionary = {}
	for action: String in REMAPPABLE + RESERVED:
		if not InputMap.has_action(action):
			continue
		var events: Array = default_events(action) if from_defaults \
			else InputMap.action_get_events(action)
		for e: InputEvent in events:
			var sig: String = InputBindings.signature(e)
			if sig.is_empty():
				continue
			if not out.has(sig):
				out[sig] = [] as Array
			(out[sig] as Array).append(action)
	return out

## Занята ли кнопка служебным действием, которое переназначать нельзя. Своё
## умолчание вернуть можно всегда — иначе «Отзыв» нельзя было бы вернуть на
## Space (его же держит ui_accept), а паузу — на Esc.
func is_reserved_event(action: String, event: InputEvent) -> bool:
	capture_defaults()
	var sig: String = InputBindings.signature(event)
	if sig.is_empty():
		return false
	for own: InputEvent in default_events(action):
		if InputBindings.signature(own) == sig:
			return false
	for other: String in RESERVED:
		if not InputMap.has_action(other):
			continue
		for e: InputEvent in InputMap.action_get_events(other):
			if InputBindings.signature(e) == sig:
				return true
	return false

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
		"input_scheme": int(input_scheme),
		"camera_sensitivity": camera_sensitivity, "stick_deadzone": stick_deadzone,
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
	# ⚠️ Новые поля читаются через d.get(умолчание) и версии НЕ требуют:
	# load_settings при несовпадении версии выбрасывает файл целиком, то есть
	# поднять VERSION значит сбросить всем и звук, и язык, и доступность.
	input_scheme = clampi(int(d.get("input_scheme", 0)), 0, int(Scheme.TOUCH)) as Scheme
	camera_sensitivity = clampf(float(d.get("camera_sensitivity", 1.0)),
		CAM_SENS_MIN, CAM_SENS_MAX)
	stick_deadzone = clampf(float(d.get("stick_deadzone", 0.2)),
		DEADZONE_MIN, DEADZONE_MAX)
	font_scale = clampf(float(d.get("font_scale", 1.0)), 0.75, 2.0)
	colorblind = int(d.get("colorblind", 0)) as Colorblind
	reduce_motion = bool(d.get("reduce_motion", false))
	high_contrast = bool(d.get("high_contrast", false))
	toast_seconds = maxf(float(d.get("toast_seconds", UITokens.TOAST_LIFE_SEC)), 0.0)
	screen_reader = bool(d.get("screen_reader", false))
	bindings = (d.get("bindings", {}) as Dictionary).duplicate(true)

## Закрепление схемы: не-auto запрещает InputService переключать устройство
## по последнему событию (docs/03 §3.6).
func set_input_scheme(value: int) -> void:
	input_scheme = clampi(value, 0, int(Scheme.TOUCH)) as Scheme
	input_scheme_changed.emit()
	mark_dirty()

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
