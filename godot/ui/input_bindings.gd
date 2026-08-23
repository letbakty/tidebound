class_name InputBindings
extends RefCounted
## Привязки управления: формат хранения, слоты действия и человеческие подписи.
## ОДНО место на проект. Раньше формат жил в Settings строками as_text(), а
## подписи — константами в ButtonHints, и они разъезжались после первого же
## ремапа.
##
## ⚠️ ФОРМАТ ХРАНЕНИЯ — КОНТРАКТ. Он лежит в user://settings.json у игроков, и
## переделать его потом значит сбросить настройки всем сразу. Схема на событие:
##
##   {"type": "key",        "physical_keycode": int, "ctrl"/"shift"/"alt"/"meta": bool}
##   {"type": "pad_button", "button_index": int}
##   {"type": "pad_axis",   "axis": int, "axis_value": float}
##
## Хранится ТОЛЬКО то, что отличается от умолчаний проекта: полная карта в
## конфиге означала бы, что новое действие из патча игрок не получит вовсе.
## Неизвестный type и неизвестное действие читаются как «пропустить», а не как
## ошибка: файл переживает и патч, и правку руками.
##
## ⚠️ Строки as_text() тут не годятся в принципе: обратного разбора в движке
## нет (InputEventKey.from_text отсутствует), а сама строка нечитаема — кнопка
## B геймпада печатается как «Joypad Button 1 (Right Action, Sony Circle,
## Xbox B, Nintendo A)».
##
## physical_keycode, а не keycode: иначе WASD на кириллической раскладке
## отдаёт «цфыв» (research/10 §5).

const TYPE_KEY: String = "key"
const TYPE_PAD_BUTTON: String = "pad_button"
const TYPE_PAD_AXIS: String = "pad_axis"

## Устройство «любой геймпад». ⚠️ InputMap сравнивает device ТОЧНО, а умолчание
## у событий геймпада — 0: игрок со вторым контроллером, с рулём или просто
## переподключивший геймпад получал индекс 1, и игра переставала видеть геймпад
## целиком (godotengine/godot#105458).
##
## Клавиатуре и мыши −1 НЕ ставим: у них свои пространства устройств
## (DEVICE_ID_KEYBOARD = 16, DEVICE_ID_MOUSE = 32), а −1 там совпадает с
## DEVICE_ID_EMULATION — «эмулированное событие». Проект эмулирует тач из мыши,
## и эти два смысла сталкивать нельзя.
const PAD_DEVICE_ALL: int = -1

## Слоты действия: ремап раздельный по устройствам ввода (Game Accessibility
## Guidelines, Xbox Accessibility Guideline 107). Без слотов назначение
## клавиши стирало кнопку геймпада на том же действии.
enum Slot { KEY_1, KEY_2, PAD }
const SLOT_COUNT: int = 3
## Ключи подписей слотов для интерфейса.
const SLOT_KEYS: Array[String] = ["SET_SLOT_KEY_1", "SET_SLOT_KEY_2", "SET_SLOT_PAD"]

## Короткие имена кнопок геймпада. Своя таблица нужна потому, что as_text() у
## них длиной в шесть десятков символов и на кнопку настроек не влезает.
## Подписи кнопок и клавиш НЕ переводятся: это глифы на железе, а не текст.
const PAD_NAMES: Dictionary[int, String] = {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_BACK: "Select", JOY_BUTTON_START: "Start", JOY_BUTTON_GUIDE: "Guide",
	JOY_BUTTON_DPAD_UP: "D-pad ↑", JOY_BUTTON_DPAD_DOWN: "D-pad ↓",
	JOY_BUTTON_DPAD_LEFT: "D-pad ←", JOY_BUTTON_DPAD_RIGHT: "D-pad →",
}

## Оси: подписи только для показа, переназначать оси игрок не может.
const AXIS_NAMES: Dictionary[int, String] = {
	JOY_AXIS_LEFT_X: "L-stick X", JOY_AXIS_LEFT_Y: "L-stick Y",
	JOY_AXIS_RIGHT_X: "R-stick X", JOY_AXIS_RIGHT_Y: "R-stick Y",
	JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT",
}

## Подпись для пустого слота и для неизвестного события.
const EMPTY_LABEL: String = "—"

# --- Формат хранения ------------------------------------------------------

## Событие → словарь для settings.json. Пустой словарь — событие такого типа
## мы не храним (мышь, жесты: их ремапа нет).
static func to_dict(event: InputEvent) -> Dictionary:
	var key: InputEventKey = event as InputEventKey
	if key != null:
		# physical_keycode может быть нулём, если событие собрали по keycode —
		# тогда падаем на keycode, иначе привязка потеряется молча.
		var code: int = int(key.physical_keycode)
		if code == 0:
			code = int(key.keycode)
		return {
			"type": TYPE_KEY, "physical_keycode": code,
			"ctrl": key.ctrl_pressed, "shift": key.shift_pressed,
			"alt": key.alt_pressed, "meta": key.meta_pressed,
		}
	var btn: InputEventJoypadButton = event as InputEventJoypadButton
	if btn != null:
		return {"type": TYPE_PAD_BUTTON, "button_index": int(btn.button_index)}
	var axis: InputEventJoypadMotion = event as InputEventJoypadMotion
	if axis != null:
		return {"type": TYPE_PAD_AXIS, "axis": int(axis.axis),
			"axis_value": axis.axis_value}
	return {}

## Словарь → событие. null — тип неизвестен или запись битая: такую строку
## пропускаем молча, весь блок привязок из-за неё ронять нельзя.
static func from_dict(d: Dictionary) -> InputEvent:
	match str(d.get("type", "")):
		TYPE_KEY:
			var code: int = int(d.get("physical_keycode", 0))
			if code == 0:
				return null
			var key: InputEventKey = InputEventKey.new()
			key.physical_keycode = code as Key
			key.ctrl_pressed = bool(d.get("ctrl", false))
			key.shift_pressed = bool(d.get("shift", false))
			key.alt_pressed = bool(d.get("alt", false))
			key.meta_pressed = bool(d.get("meta", false))
			return key
		TYPE_PAD_BUTTON:
			var index: int = int(d.get("button_index", -1))
			if index < 0:
				return null
			var btn: InputEventJoypadButton = InputEventJoypadButton.new()
			btn.button_index = index as JoyButton
			btn.device = PAD_DEVICE_ALL
			return btn
		TYPE_PAD_AXIS:
			var axis_index: int = int(d.get("axis", -1))
			if axis_index < 0:
				return null
			var axis: InputEventJoypadMotion = InputEventJoypadMotion.new()
			axis.axis = axis_index as JoyAxis
			axis.axis_value = float(d.get("axis_value", 0.0))
			axis.device = PAD_DEVICE_ALL
			return axis
	return null

## Устойчивая подпись события для сравнения привязок между собой. as_text()
## для этого не годится: у геймпада он зависит от подключённого железа.
static func signature(event: InputEvent) -> String:
	var d: Dictionary = to_dict(event)
	if d.is_empty():
		return ""
	match str(d["type"]):
		TYPE_KEY:
			return "key:%d:%d%d%d%d" % [int(d["physical_keycode"]),
				int(bool(d["ctrl"])), int(bool(d["shift"])),
				int(bool(d["alt"])), int(bool(d["meta"]))]
		TYPE_PAD_BUTTON:
			return "pad:%d" % int(d["button_index"])
	return "axis:%d:%.1f" % [int(d["axis"]), float(d["axis_value"])]

# --- Слоты действия -------------------------------------------------------

## В какой слот ложится событие. −1 — ни в какой (мышь, жест, ось).
static func slot_of(event: InputEvent) -> int:
	if event is InputEventKey:
		return int(Slot.KEY_1)
	if event is InputEventJoypadButton:
		return int(Slot.PAD)
	return -1

## Три слота действия: две клавиши и кнопка геймпада. null — слот пуст.
## Порядок клавиш — тот же, что в InputMap: первая найденная в KEY_1.
static func slots(action: StringName) -> Array[InputEvent]:
	var out: Array[InputEvent] = [null, null, null]
	if not InputMap.has_action(action):
		return out
	for e: InputEvent in InputMap.action_get_events(action):
		if e is InputEventKey:
			if out[int(Slot.KEY_1)] == null:
				out[int(Slot.KEY_1)] = e
			elif out[int(Slot.KEY_2)] == null:
				out[int(Slot.KEY_2)] = e
		elif e is InputEventJoypadButton and out[int(Slot.PAD)] == null:
			out[int(Slot.PAD)] = e
	return out

## Всё, что в три слота не поместилось (оси стика, третья клавиша). При
## перезаписи действия это дописывается в конец: ремап одного слота не имеет
## права терять то, чего он не касался.
static func extras(action: StringName) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if not InputMap.has_action(action):
		return out
	var taken: Array[InputEvent] = slots(action)
	for e: InputEvent in InputMap.action_get_events(action):
		if not taken.has(e):
			out.append(e)
	return out

# --- Подписи --------------------------------------------------------------

## Короткая подпись события: Space, B, D-pad ←. Для клавиш —
## as_text_physical_keycode(): as_text() добавляет к ним « - Physical».
static func label(event: InputEvent) -> String:
	if event == null:
		return EMPTY_LABEL
	var key: InputEventKey = event as InputEventKey
	if key != null:
		var text: String = key.as_text_physical_keycode()
		return text if not text.is_empty() else EMPTY_LABEL
	var btn: InputEventJoypadButton = event as InputEventJoypadButton
	if btn != null:
		return PAD_NAMES.get(int(btn.button_index), "Pad %d" % int(btn.button_index))
	var axis: InputEventJoypadMotion = event as InputEventJoypadMotion
	if axis != null:
		var dir: String = "+" if axis.axis_value > 0.0 else "−"
		return "%s%s" % [AXIS_NAMES.get(int(axis.axis), "Axis %d" % int(axis.axis)), dir]
	return EMPTY_LABEL

## Подпись одного слота действия — для строки настроек.
static func slot_label(action: StringName, slot: int) -> String:
	if slot < 0 or slot >= SLOT_COUNT:
		return EMPTY_LABEL
	return label(slots(action)[slot])

## Подпись действия для полосы подсказок: кнопка геймпада или первая клавиша.
## Пустой слот — берём соседний, чтобы подсказка не показывала прочерк.
static func action_label(action: StringName, prefer_pad: bool) -> String:
	var s: Array[InputEvent] = slots(action)
	# Тернарник тут не годится: типизированный массив из него не выводится.
	var order: Array[int] = [int(Slot.KEY_1), int(Slot.KEY_2), int(Slot.PAD)]
	if prefer_pad:
		order = [int(Slot.PAD), int(Slot.KEY_1), int(Slot.KEY_2)]
	for i: int in order:
		if s[i] != null:
			return label(s[i])
	return EMPTY_LABEL
