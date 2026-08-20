# 13 — Дебаг-панель и оверлеи: `_draw`, троттлинг, гейт релиза

**Для этапов:** 03 (весь), 06/07/09/10/11 (панель обрастает секциями), 13 (`TideGauge` рисуется тем же `_draw`), 18 (график времени тика).
**Дата ресерча:** 2026-08-21. **Движок:** Godot 4.7.x stable.

Этап 03 сделан рано намеренно: всё, что в него вложено, окупается на этапах 05–11. Поэтому здесь важнее «как сделать расширяемо», чем «как сделать красиво».

---

## 1. Точные сигнатуры рисования (4.7)

```gdscript
void draw_line(from: Vector2, to: Vector2, color: Color, width: float = -1.0, antialiased: bool = false)
void draw_rect(rect: Rect2, color: Color, filled: bool = true, width: float = -1.0, antialiased: bool = false)
void draw_circle(position: Vector2, radius: float, color: Color, filled: bool = true, width: float = -1.0, antialiased: bool = false)
void draw_polyline(points: PackedVector2Array, color: Color, width: float = -1.0, antialiased: bool = false)
void draw_multiline(points: PackedVector2Array, color: Color, width: float = -1.0, antialiased: bool = false)
void draw_set_transform(position: Vector2, rotation: float = 0.0, scale: Vector2 = Vector2(1, 1))
void draw_texture_rect(texture: Texture2D, rect: Rect2, tile: bool, modulate: Color = Color(1,1,1,1), transpose: bool = false)
void draw_string(font: Font, pos: Vector2, text: String, alignment := HORIZONTAL_ALIGNMENT_LEFT,
                 width: float = -1, font_size: int = 16, modulate := Color.WHITE, ...)
```

Док: рисовать можно **только внутри `_draw()`**, соответствующего `_notification()` или метода, подключённого к сигналу `draw`.

**Три ловушки:**

1. **`width: float = -1.0` — это «тонкая линия», а не «нулевая».** Движок рисует хайрлайн примитивом. В 4.7 **`CanvasItem` больше не добавляет antialiasing feather (GH-105122)** — линии стали визуально тоньше, чем в 4.6. Для оверлеев это норма, но **для `TideGauge` (этап 13) ширину надо задавать явно** (`width = 2.0`), иначе деления ярусов почти не видны. Уже отмечено в research/06 §9.
2. **`draw_string` требует объект `Font`.** Его неоткуда взять в чистом `Node2D`. Правильный способ без зависимости от темы:
   ```gdscript
   var _font: Font = ThemeDB.fallback_font
   var _font_size: int = ThemeDB.fallback_font_size
   ```
   `ThemeDB` — глобальный синглтон, всегда доступен, ничего грузить не надо. Для дебага этого достаточно; для HUD (этап 13) брать шрифт из темы: `get_theme_font("font", "Label")`.
3. **`draw_string` рисует базовой линией (baseline), а не верхом текста.** Подпись отметки, поставленная в `mark_to_world_y(m)`, окажется выше линии. Компенсация: `pos.y + font_size * 0.35`.

---

## 2. Оверлей мира: где он живёт и когда перерисовывается

**Место в дереве:** `Node2D` внутри `World` (внутри `WorldViewport`), а НЕ на `DebugLayer`.
Причина: оверлей рисует **мировые** координаты (рёбра графа, подписи ярусов, заливку затопления). Если положить его на `CanvasLayer`, придётся вручную переводить мир→экран на каждый кадр и учитывать зум. Как ребёнок `World` он получает трансформацию камеры бесплатно.

**Панель (Control'ы) — наоборот, на `DebugLayer` (layer=100)**, в нативном разрешении: иначе текст панели пикселизуется вместе с миром и станет нечитаемым.

```
Main
├── WorldContainer/WorldViewport/World
│   └── DebugOverlay (Node2D)          ← _draw в мировых координатах
└── DebugLayer (CanvasLayer, layer=100)
    └── DebugPanel (Control)            ← кнопки, слайдеры, лог
```

### 2.1 Троттлинг: `queue_redraw` по событию, не каждый кадр

Промпт 03 прямо требует «обновление по сигналам, не каждый кадр». Технически:

```gdscript
extends Node2D
class_name DebugOverlay

var show_graph: bool = false
var show_marks: bool = false
var show_deposits: bool = false
var show_flood: bool = false

var _dirty: bool = false

func _ready() -> void:
	Events.water_level_changed.connect(_mark_dirty.unbind(1))
	Events.building_placed.connect(_mark_dirty.unbind(1))
	Events.deposit_changed.connect(_mark_dirty.unbind(1))
	Events.phase_changed.connect(_mark_dirty.unbind(2))

func _mark_dirty() -> void:
	_dirty = true

func _process(_delta: float) -> void:
	# Схлопываем пачку событий одного кадра в один queue_redraw.
	if _dirty:
		_dirty = false
		queue_redraw()
```

**`Callable.unbind(n)` — ключевой приём.** Сигнал `water_level_changed(level: float)` нельзя подключить к методу без аргументов: сигнатуры не совпадут, и Godot **молча не вызовет обработчик** (docs/02 §10 — «сигналы теряются молча»). `unbind(1)` отбрасывает один аргумент. Альтернатива — `func _mark_dirty(_a = null, _b = null)`, но она нетипизирована и нарушает CONVENTIONS.

⚠️ `queue_redraw()` сам по себе дешёвый (ставит флаг), но при 10 событиях за кадр даст 10 вызовов — они схлопнутся движком в один `_draw`. То есть буфер `_dirty` — микрооптимизация; **главная причина писать его иначе:** он даёт одну точку, куда легко добавить «перерисовывать не чаще 10 Гц», если оверлей графа станет тяжёлым.

### 2.2 Ранний выход
```gdscript
func _draw() -> void:
	if not (show_graph or show_marks or show_deposits or show_flood):
		return          # ничего не включено — ноль работы
```
Без этого выключённый оверлей всё равно вызывает `_draw` при каждом `queue_redraw`.

---

## 3. Гейт релизной сборки: `OS.is_debug_build()` и почему этого мало

Промпт требует: «в релизной сборке панель недоступна».

**Факты:**
- `OS.is_debug_build() -> bool` — `true` в редакторе и в **debug**-экспорте, `false` в release-экспорте. Это правильный рантайм-гейт.
- `Engine.is_editor_hint()` — `true` **только внутри редактора** (у `@tool`-скриптов). Для гейта релиза не годится.
- `OS.has_feature("debug")` — эквивалент `is_debug_build()`; `OS.has_feature("editor")` — только редактор. Через `has_feature` удобно проверять и `"mobile"`, `"android"`, `"web"`.

**Правильная реализация — не прятать, а не создавать:**
```gdscript
# main.gd
func _ready() -> void:
	if OS.is_debug_build():
		var panel: Node = preload("res://debug/debug_panel.tscn").instantiate()
		debug_layer.add_child(panel)
```
Если панель просто скрывать (`visible = false`), в релиз попадут её сцена, скрипт и все подписки на `Events` — а вместе с ними и риск, что подписка что-то сделает. `preload` внутри `if` **всё равно попадёт в сборку** (preload разрешается на этапе компиляции!) — для полного исключения нужен `load()`:
```gdscript
	if OS.is_debug_build():
		var scn: PackedScene = load("res://debug/debug_panel.tscn")
```
⚠️ Разница `preload` vs `load` здесь принципиальна и часто упускается. Для 200 КБ дебаг-панели это не про размер, а про гигиену.

**Экспорт-фильтр как второй рубеж:** в пресете экспорта (этап 16) в `Resources → Exclude filters` добавить `res://debug/*` для release-пресета. Тогда даже случайный `preload` не соберётся — и это выявится ошибкой на этапе экспорта, а не в проде.

---

## 4. Ввод: F1 и приоритет слоёв

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_panel"):
		_toggle()
		get_viewport().set_input_as_handled()
```

**Почему `_unhandled_input`, а не `_input`:**
- `_input` вызывается **до** обработки `Control`-ами. Если панель откроется на `_input`, нажатие также улетит в поле ввода сида под фокусом и напечатает «F1».
- `_unhandled_input` вызывается после GUI. Клавиша, съеденная `LineEdit`, сюда не дойдёт — то, что нужно.
- `set_input_as_handled()` останавливает дальнейшее распространение — иначе HUD (этап 13) может обработать ту же клавишу.

**Порядок между узлами:** `_unhandled_input` идёт **снизу вверх по дереву** (последний ребёнок первым). `DebugLayer` с `layer = 100` рисуется поверх, но порядок ввода определяется **порядком в дереве**, а не `layer`. Чтобы дебаг гарантированно получал ввод первым, `DebugLayer` должен быть **последним ребёнком** `Main`. Промпт 00 именно так его и ставит — это не случайность, зафиксировать.

**Четырёхпальцевый тап (заглушка-хук):**
```gdscript
var _touch_count: int = 0
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		_touch_count += 1 if t.pressed else -1
		_touch_count = maxi(_touch_count, 0)
		if _touch_count >= 4 and t.pressed:
			_toggle()
```
⚠️ Счётчик по `index` надёжнее счётчика инкрементов: при потере события «отпускание» счётчик залипнет. Полноценный трекер — в doc 20 §2, здесь заглушка допустима.

---

## 5. Кольцевой буфер лога: почему не `RichTextLabel.append_text`

Промпт: «кольцевой буфер 200 строк».

**Наивно и плохо:**
```gdscript
rich.append_text(line + "\n")     # текст растёт бесконечно -> утечка и тормоза
```
`RichTextLabel` при каждом append переразбирает BBCode и пересчитывает лейаут. За 12 циклов забега сюда прилетят тысячи `SimEvent` — панель начнёт есть больше, чем симуляция.

**Правильно — держать данные в массиве, а текст собирать при показе:**
```gdscript
const LOG_MAX: int = 200
var _log: Array[String] = []

func _on_sim_event(line: String) -> void:
	_log.append(line)
	if _log.size() > LOG_MAX:
		_log.remove_at(0)          # O(n), но n = 200 -> неважно
	_log_dirty = true

func _process(_d: float) -> void:
	if _log_dirty and visible:      # не собираем текст, пока панель закрыта
		_log_dirty = false
		log_label.text = "\n".join(_log)
```
**`visible`-гейт — главное:** закрытая панель не должна стоить ничего. Это же правило распространить на все секции: лейбл «тик/цикл/фаза» обновлять только при `visible`.

⚠️ Для лога использовать **`Label` с `autowrap_mode = OFF` внутри `ScrollContainer`**, а не `RichTextLabel`: BBCode нам не нужен, а `Label` в разы дешевле.

---

## 6. Подписка на все сигналы `Events` одной строкой

Промпт требует печатать все `SimEvent` в панель. Писать 30 обработчиков — плохо. Godot позволяет обойти список сигналов рефлексией:

```gdscript
func _ready() -> void:
	for sig: Dictionary in Events.get_signal_list():
		var sname: String = sig["name"]
		var argc: int = (sig["args"] as Array).size()
		# bind(sname) добавляет имя В КОНЕЦ списка аргументов обработчика
		Events.connect(sname, _on_any.bind(sname))

func _on_any(a = null, b = null, c = null) -> void:
	pass
```

⚠️ **Так не сработает:** `bind` добавляет аргумент в конец, а число сигнальных аргументов у разных сигналов разное — сигнатура не совпадёт и обработчик молча не вызовется. Рабочий вариант — генерировать `Callable` нужной арности:

```gdscript
func _ready() -> void:
	for sig: Dictionary in Events.get_signal_list():
		var sname: String = sig["name"]
		var argc: int = (sig["args"] as Array).size()
		var cb: Callable
		match argc:
			0: cb = func() -> void: _log_event(sname, [])
			1: cb = func(a1: Variant) -> void: _log_event(sname, [a1])
			2: cb = func(a1: Variant, a2: Variant) -> void: _log_event(sname, [a1, a2])
			_: continue   # сигналов с 3+ аргументами у нас нет (docs/02 §3.2)
		Events.connect(sname, cb)

func _log_event(sname: String, args: Array) -> void:
	_log.append("%s %s" % [sname, args])
	# ...
```

**Это даёт «санитарию сигналов» бесплатно:** панель видит все сигналы, включая те, что никто больше не слушает. Этап 19 п.3 после этого сводится к чтению лога. **Стоит сделать сразу на этапе 03.**

⚠️ Лямбда захватывает `sname` по значению в момент создания (док GDScript: *«Local variables are captured by value once, when the lambda is created»*) — здесь это ровно то, что нужно; в цикле `for` каждая итерация создаёт свою лямбду со своим `sname`.

---

## 7. Слайдер override уровня воды: NAN и JSON

Промпт: «добавь в Tide поле `level_override: float = NAN`; если не NAN — использовать вместо кривой».

⚠️ **`NAN` не сериализуется в JSON.** Док JSON: *«non-finite numbers are not supported»* — `NAN`/`INF` превратятся в `null`, а `float(null)` = 0.0, то есть после save/load вода залипнет на нуле. Обязательно:
```gdscript
func to_dict() -> Dictionary:
	return { "level_override": null if is_nan(level_override) else level_override, ... }

func from_dict(d: Dictionary) -> void:
	var v: Variant = d.get("level_override", null)
	level_override = NAN if v == null else float(v)
```

⚠️ И второе: **сравнивать с NAN через `==` нельзя** (`NAN == NAN` → false). Только `is_nan(x)`.

**Ещё аккуратнее:** override — чисто дебажная штука, она не должна попадать в сейв вообще. **Решение: не сериализовать `level_override`, всегда восстанавливать как NAN.** Тогда исчезает целый класс проблем и загруженный сейв не может «застрять» в дебаг-режиме. Записать `# РЕШЕНИЕ:`.

---

## 8. Промотка времени: «+1 фаза» / «+1 цикл» без ломки детерминизма

```gdscript
func _fast_forward_ticks(n: int) -> void:
	for i: int in n:
		Game.world.tick()
		Game._flush_events()     # ⚠️ приватный — см. ниже
```

**Проблема:** `_flush_events` приватный, а без него `events_out` растёт и UI не обновляется.
**Решение:** добавить в `Game` публичный метод (это не нарушает раздел «Не делать» промпта 03, потому что sim не трогает):
```gdscript
## Game
func debug_fast_forward(ticks: int) -> void:
	if not OS.is_debug_build():
		return
	for i: int in ticks:
		world.tick()
		_flush_events()
```
**Гейт `is_debug_build` внутри самого метода** — чтобы дебаг-панель не была единственной защитой.

⚠️ Промотка 3000 тиков за один кадр выдаст 3000 пачек сигналов подряд. UI (тосты этапа 13, `agent_view` этапа 05) может захлебнуться созданием нод. **Лечение: на время промотки поднимать флаг `Game.fast_forwarding = true`, а View-ноды при нём пропускают анимации и создают/удаляют себя без Tween'ов.** Один булев флаг, но он спасёт этапы 13–15 от «зависаний при +1 цикл».

---

## 9. График времени тика (нужен этапу 18 п.10, заложить сейчас)

```gdscript
# Game уже меряет _tick_budget_ms (см. research/11 §3).
# Панель рисует кольцевой буфер из 120 значений:
const N: int = 120
var _samples: PackedFloat32Array = PackedFloat32Array()

func _process(_d: float) -> void:
	if not visible: return
	_samples.append(Game.tick_budget_ms())
	if _samples.size() > N: _samples.remove_at(0)
	graph.queue_redraw()

# в graph._draw():
func _draw() -> void:
	var h: float = size.y
	var budget: float = 2.0          # docs/00 §16: бюджет 2 мс на тик
	draw_line(Vector2(0, h - h * 0.5), Vector2(size.x, h - h * 0.5),
		Color(1, 0.4, 0.4, 0.5), 1.0)     # линия бюджета
	var pts := PackedVector2Array()
	for i: int in _samples.size():
		pts.append(Vector2(size.x * i / float(N),
			h - clampf(_samples[i] / (budget * 2.0), 0.0, 1.0) * h))
	if pts.size() >= 2:
		draw_polyline(pts, Color("7fd8a0"), 1.0)
```
`PackedFloat32Array` здесь оправдан: 120 значений каждый кадр, это ровно тот случай, где packed-массив дешевле (док Array: *«Packed arrays are generally faster to iterate on and modify»*).

---

## 10. Чек-лист приёмки этапа 03

- [ ] F1 открывает/закрывает; при открытом `LineEdit` под фокусом F1 всё ещё работает (проверка `_unhandled_input`).
- [ ] Оверлеи включаются независимо; при всех выключённых `_draw` выходит сразу.
- [ ] Override воды двигает `WaterView` и меняет `is_flooded` в тот же тик.
- [ ] Лог не растёт: после 3000 промотанных тиков `_log.size() == 200`.
- [ ] Панель видит **все** сигналы `Events` (рефлексия из §6) — включая те, что ещё никто не эмитит.
- [ ] `godot --headless -s res://tests/run_all.gd` зелёный (панель не должна ломать headless: она просто не создаётся без сцены).
- [ ] В release-экспорте `res://debug/*` отсутствует (проверить через `--export-release` и распаковку pck).

---

## Источники

- [CanvasItem (Godot 4.7)](https://docs.godotengine.org/en/stable/classes/class_canvasitem.html) — сигнатуры draw_*, ограничение «только внутри _draw»
- [GH-105122](https://github.com/godotengine/godot/pull/105122) — удаление AA feather у линий в 4.7 (см. research/06 §9)
- [ThemeDB](https://docs.godotengine.org/en/stable/classes/class_themedb.html) — fallback_font / fallback_font_size
- [GDScript reference](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html) — захват переменных лямбдой по значению
- [JSON](https://docs.godotengine.org/en/stable/classes/class_json.html) — non-finite numbers не поддерживаются
