# 21 — HUD и игровые панели: `_draw`-шкала, Tween, тосты, PanelHost

**Для этапов:** 13 (весь), 14 (весь), 15 (те же приёмы на экранах), 16 (фокус и цели касания).
**Дата ресерча:** 2026-08-21. **Движок:** Godot 4.7.x stable.

---

## 1. Главное архитектурное правило этапов 13–14

**HUD никогда не читает sim.** Только:
- вниз — `Game.cmd_*`;
- вверх — сигналы `Events`;
- разрешённое исключение — синхронные `Game.query_*` (промпт 14 вводит `query_agent`).

Отсюда следует то, что определяет весь код HUD: **каждый виджет держит собственный кэш, наполняемый событиями.** Постройки на шкале прилива, тренды ресурсов, «сколько внизу осталось» — всё это локальные словари в нодах, а не запросы в мир.

```gdscript
# tide_gauge.gd
var _buildings: Dictionary[int, Dictionary] = {}    # id -> {mark, flooded, damaged}

func _ready() -> void:
	Events.building_placed.connect(_on_b_placed)
	Events.building_state_changed.connect(_on_b_changed)
	Events.building_removed.connect(_on_b_removed)
```
⚠️ **Кэш обязан переживать загрузку сейва.** Он наполняется `rebroadcast_state` (doc 18 §7) — но только если перед этим очищен. **Правило: каждый кэширующий виджет подписан на `Events.run_started` и чистит себя там.** Забыть — значит после `Continue` видеть постройки прошлого забега.

⚠️ Событие `building_placed(id)` даёт только id. Значит виджету нужны детали — а лезть в sim нельзя. Два выхода: (а) расширить событие данными, (б) `Game.query_building(id)`. **Рекомендация (б)** — событие остаётся дешёвым (промпт 05 требует троттлинга), а запрос делается один раз на постройку.

---

## 2. `TideGauge`: единственный сложный `_draw` в проекте

**Кэш темы, а не `get_theme_*` в `_draw`** (doc 19 §5, п.3).

**Ширина линий задавать явно.** В 4.7 `CanvasItem` больше не добавляет antialiasing feather (GH-105122, research/00 §6) — линии стали тоньше. Деления ярусов при `width = -1.0` почти не видны.
```gdscript
const W_TICK: float = 1.0        # мелкая риска
const W_MARK: float = 2.0        # подписанная риска (каждые 2 яруса)
const W_PLATEAU: float = 2.0     # линия плато LOW
```

**Маппинг отметки в Y виджета — своя функция, не `WorldGeo`:**
```gdscript
const MARK_TOP: int = 6
const MARK_BOTTOM: int = -12
func _mark_to_y(m: float) -> float:
	var t: float = (float(MARK_TOP) - m) / float(MARK_TOP - MARK_BOTTOM)
	return roundf(t * size.y)         # roundf: риски на целых пикселях
```
⚠️ **`roundf` обязателен.** Дробный Y даёт полупрозрачную линию (даже без AA — из-за растеризации) и «дрожание» рисок при ресайзе.

⚠️ **`size.y` меняется** при смене `content_scale_factor` и разрешения. Значит `_mark_to_y` нельзя кэшировать; кэшировать надо только цвета и шрифт. Подписаться на `resized` → `queue_redraw()`.

**Порядок отрисовки (снизу вверх по слоям):**
1. фон шкалы, 2. заливка воды до `_mark_to_y(level)`, 3. линия плато LOW, 4. риски + подписи, 5. точки построек, 6. стрелка-поплавок, 7. прогноз циклов, 8. таймер фазы.

**Перерисовка — по событиям, не каждый кадр.** `water_level_changed` приходит раз в 3 тика (≈3 Гц) — этого достаточно и для плавности, и для бюджета. Таймер фазы (mm:ss) обновлять раз в секунду отдельным `Timer`, а не завязывать на `queue_redraw` всей шкалы. ⚠️ Иначе шкала перерисовывается 60 раз в секунду ради двух цифр.

**Прогноз кризисов:** `crisis_announced(type, cycle)` приходит за цикл до события. Виджет хранит `Dictionary[int, int]` (цикл → тип) и рисует иконки для циклов `N, N+1, N+2`. Чистится на `run_started`.

---

## 3. Tween в 4.7: что важно

```gdscript
var tw: Tween = create_tween()                    # метод Node; Tween — не нода
tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
tw.tween_property(self, "scale", Vector2(1.08, 1.08), 0.4)
tw.tween_property(self, "scale", Vector2.ONE, 0.4)          # последовательно
tw.parallel().tween_property(self, "modulate:a", 0.5, 0.4)  # параллельно предыдущему
tw.set_loops()                                              # бесконечно
```

**Факты и ловушки:**

1. **`create_tween()` привязывает Tween к узлу.** Узел освобождён → Tween останавливается. Это защищает от «твин анимирует мёртвый объект».
2. **Хранить ссылку и убивать перед новым:**
```gdscript
if _tw != null and _tw.is_valid():
	_tw.kill()
_tw = create_tween()
```
⚠️ **Без `kill()` два твина будут спорить за одно свойство** — классический баг «кнопка отзыва дёргается». Особенно на `set_loops()`-пульсации, которая переживает смену фазы.
3. **`is_valid()` перед любым обращением** к сохранённому Tween: после завершения объект остаётся, но невалиден.
4. **Пауза.** `Tween.set_pause_mode(Tween.TWEEN_PAUSE_BOUND/STOP/PROCESS)`. У нас `get_tree().paused` не используется (research/11 §3), так что дефолт подходит. **Но:** тактическая пауза (`Game.speed == 0`) на Tween'ы не влияет — и это правильно для UI (кнопки должны отзываться на паузе) и неправильно для мира (агенты не должны доезжать — research/15 §6.3).
5. **`tween_property(obj, "modulate:a", ...)`** — двоеточие указывает под-свойство. Работает для `position:x`, `scale:y` и т.д. Дешевле, чем анимировать весь Vector2.
6. **Числа с «подъездом»** (промпт 15, RunSummary):
```gdscript
tw.tween_method(func(v: float) -> void: label.text = "%d" % int(v), 0.0, float(total), 0.8)
```
`tween_method` вызывает Callable с интерполированным значением — ровно для этого случая.

---

## 4. Тосты: группировка и мёртвая зона

Промпт 13 п.4: группировка по типу за 10 с, тап — центр камеры, свайп — скрыть, **не перекрывать кнопку отзыва**.

```gdscript
const GROUP_WINDOW_SEC: float = 10.0
var _active: Dictionary[String, Dictionary] = {}   # type -> {node, count, t_last}

func push(type: String, text: String, cell: Vector2i) -> void:
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var g: Dictionary = _active.get(type, {})
	if not g.is_empty() and now - float(g["t_last"]) < GROUP_WINDOW_SEC:
		g["count"] = int(g["count"]) + 1
		g["t_last"] = now
		(g["node"] as Toast).set_count(int(g["count"]))
		(g["node"] as Toast).restart_timer()
		return
	var t: Toast = TOAST.instantiate()
	...
```
⚠️ **`Time.get_ticks_msec()` здесь допустим** — это UI, а не `sim/`. Запрет `Time.*` действует только в `sim/`.

**Мёртвая зона кнопки отзыва:** контейнер тостов — `VBoxContainer` в `MarginContainer` с нижним отступом `= размер кнопки + SPACE_3`. Не «на глаз в пикселях», а вычисляемо от `recall_button.size.y`, иначе при `content_scale_factor = 150%` они наедут.

**Свайп-скрытие:** `_gui_input` на тосте, `InputEventScreenDrag` с `relative.x > 40` → `queue_free()`. ⚠️ Тост при этом должен иметь `mouse_filter = STOP`, иначе драг уйдёт в мир и превратится в панораму камеры.

---

## 5. Банер и автопауза

Промпт 13 п.5: автопауза при **первом появлении типа за забег**.

```gdscript
# Game (чтобы попадало в сейв — промпт требует "словарь в Game на забег, в to_dict")
var seen_banner_types: Dictionary[int, bool] = {}

func note_banner(type: int) -> bool:
	if seen_banner_types.has(type):
		return false
	seen_banner_types[type] = true
	cmd_set_speed(0)
	return true                       # true = это первый раз, банер с автопаузой
```
⚠️ **Ключи `Dictionary[int, bool]` после JSON round-trip станут строками** (doc 18 §1). Сериализовать как `Array[int]` отсортированный — и проблема исчезает.

⚠️ **Автопауза должна возвращать прежнюю скорость**, а не ставить ×1. Хранить `_speed_before_pause` в `Game` и восстанавливать при закрытии банера/выборе карты (промпт 10 требует того же для драфта). **Один механизм на оба случая:**
```gdscript
func push_pause() -> void:
	if _pause_depth == 0: _speed_before = speed
	_pause_depth += 1
	cmd_set_speed(0)

func pop_pause() -> void:
	_pause_depth = maxi(_pause_depth - 1, 0)
	if _pause_depth == 0: cmd_set_speed(_speed_before)
```
Счётчик глубины нужен, потому что банер и драфт могут наложиться (объявление шторма в EBB одновременно с драфтом).

---

## 6. `PanelHost`: одна панель за раз

```gdscript
class_name PanelHost
extends Control

var _panels: Dictionary[String, Control] = {}
var _current: String = ""
var _focus_before: Control = null

func open(name: String, args: Dictionary = {}) -> void:
	if _current == name:
		close()                                  # повторный вызов = переключатель
		return
	close()
	var p: Control = _panels.get(name, null)
	if p == null: return
	_focus_before = get_viewport().gui_get_focus_owner()
	p.visible = true
	if p.has_method("setup"): p.call("setup", args)
	if p.has_method("grab_initial_focus"): p.call("grab_initial_focus")
	_current = name
	Events.ui_panel_opened.emit(name)

func close() -> void:
	if _current.is_empty(): return
	_panels[_current].visible = false
	Events.ui_panel_closed.emit(_current)
	_current = ""
	if _focus_before != null and is_instance_valid(_focus_before):
		_focus_before.grab_focus()               # геймпад: фокус возвращается
		_focus_before = null

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause_menu") and not _current.is_empty():
		close()
		get_viewport().set_input_as_handled()
```

**Технические моменты:**
- **`visible`, а не `instantiate`/`queue_free`.** Панели создаются один раз при старте: пересоздание даёт мигание и теряет состояние скролла. 6 панелей — ничтожная память.
- **`gui_get_focus_owner()`** для возврата фокуса — требование приёмки «проходима только геймпадом» (doc 20 §6).
- **Панели немодальные:** мир виден и тикает. Значит фон панели **не должен** быть полноэкранным `Control` с `mouse_filter = STOP` — иначе мир перестанет принимать тапы (doc 19 §5, п.4).
- ⚠️ **`Esc` в `_unhandled_input`, а не `_input`** — чтобы `LineEdit` внутри панели мог сначала снять свой фокус.

---

## 7. Bottom sheet с перетаскиванием

Промпт 14 п.7: «перетаскивается пальцем (полэкрана ↔ четверть)».

```gdscript
const SNAP: Array[float] = [0.25, 0.5]           # доли высоты экрана
var _drag_start_y: float = 0.0
var _height_start: float = 0.0

func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenDrag:
		var d := e as InputEventScreenDrag
		_set_height(_height_start + (_drag_start_y - d.position.y))
	elif e is InputEventScreenTouch and not (e as InputEventScreenTouch).pressed:
		_snap_to_nearest()

func _snap_to_nearest() -> void:
	var h: float = size.y / get_viewport_rect().size.y
	var best: float = SNAP[0]
	for s: float in SNAP:
		if absf(s - h) < absf(best - h): best = s
	var tw := create_tween()
	tw.tween_property(self, "custom_minimum_size:y",
		get_viewport_rect().size.y * best, 0.18).set_trans(Tween.TRANS_CUBIC)
```
⚠️ **Хват только за «ручку» сверху панели**, а не за всю панель — иначе скролл содержимого будет драгать лист. Отдельный `Control`-хэндл с `mouse_filter = STOP`, остальное — `PASS`.

---

## 8. `AgentCard`: «pull» вместо потока событий

Промпт 14 п.4 вводит `Game.query_agent(id) -> Dictionary` — единственный разрешённый синхронный запрос.

```gdscript
## Game
func query_agent(id: int) -> Dictionary:
	if world == null: return {}
	var a: SimAgent = world.agents.get_agent(id)
	return {} if a == null else a.to_view_dict()   # НЕ to_dict(): отдельная проекция
```
⚠️ **Отдельный `to_view_dict()`, а не `to_dict()`.** Сейв-словарь содержит внутренности (`_satiety_rem`, `path`, `job_id`), которые UI не нужны и которые изменятся при рефакторе. Разделив их, мы развязываем формат сейва и формат UI. Одна лишняя функция — и этапы 11 и 14 перестают конфликтовать.

**Обновление раз в секунду, пока открыта** (промпт): `Timer` с `wait_time = 1.0`, `autostart = false`, старт в `setup`, стоп в `_on_closed`. ⚠️ Не `_process` — карточка не должна стоить ничего 60 раз в секунду.

---

## 9. Тренды ресурсов

Промпт 13 п.2: «сравнение с началом прошлого цикла — считай в ноде».
```gdscript
var _totals_now: Dictionary[String, int] = {}
var _totals_prev_cycle: Dictionary[String, int] = {}

func _on_cycle_started(_c: int) -> void:
	_totals_prev_cycle = _totals_now.duplicate()   # duplicate! иначе общая ссылка

func trend(item_id: String) -> int:
	var now: int = _totals_now.get(item_id, 0)
	var was: int = _totals_prev_cycle.get(item_id, 0)
	return signi(now - was)                        # -1 / 0 / +1
```
⚠️ **`.duplicate()` обязателен** — словари передаются по ссылке (док Dictionary), без копии «прошлое» будет всегда равно «настоящему», и стрелка тренда всегда покажет →.

---

## 10. Чек-лист приёмок этапов 13 и 14

**13:**
- [ ] Полный цикл играется только с HUD.
- [ ] Шкала показывает сизигию (+2) и объявленный шторм; риски видны (ширина линий задана явно).
- [ ] Тосты группируются (×3) и не перекрывают кнопку отзыва при `content_scale_factor` 100% и 150%.
- [ ] Тап по AgentChip центрирует камеру плавно; при вводе игрока Tween камеры прерывается.
- [ ] Ни одного `get_theme_*` внутри `_draw`.
- [ ] Шкала не перерисовывается 60 Гц (счётчик `_draw` за 10 с ≤ ~50).
- [ ] После `Continue` из сейва кэши виджетов чистые (нет построек прошлого забега).

**14:**
- [ ] Открытие панели закрывает предыдущую; Esc закрывает; мир продолжает тикать.
- [ ] Фокус захватывается при открытии и возвращается при закрытии (геймпад).
- [ ] Радиал: страница «ещё» при >6 построек; заблокированные не показываются.
- [ ] Призрак дёргает sim только при смене клетки.
- [ ] `AgentCard` живая, «к агенту» работает, при закрытии таймер остановлен.
- [ ] Bottom sheet драгается только за ручку; скролл содержимого не конфликтует.

---

## Источники

- [Tween](https://docs.godotengine.org/en/stable/classes/class_tween.html) — `create_tween`, `parallel`, `set_loops`, `kill`, `is_valid`, `tween_method`
- [CanvasItem](https://docs.godotengine.org/en/stable/classes/class_canvasitem.html) — сигнатуры `draw_*`
- [Control](https://docs.godotengine.org/en/stable/classes/class_control.html) — `mouse_filter`, `focus_*`, `gui_get_focus_owner`
- [Dictionary](https://docs.godotengine.org/en/stable/classes/class_dictionary.html) — передача по ссылке, `duplicate()`
- research/00 §6 — GH-105122, линии без AA-feather в 4.7
- research/06 §9 — тот же вывод применительно к `TideGauge`
