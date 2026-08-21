class_name FirstLaunch
extends ScreenBase
## Первый запуск: язык и предложение настроить доступность (docs/03 §3.2).
##
## Отраслевой стандарт: доступность предлагается СРАЗУ, а не прячется в третьей
## вкладке настроек. И она никогда не отключает достижения.

signal done(open_accessibility: bool)

var _step: int = 0
var _lang_box: VBoxContainer = null
var _access_box: VBoxContainer = null

func _ready() -> void:
	super()
	set_title("FIRST_LANG_TITLE")
	show_back(false)
	_build_steps()

func _build_steps() -> void:
	_lang_box = VBoxContainer.new()
	_lang_box.name = "Lang"
	content.add_child(_lang_box)
	# Языки названы на самих себе: заголовок на чужом языке игрок не прочтёт.
	for pair: Array in [["ru", "Русский"], ["en", "English"]]:
		var b: PixelButton = PixelButton.new()
		b.setup(str(pair[1]), PixelButton.Variant.NORMAL)
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var code: String = str(pair[0])
		if code == Settings.system_locale():
			b.variant = PixelButton.Variant.PRIMARY   # подсказка по системе
			set_first_focus(b)
		b.pressed.connect(func() -> void: _pick_language(code))
		_lang_box.add_child(b)

	_access_box = VBoxContainer.new()
	_access_box.name = "Access"
	_access_box.visible = false
	content.add_child(_access_box)
	var text: Label = Label.new()
	UILayout.wrap(text, 520.0)
	text.text = "FIRST_ACCESS_TEXT"
	_access_box.add_child(text)
	var row: HBoxContainer = HBoxContainer.new()
	_access_box.add_child(row)
	var setup_btn: PixelButton = PixelButton.new()
	setup_btn.setup("FIRST_ACCESS_SETUP", PixelButton.Variant.PRIMARY)
	setup_btn.pressed.connect(func() -> void: done.emit(true))
	row.add_child(setup_btn)
	var skip: PixelButton = PixelButton.new()
	skip.setup("FIRST_ACCESS_SKIP", PixelButton.Variant.GHOST)
	skip.pressed.connect(func() -> void: done.emit(false))
	row.add_child(skip)

func on_enter(_args: Dictionary = {}) -> void:
	_step = 0
	_lang_box.visible = true
	_access_box.visible = false
	set_title("FIRST_LANG_TITLE")

func _pick_language(code: String) -> void:
	Settings.set_locale(code)
	Settings.apply()
	_step = 1
	_lang_box.visible = false
	_access_box.visible = true
	set_title("FIRST_ACCESS_TITLE")
