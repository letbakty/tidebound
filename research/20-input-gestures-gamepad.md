# 20 — Ввод: жесты, мультитач, геймпад, safe area, экспорт

**Для этапов:** 12 п.5 (`InputService`), 16 (весь), 13/14 (тап по миру, свайпы панелей).
**Дата ресерча:** 2026-08-21. **Движок:** Godot 4.7.x stable.

---

## 1. Порядок обработки ввода — фундамент, без которого всё остальное не имеет смысла

Godot прогоняет каждое событие через цепочку:

```
Viewport._input()  →  Control._gui_input() (по слоям, сверху вниз)
                   →  Viewport._shortcut_input()
                   →  Viewport._unhandled_key_input()
                   →  Viewport._unhandled_input()
```
Внутри каждого уровня узлы опрашиваются **в обратном порядке дерева** (последний ребёнок первым).

**Наши правила:**

| Что | Где обрабатывать | Почему |
|---|---|---|
| Клики по кнопкам/панелям | `_gui_input` (сам `Control`) | штатно |
| Тап/лонгпресс/драг **по миру** | `_unhandled_input` в `InputService` | не должно срабатывать сквозь панель |
| F1, Esc, 1/2/3, Space | `_unhandled_input` | не должно срабатывать при фокусе в `LineEdit` |
| Пинч | `_unhandled_input` | то же |

**`get_viewport().set_input_as_handled()` после каждой реакции** — иначе одно касание отработают и `InputService`, и HUD, и дебаг-панель.

⚠️ **`InputService` — нода в `Main`, не автолоад** (промпт 12). Автолоад висел бы на `/root` и получал `_input` раньше всего GUI. Ставить `InputService` **первым ребёнком** `Main` (значит — обрабатывается последним среди детей), чтобы панели имели приоритет.

---

## 2. Мультитач: трекер касаний

`InputEventScreenTouch`: `index: int`, `position: Vector2`, `pressed: bool`, `double_tap: bool`, `canceled: bool`.
`InputEventScreenDrag`: `index: int`, `position`, `relative`, `velocity`.

**`index` — идентификатор пальца.** Считать «сколько пальцев» инкрементами нельзя: одно потерянное «отпускание» — и счётчик залипнет навсегда.

```gdscript
class_name InputService
extends Node

var _touches: Dictionary[int, Vector2] = {}      # index -> текущая позиция

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = t.position
			_on_touch_down(t)
		else:
			_touches.erase(t.index)              # erase по index — не залипнет
			_on_touch_up(t)
	elif e is InputEventScreenDrag:
		var d := e as InputEventScreenDrag
		_touches[d.index] = d.position
		_on_drag(d)
```

⚠️ **`canceled = true`** приходит, когда система отобрала касание (входящий звонок, системный жест). Обрабатывать как «отпускание без действия» — иначе долгое нажатие «зависнет» в прогрессе.

---

## 3. Пинч-зум: `InputEventMagnifyGesture` НЕ покрывает все платформы

**Факты:**
- `InputEventMagnifyGesture` (поле `factor: float`) приходит на macOS-трекпаде.
- На **Android** требует включённой настройки проекта **`input_devices/pointing/android/enable_pan_and_scale_gestures`** (по умолчанию **выключена**).
- На iOS/Windows-тачскринах на неё полагаться нельзя.
- Открытое предложение [godot-proposals#4340](https://github.com/godotengine/godot-proposals/issues/4340) «Implement standard and configurable gestures across all platforms» — то есть единого кроссплатформенного API **нет**.

**Вывод: пинч считать вручную из двух `InputEventScreenDrag`, а `MagnifyGesture` — как дополнительный источник.**

```gdscript
signal zoom_step(delta: int)                    # +1 / -1, ступенями (docs/01 §1.1)

const PINCH_STEP_PX: float = 60.0               # пикселей изменения дистанции на ступень
var _pinch_ref: float = -1.0

func _on_drag(_d: InputEventScreenDrag) -> void:
	if _touches.size() != 2:
		_pinch_ref = -1.0
		return
	var keys: Array = _touches.keys()
	keys.sort()                                  # стабильный порядок пальцев
	var dist: float = _touches[keys[0]].distance_to(_touches[keys[1]])
	if _pinch_ref < 0.0:
		_pinch_ref = dist
		return
	var delta: float = dist - _pinch_ref
	if absf(delta) >= PINCH_STEP_PX:
		zoom_step.emit(1 if delta > 0.0 else -1)
		_pinch_ref = dist                        # новый опорный => ступени, не непрерывность

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMagnifyGesture:            # macOS-трекпад: бонусом
		var f: float = (e as InputEventMagnifyGesture).factor
		if absf(f - 1.0) > 0.15:
			zoom_step.emit(1 if f > 1.0 else -1)
```
⚠️ **Пока пальцев два — панорама должна быть выключена**, иначе камера уедет во время пинча. Флаг `_pinch_active` и ранний выход в обработчике драга.

⚠️ **Ступени, а не непрерывный зум** — требование docs/01 §1.1 и пиксель-арта (doc 12 §6.3). Плавная анимация перехода — да, промежуточные значения как конечное состояние — нет.

---

## 4. Long-press с прогрессом у пальца

```gdscript
signal world_long_pressed(pos: Vector2)
signal long_press_progress(pos: Vector2, t: float)   # 0..1 для индикатора

const LONG_PRESS_SEC: float = 0.5
const MOVE_TOLERANCE_PX: float = 12.0

var _lp_index: int = -1
var _lp_start: Vector2 = Vector2.ZERO
var _lp_time: float = 0.0

func _process(delta: float) -> void:
	if _lp_index == -1:
		return
	_lp_time += delta
	long_press_progress.emit(_lp_start, minf(_lp_time / LONG_PRESS_SEC, 1.0))
	if _lp_time >= LONG_PRESS_SEC:
		world_long_pressed.emit(_lp_start)
		_lp_index = -1                            # сработало один раз
```
Отмена: смещение больше `MOVE_TOLERANCE_PX` (это уже драг), второй палец, `canceled`, отпускание.

⚠️ **`_process`, а не `Timer`** — потому что нужен прогресс каждый кадр для индикатора у пальца (требование docs/01). `Timer` дал бы только момент срабатывания.

⚠️ **Порог смещения обязателен и должен быть щедрым (10–14 px).** Палец на телефоне всегда немного ползёт; при пороге 2 px long-press почти никогда не сработает.

**Мышь мапится в те же сигналы:** удержание ПКМ 0.5 с → `world_long_pressed`. Это требование промпта 12 («мышь мапится в те же сигналы») и оно же делает всю игру тестируемой без устройства.

---

## 5. Мышь ↔ тач: две настройки, которые могут задвоить события

- `input_devices/pointing/emulate_touch_from_mouse` — мышь порождает `InputEventScreenTouch`. **Включать для отладки жестов** (промпт 12 требует проверки жестов в редакторе).
- `input_devices/pointing/emulate_mouse_from_touch` — касание порождает `InputEventMouseButton`. **По умолчанию включена** — это то, благодаря чему `Button` нажимается пальцем.

⚠️ **Включив первую, легко получить двойную обработку:** мышь → touch → (эмуляция обратно) → mouse. Godot защищается от петли, но код, который слушает **и** `InputEventMouseButton`, **и** `InputEventScreenTouch`, получит оба. **Правило: `InputService` слушает ТОЛЬКО тач-события и явно мышь-специфичные (колесо, ПКМ), но не «клик».** Клик приходит как эмулированный тач.

**Определение активного устройства ввода** (для подсказок кнопок в HUD, промпт 16 п.2):
```gdscript
enum Device { KEYBOARD, TOUCH, PAD }
var device: Device = Device.KEYBOARD
signal device_changed(d: Device)

func _input(e: InputEvent) -> void:
	var d: Device = device
	if e is InputEventJoypadButton or e is InputEventJoypadMotion: d = Device.PAD
	elif e is InputEventScreenTouch or e is InputEventScreenDrag:  d = Device.TOUCH
	elif e is InputEventKey or e is InputEventMouse:               d = Device.KEYBOARD
	if d != device:
		device = d
		device_changed.emit(d)
```
⚠️ **`InputEventJoypadMotion` летит постоянно от дрейфа стика.** Фильтровать: `absf(e.axis_value) > 0.5`. Иначе HUD будет мигать между иконками клавиатуры и геймпада.

---

## 6. Геймпад и Steam Deck

**Подключение:**
```gdscript
Input.get_connected_joypads() -> Array[int]
Input.joy_connection_changed(device: int, connected: bool)   # сигнал
Input.get_joy_name(device) -> String
```

**Виртуальный курсор** (промпт 16 п.2): узел `Control`/`Sprite2D` на отдельном слое, позиция двигается правым стиком:
```gdscript
func _process(delta: float) -> void:
	if device != Device.PAD: return
	var v := Input.get_vector("cursor_left", "cursor_right", "cursor_up", "cursor_down")
	if v.length_squared() < 0.04: return          # мёртвая зона стика
	_cursor_pos += v * CURSOR_SPEED * delta
	_cursor_pos = _cursor_pos.clamp(Vector2.ZERO, get_viewport_rect().size)
	cursor_node.position = _cursor_pos.round()    # целые пиксели
```
⚠️ Оси стика нужны как **действия** в Input Map (`cursor_left` и т.д. на `InputEventJoypadMotion`), иначе `get_vector` не сработает. Добавить их в генератор из doc 10 §5.

**Фокус-навигация в панелях.** Godot сам строит соседей по геометрии, но в сложных лейаутах ошибается. Явные соседи:
```gdscript
btn_a.focus_neighbor_bottom = btn_b.get_path()
btn_b.focus_neighbor_top = btn_a.get_path()
# и обязательно на каждой панели:
first_control.grab_focus()
```
⚠️ **Приёмка «вся игра проходима только геймпадом» падает чаще всего на том, что при открытии панели фокус никто не забрал** — и стик двигает курсор, а не выбирает. Правило: `PanelHost` (этап 14) при открытии панели вызывает `panel.grab_initial_focus()`, при закрытии — возвращает фокус тому, кто открыл.

⚠️ `focus_mode` у `Label`/`Panel` по умолчанию `FOCUS_NONE` — они пропускаются, это правильно. Но у кастомного компонента (`policy_slider`, `agent_chip`) его надо выставить в `FOCUS_ALL` явно, иначе он выпадет из навигации.

**Steam Deck:** воспринимается как обычный геймпад (Xbox-раскладка). Отдельного API не нужно. Разрешение 1280×800 (16:10) — **проверить, что HUD не ломается на 16:10**, у нас базовое 16:9. `aspect = expand` это переживает, но safe-area отступы стоит проверить глазами.

---

## 7. Safe area и DPI

```gdscript
func _safe_margins() -> Vector4i:
	var win: Vector2i = DisplayServer.window_get_size()
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	# Фолбэк: headless/desktop вернут весь экран или мусор
	if safe.size.x <= 0 or safe.size.y <= 0 or safe.size == win:
		return Vector4i(12, 12, 12, 12)           # минимум из docs/01 §5
	return Vector4i(
		maxi(safe.position.x, 12),
		maxi(safe.position.y, 12),
		maxi(win.x - safe.end.x, 12),
		maxi(win.y - safe.end.y, 12))
```
⚠️ **Фолбэк обязателен:** на десктопе и в headless `get_display_safe_area()` вернёт полный экран, разность будет 0, и отступов не будет вовсе. Промпт 13 требует «фолбэк ≥12px» — вот он.

⚠️ **Safe area — в физических пикселях экрана, а не в единицах UI.** При `content_scale_factor != 1.0` их надо делить на фактор, иначе на hiDPI отступы будут вдвое больше нужного. ⚠️ **НЕ ПОДТВЕРЖДЕНО** документацией для 4.7 — проверить на устройстве и записать вывод.

`DisplayServer.get_display_cutouts()` (Android) — прямоугольники «чёлок»; полезно, если HUD-элемент окажется под вырезом. Для нашего лейаута (полосы сверху/снизу) хватает safe area.

**Масштаб UI из DPI** (промпт 16 п.3):
```gdscript
func _auto_ui_scale() -> float:
	var dpi: int = DisplayServer.screen_get_dpi()
	if dpi <= 0: return 1.0                       # неизвестно (Linux/headless)
	# 160 dpi = 1x (Android mdpi baseline). Ступени по 0.25, чтобы UI не мылил.
	return clampf(snappedf(float(dpi) / 160.0, 0.25), 1.0, 3.0)
get_tree().root.content_scale_factor = _auto_ui_scale() * Settings.ui_scale
```
⚠️ **`snappedf(..., 0.25)`** — не произвольный масштаб. Пиксельный шрифт при факторе 1.37 превратится в кашу. И это же значение перемножается с пользовательским слайдером 75–150% (промпт 15) — итог тоже надо снапить.

---

## 8. Проверка «цель ≥48dp»

`TOUCH_MIN = 48` из токенов — это **dp**, а не пиксели. В пикселях цель = `48 * content_scale_factor`. Поскольку `custom_minimum_size` задаётся в единицах UI (до умножения на `content_scale_factor`), достаточно `custom_minimum_size = Vector2(48, 48)` — движок сам отмасштабирует.

**Автотест вместо ручного аудита** (экономит весь п.3 промпта 16):
```gdscript
# tests/test_touch_targets.gd — обходит сцены HUD и панелей
static func audit(root: Node, t: TestCtx) -> void:
	for n: Node in root.find_children("*", "Control", true, false):
		var c := n as Control
		if c.focus_mode == Control.FOCUS_NONE and not (c is BaseButton):
			continue                              # неинтерактивный
		if not c.visible: continue
		var s: Vector2 = c.get_rect().size
		t.check(s.x >= 48.0 and s.y >= 48.0,
			"%s: цель %dx%d < 48dp" % [c.get_path(), s.x, s.y])
```
Запускать из headless-раннера с инстанцированными сценами HUD/панелей. **Ловит регрессии на этапах 13–15 сразу, а не на 16-м.**

---

## 9. `export_presets.cfg` и сборка из командной строки

**Пресеты создаются в редакторе** (Project → Export) — генерировать файл руками не стоит, формат меняется между версиями. Что важно знать:

```bash
# Список пресетов и валидация (упадёт, если нет export templates)
godot --headless --export-release "Windows Desktop" build/tidebound.exe
godot --headless --export-debug   "Android"         build/tidebound.apk
# Обязательно ДО экспорта, если проект не импортирован:
godot --headless --import --quit
```

- **Имя пресета в команде — точная строка из `export_presets.cfg`** (`name="Windows Desktop"`). Опечатка даёт «no export preset found».
- **Export templates** должны быть установлены (Editor → Manage Export Templates) и **их версия должна совпадать с версией движка**. В CI — качать `.tpz` под ту же версию.
- ⚠️ **`export_presets.cfg` коммитим, `.godot/` — нет** (doc 10 §8). Пароли подписи в 4.x лежат отдельно и в git попасть не должны.
- **Exclude-фильтр для release:** `res://debug/*`, `res://tests/*`, `res://tools/*` — см. doc 13 §3.
- **Android:** нужен SDK + `debug.keystore`; при отсутствии — оставить пресет и `# TODO`, приёмка промпта 16 это разрешает.
- **iOS:** только пресет-заглушка, сборка требует macOS + Xcode.

**Иконка-заглушка:** 
```gdscript
# tools/gen_icon.gd
var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
img.fill(Color("1b2a33"))
img.fill_rect(Rect2i(0, 128, 256, 128), Color("2e5f6e"))   # «вода» снизу
img.save_png("res://icon.png")
```
Мгновенно и в палитре игры — лучше, чем дефолтный логотип Godot в билде.

---

## 10. Чек-лист приёмок этапов 12 (ввод) и 16

- [ ] Пинч работает **без** `MagnifyGesture` (проверить с выключенной `enable_pan_and_scale_gestures`).
- [ ] Панорама не срабатывает во время пинча.
- [ ] Long-press: прогресс виден, отменяется смещением >12 px и вторым пальцем.
- [ ] Двойной тап по пустому месту переключает скорость (`double_tap` у `InputEventScreenTouch`).
- [ ] Edge-swipe справа открывает политики и не конфликтует с системным жестом «назад» на Android.
- [ ] `_touches` пуст после отпускания всех пальцев (проверить `canceled`).
- [ ] Вся игра проходима геймпадом: **фокус захватывается при каждом открытии панели**.
- [ ] Иконки подсказок переключаются по последнему устройству и не мигают от дрейфа стика.
- [ ] Автотест целей ≥48dp зелёный на HUD и всех панелях.
- [ ] Safe area применена, фолбэк 12px работает на десктопе.
- [ ] `godot --headless --export-release "<preset>"` собирается (или пресет готов + TODO).

---

## Источники

- [InputEventScreenTouch](https://docs.godotengine.org/en/stable/classes/class_inputeventscreentouch.html) / [InputEventScreenDrag](https://docs.godotengine.org/en/stable/classes/class_inputeventscreendrag.html) — `index`, `double_tap`, `canceled`
- [InputEventMagnifyGesture](https://docs.godotengine.org/en/stable/classes/class_inputeventmagnifygesture.html) — на Android требует `input_devices/pointing/android/enable_pan_and_scale_gestures`
- [godot-proposals#4340](https://github.com/godotengine/godot-proposals/issues/4340) — единого кроссплатформенного API жестов нет
- [Input examples](https://docs.godotengine.org/en/stable/tutorials/inputs/input_examples.html) — «Emulate Touch From Mouse»
- [Multiple resolutions](https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html) — `content_scale_factor`, hiDPI
- [Exporting projects](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html) — CLI-экспорт, export templates
- [Federico-Ciuffardi/GodotTouchInputManager](https://github.com/Federico-Ciuffardi/GodotTouchInputManager) — эталонная реализация распознавания жестов на GDScript (для сверки, не для зависимости)
