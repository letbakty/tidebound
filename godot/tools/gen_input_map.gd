extends SceneTree
## Генератор Input Map (этап 00). Запуск:
##   godot --headless -s res://tools/gen_input_map.gd
## Идемпотентен: повторный прогон перезаписывает действия.
##
## physical_keycode, а не keycode: иначе WASD не работает на кириллической
## раскладке — клавиша "W" отдаёт "ц". См. research/10 §5.

const ACTIONS: Dictionary = {
	"pan_left":      [KEY_A, KEY_LEFT],
	"pan_right":     [KEY_D, KEY_RIGHT],
	"pan_up":        [KEY_W, KEY_UP],
	"pan_down":      [KEY_S, KEY_DOWN],
	"recall":        [KEY_SPACE],
	"policies":      [KEY_P],
	"build_radial":  [KEY_B],
	"beacon":        [KEY_M],
	"speed_1":       [KEY_1],
	"speed_2":       [KEY_2],
	"speed_3":       [KEY_3],
	"pause_menu":    [KEY_ESCAPE],
	"debug_panel":   [KEY_F1],
	"overlay_marks": [KEY_F2],
	"overlay_flood": [KEY_F3],
	"overlay_jobs":  [KEY_F4],
}

## Оси стика как ДЕЙСТВИЯ: Input.get_vector без них не работает, и виртуальный
## курсор геймпада стоял бы на месте (research/20 §6).
const PAD_AXES: Dictionary = {
	"cursor_left":  [JOY_AXIS_RIGHT_X, -1.0],
	"cursor_right": [JOY_AXIS_RIGHT_X, 1.0],
	"cursor_up":    [JOY_AXIS_RIGHT_Y, -1.0],
	"cursor_down":  [JOY_AXIS_RIGHT_Y, 1.0],
	"zoom_in":      [JOY_AXIS_TRIGGER_RIGHT, 1.0],
	"zoom_out":     [JOY_AXIS_TRIGGER_LEFT, 1.0],
}

## Тап курсором геймпада: A. Отдельным действием, чтобы не путать с ui_accept,
## который ходит по кнопкам интерфейса.
const PAD_TAP: Array[int] = [JOY_BUTTON_A]

const PADS: Dictionary = {
	"recall":       [JOY_BUTTON_B],
	"build_radial": [JOY_BUTTON_Y],
	"policies":     [JOY_BUTTON_LEFT_SHOULDER],
	"beacon":       [JOY_BUTTON_X],
	"pause_menu":   [JOY_BUTTON_START],
	"speed_1":      [JOY_BUTTON_DPAD_LEFT],
	"speed_2":      [JOY_BUTTON_DPAD_UP],
	"speed_3":      [JOY_BUTTON_DPAD_RIGHT],
}

func _initialize() -> void:
	for axis_action: String in PAD_AXES:
		var axis_events: Array[InputEvent] = []
		var pair: Array = PAD_AXES[axis_action] as Array
		var m := InputEventJoypadMotion.new()
		m.axis = int(pair[0]) as JoyAxis
		m.axis_value = float(pair[1])
		axis_events.append(m)
		ProjectSettings.set_setting("input/" + axis_action,
			{"deadzone": 0.25, "events": axis_events})
	var tap_events: Array[InputEvent] = []
	for tap_btn: int in PAD_TAP:
		var tap := InputEventJoypadButton.new()
		tap.button_index = tap_btn
		tap_events.append(tap)
	ProjectSettings.set_setting("input/cursor_tap",
		{"deadzone": 0.5, "events": tap_events})
	for action: String in ACTIONS:
		var events: Array[InputEvent] = []
		for key: int in ACTIONS[action]:
			var e := InputEventKey.new()
			e.physical_keycode = key
			events.append(e)
		for btn: int in PADS.get(action, [] as Array):
			var j := InputEventJoypadButton.new()
			j.button_index = btn
			events.append(j)
		ProjectSettings.set_setting("input/" + action, {"deadzone": 0.5, "events": events})
	var err: int = ProjectSettings.save()
	if err != OK:
		push_error("ProjectSettings.save() failed: %d" % err)
		quit(1)
		return
	print("input map written: %d actions" % (ACTIONS.size() + PAD_AXES.size() + 1))
	quit(0)
