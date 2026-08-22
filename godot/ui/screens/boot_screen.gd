class_name BootScreen
extends ScreenBase
## Заставка: логотип, полоса загрузки, версия сборки. Живёт доли секунды,
## но без неё первый кадр чёрный и игрок думает, что игра зависла (docs/03 §3.1).

signal finished(profile_ok: bool)

const MIN_SEC: float = 0.6

var _bar: ProgressBar = null
var _version: Label = null
var _t: float = 0.0
var _profile_ok: bool = true

func _ready() -> void:
	super()
	set_title("APP_NAME")
	show_back(false)
	var center: CenterContainer = CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(center)
	var box: VBoxContainer = VBoxContainer.new()
	center.add_child(box)
	var logo: Label = Label.new()
	logo.theme_type_variation = &"LabelTitle"
	logo.text = "APP_NAME"
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(logo)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(320.0, float(UITokens.SPACE_5))
	_bar.max_value = 1.0
	_bar.show_percentage = false
	box.add_child(_bar)
	_version = Label.new()
	_version.theme_type_variation = &"LabelSmall"
	_version.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_version.text = build_version()
	box.add_child(_version)

## Версия сборки: показывается на заставке, в меню и в настройках — одна
## строка на все три места.
static func build_version() -> String:
	var v: String = str(ProjectSettings.get_setting("application/config/version", ""))
	if v.is_empty():
		v = "dev"
	return "%s %s" % [v, Engine.get_version_info().get("string", "")]

func on_enter(_args: Dictionary = {}) -> void:
	_t = 0.0
	# ⚠️ set_process взводится обратно: после finished он выключен, и второй
	# вход в заставку висел бы на пустой полосе (аудит B5).
	set_process(true)
	# Профиль читает Meta в своём _ready; здесь только проверяем результат.
	_profile_ok = not FileAccess.file_exists(Meta.PROFILE_PATH) or Meta.load_profile()

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_bar.value = clampf(_t / MIN_SEC, 0.0, 1.0)
	if _t >= MIN_SEC:
		set_process(false)
		finished.emit(_profile_ok)
