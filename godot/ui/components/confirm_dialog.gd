class_name ConfirmDialog
extends Control
## Подтверждение: вопрос, строка последствий, две кнопки. Опасное действие —
## красной кнопкой и НИКОГДА не на фокусе по умолчанию (docs/03 §4.4).
## Для необратимого действия требуется ввод слова.

signal confirmed()
signal cancelled()

var _panel: PixelPanel = null
var _body: Label = null
var _word_edit: LineEdit = null
var _word_hint: Label = null
var _ok: PixelButton = null
var _cancel: PixelButton = null
var _body_key: String = ""
var _word: String = ""

func _ready() -> void:
	_build()

func _build() -> void:
	if _panel != null:
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Модальное окно блокирует ввод в мир — здесь STOP уместен (docs/03 §1).
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim: ColorRect = ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(UITokens.PAPER.r, UITokens.PAPER.g, UITokens.PAPER.b, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center: CenterContainer = CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PixelPanel.new()
	_panel.name = "Panel"
	_panel.custom_minimum_size = Vector2(420.0, 0.0)
	_panel.closed.connect(_on_cancel)
	center.add_child(_panel)
	_panel.setup("UI_CONFIRM_TITLE", true)

	_body = Label.new()
	_body.name = "Body"
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_content(_body)

	_word_hint = Label.new()
	_word_hint.name = "WordHint"
	_word_hint.theme_type_variation = &"LabelSmall"
	_word_hint.visible = false
	_panel.add_content(_word_hint)

	_word_edit = LineEdit.new()
	_word_edit.name = "Word"
	_word_edit.visible = false
	_word_edit.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_word_edit.text_changed.connect(_on_word_changed)
	_panel.add_content(_word_edit)

	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Buttons"
	_panel.add_content(row)
	_cancel = PixelButton.new()
	_cancel.name = "Cancel"
	_cancel.setup("UI_CANCEL", PixelButton.Variant.NORMAL)
	_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel.pressed.connect(_on_cancel)
	row.add_child(_cancel)
	_ok = PixelButton.new()
	_ok.name = "Ok"
	_ok.setup("UI_OK", PixelButton.Variant.PRIMARY)
	_ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ok.pressed.connect(_on_ok)
	row.add_child(_ok)

## require_word — уже переведённое слово подтверждения ("" = не требуется).
func setup(title_key: String, body_key: String, confirm_key: String,
		danger: bool, require_word: String = "") -> void:
	_build()
	_panel.setup(title_key, true)
	_body_key = body_key
	_word = require_word
	_ok.setup(confirm_key, PixelButton.Variant.DANGER if danger
		else PixelButton.Variant.PRIMARY)
	_word_edit.visible = not _word.is_empty()
	_word_hint.visible = not _word.is_empty()
	_word_edit.text = ""
	_ok.disabled = not _word.is_empty()
	_refresh_texts()

func open() -> void:
	visible = true
	grab_initial_focus()

func close() -> void:
	visible = false

## Опасная кнопка не получает фокус по умолчанию — уходит на «Отмену».
func grab_initial_focus() -> void:
	if _word_edit.visible:
		_word_edit.grab_focus()
		return
	_cancel.grab_focus()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh_texts()

func _refresh_texts() -> void:
	if _body == null:
		return
	_body.text = tr(_body_key)
	_word_hint.text = tr("UI_TYPE_WORD").format({"word": _word})

func _on_word_changed(text: String) -> void:
	_ok.disabled = text.strip_edges().to_upper() != _word.to_upper()

func _on_ok() -> void:
	close()
	confirmed.emit()

func _on_cancel() -> void:
	close()
	cancelled.emit()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_on_cancel()
		get_viewport().set_input_as_handled()
