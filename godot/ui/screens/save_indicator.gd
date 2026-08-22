class_name SaveIndicator
extends Control
## Метка «сохранено» на границе цикла (docs/03 §6). Без неё игрок не знает,
## что прогресс цел, и боится закрывать игру.

const SHOW_SEC: float = 2.0

var _label: Label = null
var _timer: Timer = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	Events.cycle_ended.connect(_on_saved.unbind(1))

func _build() -> void:
	_label = Label.new()
	_label.theme_type_variation = &"LabelSmall"
	_label.text = "SAVE_DONE"
	_label.visible = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(func() -> void: _label.visible = false)
	add_child(_timer)

## Показываем ПРАВДУ: неудачная запись (диск полон, нет прав) с меткой
## «Сохранено» — худший вид молчаливого отказа (аудит B5).
func _on_saved() -> void:
	var ok: bool = Game.last_save_ok
	_label.text = "SAVE_DONE" if ok else "SAVE_FAILED"
	_label.add_theme_color_override("font_color",
		UITokens.MUTED if ok else UIPalette.danger())
	_label.visible = true
	_timer.start(SHOW_SEC)
