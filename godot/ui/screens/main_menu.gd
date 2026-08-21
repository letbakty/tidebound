class_name MainMenu
extends ScreenBase
## Главное меню (docs/03 §3.3). Фон — статичная заглушка: живой мир под меню
## стоил бы кадров и рисковал падать до старта игры.

signal continue_requested()
signal new_run_requested(seed_value: int)
signal journal_requested()
signal settings_requested()
signal credits_requested()
signal quit_requested()

var _continue: PixelButton = null
var _continue_note: Label = null
var _journal: PixelButton = null
var _seed_edit: LineEdit = null
var _version: Label = null
var _confirm: ConfirmDialog = null

func _ready() -> void:
	super()
	set_title("APP_NAME")
	show_back(false)
	_build_menu()

func _build_menu() -> void:
	var subtitle: Label = Label.new()
	subtitle.theme_type_variation = &"LabelSmall"
	UILayout.wrap(subtitle, 520.0)
	subtitle.text = "MENU_SUBTITLE"
	content.add_child(subtitle)

	var box: VBoxContainer = VBoxContainer.new()
	box.name = "Buttons"
	box.custom_minimum_size = Vector2(320.0, 0.0)
	# Колонка меню держит свою ширину: растянутая на весь экран кнопка «Выход»
	# читается как полоса, а не как кнопка.
	box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	content.add_child(box)

	_continue = PixelButton.new()
	_continue.setup("MENU_CONTINUE", PixelButton.Variant.PRIMARY)
	_continue.pressed.connect(func() -> void: continue_requested.emit())
	box.add_child(_continue)
	_continue_note = Label.new()
	_continue_note.theme_type_variation = &"LabelSmall"
	_continue_note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	box.add_child(_continue_note)

	var seed_row: HBoxContainer = HBoxContainer.new()
	box.add_child(seed_row)
	var seed_label: Label = Label.new()
	seed_label.theme_type_variation = &"LabelSmall"
	seed_label.text = "MENU_SEED"
	seed_row.add_child(seed_label)
	_seed_edit = LineEdit.new()
	# placeholder_text движок не переводит сам — только через tr().
	_seed_edit.placeholder_text = tr("MENU_SEED_RANDOM")
	_seed_edit.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_edit.custom_minimum_size = Vector2(140.0, float(UITokens.TOUCH_MIN))
	seed_row.add_child(_seed_edit)

	var new_run: PixelButton = PixelButton.new()
	new_run.setup("MENU_NEW_RUN", PixelButton.Variant.NORMAL)
	new_run.pressed.connect(_on_new_run)
	box.add_child(new_run)
	set_first_focus(new_run)

	_journal = PixelButton.new()
	_journal.setup("MENU_JOURNAL", PixelButton.Variant.NORMAL)
	_journal.pressed.connect(func() -> void: journal_requested.emit())
	box.add_child(_journal)

	var settings: PixelButton = PixelButton.new()
	settings.setup("MENU_SETTINGS", PixelButton.Variant.NORMAL)
	settings.pressed.connect(func() -> void: settings_requested.emit())
	box.add_child(settings)

	var credits: PixelButton = PixelButton.new()
	credits.setup("MENU_CREDITS", PixelButton.Variant.GHOST)
	credits.pressed.connect(func() -> void: credits_requested.emit())
	box.add_child(credits)

	var quit: PixelButton = PixelButton.new()
	quit.setup("MENU_QUIT", PixelButton.Variant.GHOST)
	quit.pressed.connect(_on_quit)
	box.add_child(quit)

	_version = Label.new()
	_version.theme_type_variation = &"LabelSmall"
	_version.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_version.tooltip_text = "MENU_VERSION_TIP"
	_version.mouse_filter = Control.MOUSE_FILTER_STOP
	_version.text = BootScreen.build_version()
	_version.gui_input.connect(_on_version_input)
	content.add_child(_version)

	_confirm = ConfirmDialog.new()
	_confirm.name = "Confirm"
	add_child(_confirm)

func on_enter(_args: Dictionary = {}) -> void:
	_refresh()

## «Продолжить» видна только при валидном сейве (docs/03 §3.3).
func _refresh() -> void:
	var has: bool = Game.has_save()
	_continue.visible = has
	_continue_note.visible = has
	if has:
		var info: Dictionary = SaveService.saved_info()
		_continue_note.text = tr("MENU_CONTINUE_NOTE").format({
			"n": int(info.get("cycle", 1)), "total": Balance.CYCLES_PER_RUN})
	# Бейдж непотраченных очков — чтобы игрок не забыл про Журнал.
	var points: int = Meta.points_total
	_journal.text = tr("MENU_JOURNAL") if points <= 0 \
		else "%s  (%d)" % [tr("MENU_JOURNAL"), points]

func _on_new_run() -> void:
	var value: int = _seed_value()
	if not Game.has_save():
		new_run_requested.emit(value)
		return
	# Текущий забег будет потерян — спрашиваем (docs/03 §2).
	_confirm.setup("MENU_NEW_RUN", "MENU_OVERWRITE", "MENU_NEW_RUN", true, "")
	_reconnect(_confirm.confirmed, func() -> void: new_run_requested.emit(value))
	_confirm.open()

func _on_quit() -> void:
	_confirm.setup("MENU_QUIT", "MENU_QUIT_CONFIRM", "MENU_QUIT", true, "")
	_reconnect(_confirm.confirmed, func() -> void: quit_requested.emit())
	_confirm.open()

## Диалог один на всё меню: старую подписку снимаем, иначе «Выход» однажды
## запустит и новый забег.
func _reconnect(sig: Signal, target: Callable) -> void:
	for c: Dictionary in sig.get_connections():
		sig.disconnect(c["callable"] as Callable)
	sig.connect(target)

## Пусто = случайный сид; иначе число или хеш строки (docs/03 §3.3).
func _seed_value() -> int:
	var text: String = _seed_edit.text.strip_edges()
	if text.is_empty():
		return 0
	if text.is_valid_int():
		return absi(text.to_int())
	return absi(int(text.hash()))

func _on_version_input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null and not touch.pressed:
		DisplayServer.clipboard_set(_version.text)

func _refresh_texts() -> void:
	super()
	if _seed_edit != null:
		_seed_edit.placeholder_text = tr("MENU_SEED_RANDOM")
	if _continue != null:
		_refresh()
