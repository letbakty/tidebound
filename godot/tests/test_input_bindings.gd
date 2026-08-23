extends RefCounted
## Ремап управления: формат хранения, слоты, конфликты, геймпады.
##
## ⚠️ Формат хранения — КОНТРАКТ: он лежит в user://settings.json у игроков, и
## смена схемы означает сброс настроек у всех сразу. Круг «событие → словарь →
## событие» тут не формальность, а защита этого контракта.
##
## Сьют трогает ГЛОБАЛЬНЫЙ InputMap, поэтому каждый тест возвращает раскладку
## на место через reset_bindings(): иначе он ломал бы соседние сьюты.

const SETTINGS_SCRIPT: String = "res://autoload/settings.gd"

static func _settings() -> Node:
	var s: Node = (load(SETTINGS_SCRIPT) as GDScript).new()
	s.call("capture_defaults")
	return s

static func _key(code: int, ctrl: bool = false, shift: bool = false) -> InputEventKey:
	var e: InputEventKey = InputEventKey.new()
	e.physical_keycode = code as Key
	e.ctrl_pressed = ctrl
	e.shift_pressed = shift
	return e

static func _pad(index: int) -> InputEventJoypadButton:
	var e: InputEventJoypadButton = InputEventJoypadButton.new()
	e.button_index = index as JoyButton
	e.device = InputBindings.PAD_DEVICE_ALL
	return e

# --- Формат ---------------------------------------------------------------

## Круг «событие → словарь → событие» для всех трёх типов. Обратного разбора
## строк as_text() в движке нет вовсе — поэтому храним структуру.
static func test_round_trip_all_types(t: TestCtx) -> void:
	var key: InputEventKey = _key(KEY_R, true, true)
	var back_key: InputEventKey = InputBindings.from_dict(
		InputBindings.to_dict(key)) as InputEventKey
	t.check(back_key != null, "клавиша разобралась обратно")
	t.check_eq(int(back_key.physical_keycode), int(KEY_R), "код клавиши сохранился")
	t.check(back_key.ctrl_pressed and back_key.shift_pressed,
		"модификаторы сохранились")
	t.check_eq(InputBindings.signature(key), InputBindings.signature(back_key),
		"подпись до и после круга совпала")

	var pad: InputEventJoypadButton = _pad(JOY_BUTTON_B)
	var back_pad: InputEventJoypadButton = InputBindings.from_dict(
		InputBindings.to_dict(pad)) as InputEventJoypadButton
	t.check(back_pad != null, "кнопка геймпада разобралась обратно")
	t.check_eq(int(back_pad.button_index), int(JOY_BUTTON_B), "индекс кнопки сохранился")
	t.check_eq(back_pad.device, InputBindings.PAD_DEVICE_ALL,
		"кнопка приходит с device −1: иначе её увидит только геймпад №0")

	var axis: InputEventJoypadMotion = InputEventJoypadMotion.new()
	axis.axis = JOY_AXIS_RIGHT_X
	axis.axis_value = -1.0
	var back_axis: InputEventJoypadMotion = InputBindings.from_dict(
		InputBindings.to_dict(axis)) as InputEventJoypadMotion
	t.check(back_axis != null, "ось разобралась обратно")
	t.check_eq(int(back_axis.axis), int(JOY_AXIS_RIGHT_X), "номер оси сохранился")
	t.check_approx(back_axis.axis_value, -1.0, 0.001, "направление оси сохранилось")

## Мусор в файле пропускается молча: один битый ключ не имеет права уронить
## весь блок привязок или весь файл настроек.
static func test_garbage_is_skipped(t: TestCtx) -> void:
	t.check(InputBindings.from_dict({}) == null, "пустой словарь — не событие")
	t.check(InputBindings.from_dict({"type": "хз"}) == null, "неизвестный type пропущен")
	t.check(InputBindings.from_dict({"type": "key"}) == null, "клавиша без кода пропущена")
	t.check(InputBindings.from_dict({"type": "pad_button"}) == null,
		"кнопка без индекса пропущена")

	var s: Node = _settings()
	s.set("bindings", {
		"нет_такого_действия": [{"type": "key", "physical_keycode": KEY_R}],
		"recall": [{"type": "хз"}, {"type": "key", "physical_keycode": KEY_R}],
	})
	s.call("apply_bindings")
	t.check(InputMap.event_is_action(_key(KEY_R), "recall"),
		"понятная строка применилась, несмотря на соседний мусор")
	s.call("reset_bindings")
	s.free()

# --- Слоты ----------------------------------------------------------------

## Главный дефект ремапа: назначение клавиши стирало кнопку геймпада на том же
## действии, а у панорамы — вторую клавишу.
static func test_key_remap_keeps_pad(t: TestCtx) -> void:
	var s: Node = _settings()
	t.check(InputMap.event_is_action(_pad(JOY_BUTTON_B), "recall"),
		"в умолчаниях «Отзыв» висит и на кнопке B")
	t.check(s.call("set_slot", "recall", int(InputBindings.Slot.KEY_1), _key(KEY_R)),
		"клавиша записалась в первый слот")
	t.check(InputMap.event_is_action(_key(KEY_R), "recall"), "R отзывает людей")
	t.check(InputMap.event_is_action(_pad(JOY_BUTTON_B), "recall"),
		"кнопка геймпада на том же действии ЖИВА")
	t.check(not InputMap.event_is_action(_key(KEY_SPACE), "recall"),
		"старая клавиша заменена, а не добавлена")

	# Вторая клавиша панорамы — тот же случай.
	t.check(s.call("set_slot", "pan_left", int(InputBindings.Slot.KEY_1), _key(KEY_J)),
		"панорама влево переехала на J")
	t.check(InputMap.event_is_action(_key(KEY_LEFT), "pan_left"),
		"запасная стрелка у панорамы жива")
	s.call("reset_bindings")
	t.check(InputMap.event_is_action(_key(KEY_SPACE), "recall"),
		"сброс вернул умолчание")
	s.free()

## Слот принимает только своё устройство: кнопка геймпада не должна попадать
## в клавиатурный слот и наоборот.
static func test_slot_takes_only_its_device(t: TestCtx) -> void:
	var s: Node = _settings()
	t.check(not s.call("set_slot", "recall", int(InputBindings.Slot.KEY_1),
		_pad(JOY_BUTTON_X)), "кнопка геймпада в клавиатурный слот не идёт")
	t.check(not s.call("set_slot", "recall", int(InputBindings.Slot.PAD),
		_key(KEY_R)), "клавиша в слот геймпада не идёт")
	t.check(s.call("set_slot", "recall", int(InputBindings.Slot.PAD),
		_pad(JOY_BUTTON_X)), "своя кнопка в свой слот записалась")
	t.check(InputMap.event_is_action(_key(KEY_SPACE), "recall"),
		"клавиша при ремапе геймпада не пострадала")
	s.call("reset_bindings")
	s.free()

# --- Сохранение -----------------------------------------------------------

## to_dict → from_dict → apply_bindings возвращает ровно то, что назначили:
## именно этого не происходило никогда — файл читался, InputMap не трогали.
static func test_saved_bindings_survive_restart(t: TestCtx) -> void:
	var s: Node = _settings()
	s.call("set_slot", "recall", int(InputBindings.Slot.KEY_1), _key(KEY_R))
	var saved: Dictionary = s.call("to_dict")
	s.call("reset_bindings")
	t.check(InputMap.event_is_action(_key(KEY_SPACE), "recall"),
		"перед «перезапуском» раскладка сброшена")

	# Второй объект = свежий запуск игры: читает файл и применяет его.
	var fresh: Node = (load(SETTINGS_SCRIPT) as GDScript).new()
	fresh.call("from_dict", saved)
	fresh.call("apply_bindings")
	t.check(InputMap.event_is_action(_key(KEY_R), "recall"),
		"после перезапуска R по-прежнему отзывает людей")
	t.check(InputMap.event_is_action(_pad(JOY_BUTTON_B), "recall"),
		"и кнопка геймпада на месте")
	# Повторный вызов идемпотентен: события не копятся.
	fresh.call("apply_bindings")
	t.check_eq(InputMap.action_get_events("recall").size(), 2,
		"повторное применение не размножает события")
	fresh.call("reset_bindings")
	fresh.free()
	s.free()

## Храним ТОЛЬКО отличия от умолчаний: полная карта в конфиге означала бы, что
## действие, добавленное патчем, игрок не получит вовсе.
static func test_only_overrides_are_stored(t: TestCtx) -> void:
	var s: Node = _settings()
	t.check((s.get("bindings") as Dictionary).is_empty(),
		"на чистых настройках оверрайдов нет")
	s.call("set_slot", "recall", int(InputBindings.Slot.KEY_1), _key(KEY_R))
	t.check_eq((s.get("bindings") as Dictionary).size(), 1,
		"записалось ровно одно действие")
	s.call("set_slot", "recall", int(InputBindings.Slot.KEY_1), _key(KEY_SPACE))
	t.check((s.get("bindings") as Dictionary).is_empty(),
		"возврат к умолчанию вычёркивает действие из файла")
	s.call("reset_bindings")
	s.free()

# --- Геймпады -------------------------------------------------------------

## device = −1 — «любой геймпад». С умолчанием 0 игрок со вторым контроллером
## или просто переподключивший геймпад терял управление целиком.
static func test_any_gamepad_index_works(t: TestCtx) -> void:
	for device: int in [0, 1, 2, 7]:
		var e: InputEventJoypadButton = InputEventJoypadButton.new()
		e.button_index = JOY_BUTTON_B
		e.device = device
		t.check(InputMap.event_is_action(e, "recall"),
			"кнопка B геймпада №%d отзывает людей" % device)
	var axis: InputEventJoypadMotion = InputEventJoypadMotion.new()
	axis.axis = JOY_AXIS_RIGHT_X
	axis.axis_value = 1.0
	axis.device = 3
	t.check(InputMap.event_is_action(axis, "cursor_right"),
		"ось стика тоже слушает любой геймпад")

## Ремап геймпада хранится и применяется наравне с клавиатурой: Steam Input
## закрывает только Steam-сборки, а у проекта в планах itch, веб и телефон.
static func test_pad_remap_survives_restart(t: TestCtx) -> void:
	var s: Node = _settings()
	s.call("set_slot", "recall", int(InputBindings.Slot.PAD), _pad(JOY_BUTTON_X))
	var saved: Dictionary = s.call("to_dict")
	s.call("reset_bindings")
	var fresh: Node = (load(SETTINGS_SCRIPT) as GDScript).new()
	fresh.call("from_dict", saved)
	fresh.call("apply_bindings")
	var other_pad: InputEventJoypadButton = InputEventJoypadButton.new()
	other_pad.button_index = JOY_BUTTON_X
	other_pad.device = 2
	t.check(InputMap.event_is_action(other_pad, "recall"),
		"переназначенная кнопка работает на любом геймпаде")
	fresh.call("reset_bindings")
	fresh.free()
	s.free()

# --- Конфликты ------------------------------------------------------------

## Конфликт считается против ВСЕХ действий, включая служебные: раньше обход шёл
## только по переназначаемым, и повесить действие на F1 можно было молча.
static func test_conflicts_cover_reserved_actions(t: TestCtx) -> void:
	var s: Node = _settings()
	t.check_eq((s.call("conflicts") as Dictionary).size(), 0,
		"в раскладке по умолчанию конфликтов нет")
	s.call("set_slot", "recall", int(InputBindings.Slot.KEY_1), _key(KEY_F1))
	var bad: Dictionary = s.call("conflicts")
	t.check(bad.has("recall"), "F1 занят дебаг-панелью — строка краснеет")
	s.call("reset_bindings")

	s.call("set_slot", "recall", int(InputBindings.Slot.KEY_1), _key(KEY_P))
	bad = s.call("conflicts")
	t.check(bad.has("recall") and bad.has("policies"),
		"конфликт двух игровых действий подсвечивает ОБА")
	s.call("reset_bindings")
	t.check_eq((s.call("conflicts") as Dictionary).size(), 0,
		"сброс убирает конфликт")
	s.free()

## Штатные пересечения не краснеют: Space стоит и на «Отзыве», и на ui_accept,
## Esc — и на паузе, и на ui_cancel. Без этой поправки вкладка была бы красной
## на чистой установке.
static func test_default_overlaps_are_not_conflicts(t: TestCtx) -> void:
	var s: Node = _settings()
	# ⚠️ event_is_action тут не годится: у встроенных ui_* события собраны по
	# keycode, а у наших — по physical_keycode, и движок сравнивает их
	# раздельно. Наша подпись оба случая приводит к одному виду — именно
	# поэтому пересечение видно в conflicts().
	var space: String = InputBindings.signature(_key(KEY_SPACE))
	var shared: bool = false
	for e: InputEvent in InputMap.action_get_events("ui_accept"):
		shared = shared or InputBindings.signature(e) == space
	t.check(shared, "Space действительно занят и интерфейсом (ui_accept)")
	t.check_eq((s.call("conflicts") as Dictionary).size(), 0,
		"и всё же конфликтом это не считается")
	s.free()

## Служебную кнопку занять нельзя — иначе игрок запирает себя без выхода в
## меню. Своё умолчание вернуть можно всегда.
static func test_reserved_keys_are_protected(t: TestCtx) -> void:
	var s: Node = _settings()
	t.check(s.call("is_reserved_event", "recall", _key(KEY_ESCAPE)),
		"Esc занят выходом из меню")
	t.check(s.call("is_reserved_event", "recall", _key(KEY_F1)),
		"F1 занят дебаг-панелью")
	t.check(not s.call("is_reserved_event", "recall", _key(KEY_SPACE)),
		"своё умолчание вернуть можно, даже если его делит ui_accept")
	t.check(not s.call("is_reserved_event", "pause_menu", _key(KEY_ESCAPE)),
		"паузе её собственный Esc вернуть можно")
	t.check(not s.call("is_reserved_event", "recall", _key(KEY_R)),
		"свободная клавиша не запрещена")
	s.free()

## Действие без единого события недостижимо — записать такое нельзя.
static func test_action_never_left_empty(t: TestCtx) -> void:
	var s: Node = _settings()
	s.set("bindings", {"recall": []})
	s.call("apply_bindings")
	t.check(InputMap.event_is_action(_key(KEY_SPACE), "recall"),
		"пустой список в файле игнорируется, умолчание остаётся")
	s.call("reset_bindings")
	s.free()

# --- Пресеты --------------------------------------------------------------

## Пресет — те же оверрайды: правка любой строки делает раскладку своей.
static func test_presets_switch_and_report(t: TestCtx) -> void:
	var s: Node = _settings()
	t.check_eq(int(s.call("current_preset")), int(Settings.Preset.DEFAULT),
		"на чистых настройках — раскладка по умолчанию")
	s.call("apply_preset", int(Settings.Preset.ARROWS))
	t.check(InputMap.event_is_action(_key(KEY_LEFT), "pan_left"),
		"«стрелки»: панорама на стрелке")
	t.check(not InputMap.event_is_action(_key(KEY_A), "pan_left"),
		"и WASD с панорамы снят — иначе A занят политиками и панорамой сразу")
	t.check(InputMap.event_is_action(_key(KEY_A), "policies"),
		"действия переехали под левую руку")
	t.check(InputMap.event_is_action(_pad(JOY_BUTTON_LEFT_SHOULDER), "policies"),
		"геймпад пресеты не трогают")
	t.check_eq(int(s.call("current_preset")), int(Settings.Preset.ARROWS),
		"пресет узнаётся обратно")
	t.check_eq((s.call("conflicts") as Dictionary).size(), 0,
		"в пресете «стрелки» конфликтов нет")

	s.call("apply_preset", int(Settings.Preset.ONE_HAND))
	t.check(InputMap.event_is_action(_key(KEY_Q), "recall"),
		"«одна рука»: отзыв под левой ладонью")
	t.check_eq((s.call("conflicts") as Dictionary).size(), 0,
		"в пресете «одна рука» конфликтов нет")
	s.call("set_slot", "beacon", int(InputBindings.Slot.KEY_1), _key(KEY_G))
	t.check_eq(int(s.call("current_preset")), int(Settings.Preset.CUSTOM),
		"правка строки делает раскладку своей")
	s.call("reset_bindings")
	t.check_eq(int(s.call("current_preset")), int(Settings.Preset.DEFAULT),
		"сброс возвращает умолчание")
	s.free()

# --- Подписи --------------------------------------------------------------

## Подписи на экране должны быть читаемы: as_text() даёт «Space - Physical» и
## «Joypad Button 1 (Right Action, Sony Circle, Xbox B, Nintendo A)».
static func test_labels_are_short(t: TestCtx) -> void:
	t.check_eq(InputBindings.label(_key(KEY_SPACE)), "Space", "клавиша подписана чисто")
	t.check_eq(InputBindings.label(_pad(JOY_BUTTON_B)), "B", "кнопка геймпада — одной буквой")
	t.check_eq(InputBindings.label(_pad(JOY_BUTTON_LEFT_SHOULDER)), "LB", "бампер подписан")
	t.check_eq(InputBindings.label(null), InputBindings.EMPTY_LABEL, "пустой слот — прочерк")
	t.check_eq(InputBindings.action_label("recall", false), "Space",
		"подсказка на клавиатуре берёт клавишу")
	t.check_eq(InputBindings.action_label("recall", true), "B",
		"подсказка на геймпаде берёт кнопку")

## Полоса подсказок обязана поехать за ремапом: раньше она хранила подписи
## константами и после переназначения врала до конца забега.
static func test_hint_label_follows_remap(t: TestCtx) -> void:
	var s: Node = _settings()
	s.call("set_slot", "recall", int(InputBindings.Slot.KEY_1), _key(KEY_R))
	t.check_eq(InputBindings.action_label("recall", false), "R",
		"после ремапа подсказка показывает новую клавишу")
	s.call("reset_bindings")
	t.check_eq(InputBindings.action_label("recall", false), "Space",
		"после сброса — снова Space")
	s.free()

## Оверлеи и тап курсором переназначаются: Guidelines требуют «all game
## controls», а служебные F1 и режим съёмки — не игровые.
static func test_remappable_covers_game_actions(t: TestCtx) -> void:
	for action: String in ["overlay_marks", "overlay_flood", "overlay_jobs",
			"cursor_tap"]:
		t.check(Settings.REMAPPABLE.has(action),
			"%s переназначается" % action)
	for action: String in ["debug_panel", "capture_toggle", "capture_layers"]:
		t.check(not Settings.REMAPPABLE.has(action),
			"служебное %s не переназначается" % action)

## Действие только с геймпадом (cursor_tap) правится в своём слоте и не
## получает пустых клавиатурных.
static func test_pad_only_action_has_empty_key_slots(t: TestCtx) -> void:
	var slots: Array[InputEvent] = InputBindings.slots("cursor_tap")
	t.check(slots[int(InputBindings.Slot.KEY_1)] == null, "клавиши у тапа нет")
	t.check(slots[int(InputBindings.Slot.PAD)] != null, "кнопка геймпада есть")
	t.check_eq(InputBindings.slot_label("cursor_tap", int(InputBindings.Slot.KEY_1)),
		InputBindings.EMPTY_LABEL, "пустой слот показывает прочерк")
	var s: Node = _settings()
	t.check(s.call("set_slot", "cursor_tap", int(InputBindings.Slot.KEY_1), _key(KEY_T)),
		"клавишу такому действию добавить можно")
	t.check(InputMap.event_is_action(_pad(JOY_BUTTON_A), "cursor_tap"),
		"кнопка при этом осталась")
	s.call("reset_bindings")
	s.free()
