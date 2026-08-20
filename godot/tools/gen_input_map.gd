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
	print("input map written: %d actions" % ACTIONS.size())
	quit(0)
