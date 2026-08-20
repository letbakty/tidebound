# 10 — Каркас проекта: вьюпорты, масштабирование, настройки, автолоады

**Для этапов:** 00 (весь), 16 (п.3 мобильный масштаб), частично 12/13 (safe area).
**Дата ресерча:** 2026-08-21. **Движок:** Godot 4.7.x stable, рендерер Mobile.
Проверено по `docs.godotengine.org/en/stable` (баннер «Godot Engine 4.7 documentation»). Помеченное `⚠️ НЕ ПОДТВЕРЖДЕНО` — инженерный вывод, не факт из доки.

---

## 1. Главный технический риск этапа 00: гибридный вьюпорт и дробный масштаб

Промпт 00 задаёт схему: окно 1280×720, `stretch/mode = canvas_items`, `aspect = expand`, мир — в `SubViewport` 640×360 внутри `SubViewportContainer` со `stretch_shrink = 2`.

Что реально происходит с пикселем, по документации «Multiple resolutions»:

1. `canvas_items` — «базовый размер растягивается на весь экран», всё рисуется в целевом разрешении. Коэффициент = `размер_окна / базовый_размер`.
2. `SubViewportContainer.stretch_shrink = 2` делит **эффективное разрешение вьюпорта** на 2, сохраняя его экранный размер. Контейнер 1280×720 в canvas-координатах → SubViewport 640×360 → апскейл ×2 обратно в canvas.

Итог: **внутри canvas мир масштабируется строго ×2 — это идеально.** Но затем весь canvas умножается на `окно/1280`. На 1280×720 и 2560×1440 это целое, а на **1366×768 получается ×1.0672**, и мировой пиксель размазывается по 2.13 экранным. Это классический источник «дрожащих» и неровных пикселей, и он не лечится ни `Nearest`, ни `snap_2d_*`.

### Три варианта решения (выбор — на этапе 00, зафиксировать в README проекта)

| Вариант | Как | Плюс | Минус |
|---|---|---|---|
| **A. Оставить как есть** | ничего | UI всегда чёткий, лейаут тянется на любые пропорции | мир неровный на нецелых окнах |
| **B. `stretch/scale_mode = integer`** | Project Settings → `display/window/stretch/scale_mode = integer` (есть с 4.2) | пиксели идеальны везде | чёрные поля по краям на нецелых окнах |
| **C. Динамический `stretch_shrink`** | `main.gd` на `size_changed` подбирает `stretch_shrink` так, чтобы `окно/(640*shrink)` было ближе к целому | без полей и почти без дробности | мир меняет «зум» при ресайзе; сложнее |

**Рекомендация: вариант A + `stretch_scale_mode = integer` только если тест на 1366×768 выглядит плохо.** Промпт 16 требует проверки на 1280×720 и 1920×1080 — оба целые, проблема там не всплывёт; поэтому её надо проверить руками на 1366×768 и 1600×900 и записать вывод. Цитата документации про integer-режим: «Integer mode prevents distortion in pixel art by rounding down scale factors».

`stretch_shrink` — целое, минимум 1; `set_world_zoom(factor)` из промпта (clamp 2..4) при 1280×720 даст мир 640×360 / 426×240 / 320×180. **426 — нечётное число, 1280/3 = 426.67** → на shrink=3 контейнер не делится нацело и появится полупиксельный шов. Решение: либо разрешить только shrink ∈ {2, 4}, либо зумить камерой (`Camera2D.zoom`), а `stretch_shrink` держать константой 2. ⚠️ **Рекомендую второе:** зум мира — задача камеры (этап 02), а не вьюпорта; тогда `set_world_zoom` становится прокси к `CameraRig.set_zoom_step()`, и пиксель-сетка мира никогда не ломается.

---

## 2. Точные ключи ProjectSettings (для правки скриптом или руками)

Промпт 00 называет их частично по-человечески. Полные пути:

```
display/window/size/viewport_width            = 1280
display/window/size/viewport_height           = 720
display/window/stretch/mode                   = "canvas_items"
display/window/stretch/aspect                 = "expand"
display/window/stretch/scale                  = 1.0
display/window/stretch/scale_mode             = "fractional"   # или "integer", см. §1
rendering/renderer/rendering_method           = "mobile"
rendering/renderer/rendering_method.mobile    = "mobile"        # оверрайд для мобилок
rendering/textures/canvas_textures/default_texture_filter = 0   # 0 = Nearest
rendering/2d/snap/snap_2d_transforms_to_pixel = true
rendering/2d/snap/snap_2d_vertices_to_pixel   = true
physics/common/physics_ticks_per_second       = 60
physics/common/physics_jitter_fix             = 0.0
application/run/max_fps                       = 0
debug/gdscript/warnings/untyped_declaration   = 2   # 0=ignore 1=warn 2=error
debug/gdscript/warnings/unsafe_method_access  = 1
debug/gdscript/warnings/unsafe_property_access= 1
debug/gdscript/warnings/unsafe_call_argument  = 1
debug/gdscript/warnings/inferred_declaration  = 1
internationalization/locale/translations      = PackedStringArray("res://assets/i18n/strings.en.translation", ...)
input_devices/pointing/emulate_touch_from_mouse = true    # для отладки жестов, этап 12/16
input_devices/pointing/android/enable_pan_and_scale_gestures = true   # см. doc 20 §3
gui/theme/custom                              = "res://ui/theme/main_theme.tres"  # этап 12
```

**Тонкости:**

- `snap_2d_transforms_to_pixel` — проектная настройка, действует на **root viewport**. Для SubViewport есть одноимённые свойства узла: `SubViewport.snap_2d_transforms_to_pixel` / `snap_2d_vertices_to_pixel`. Промпт 00 ставит их на узле — это правильно. Но проектную настройку тоже стоит включить, иначе UI-элементы с дробными позициями (тосты, тултипы) дадут мыло. ⚠️ Проверить: если у HUD появятся «прыгающие» на 1px элементы при анимации Tween — снять проектный флаг и оставить только на SubViewport.
- `physics_jitter_fix = 0` — рекомендация из демо smooth-pixel-camera; при ненулевом значении движок подкручивает дельту физики, что вредит и сглаживанию камеры, и нашему собственному аккумулятору сим-тика.
- **`untyped_declaration = 2` (Error) поймает не всё.** Он ловит `var x = 1`, но не ловит `func f(a): ...` — для аргументов нужен `unsafe_call_argument`, а нетипизированный аргумент — отдельная категория. Полный «жёсткий» набор: `untyped_declaration`, `inferred_declaration`, `unsafe_call_argument`, `unsafe_method_access`, `unsafe_property_access`, `unsafe_cast`, `return_value_discarded`. Ставить всё в Error — вредно (`return_value_discarded` завалит на `connect()`), поэтому: **Error только на `untyped_declaration`, остальное Warn** — как и написано в промпте.

---

## 3. Автолоады: порядок, типы, ловушки

Порядок из промпта: `Events, Settings, Meta, SaveService, Game, AudioService`.

**Факты:**
- Автолоады инициализируются **в порядке списка в project.godot** и добавляются как дети `/root` до основной сцены. `_ready()` автолоада выполняется раньше `_ready()` главной сцены. Значит `Game._ready()` может обращаться к `Events` и `Settings`, но не наоборот.
- Автолоад можно объявлять как **скрипт** (движок сам обернёт в Node) или как **сцену**. Для наших шести — скрипт (`extends Node`), сцена не нужна.
- **Имя синглтона = имя в списке, а не `class_name`.** Не давать автолоадам `class_name` — иначе получатся два глобальных идентификатора с одинаковым именем и путаница в статическом анализе. ⚠️ Частая ошибка: `class_name Game` + автолоад `Game` → парсер жалуется на конфликт.
- Автолоады по умолчанию `PROCESS_MODE_ALWAYS`? Нет — по умолчанию `PROCESS_MODE_INHERIT`, а у корня это «пауза останавливает». **Для `Game` это неважно (паузу мы делаем сами через `speed = 0`, `get_tree().paused` не трогаем)**, но если когда-нибудь появится `get_tree().paused = true` для модалок — `AudioService` и `SaveService` надо будет пометить `PROCESS_MODE_ALWAYS`. Записать в комментарий.

**Заглушка автолоада (шаблон для этапа 00):**
```gdscript
extends Node
## Наполняет этап 11. Пока — только контракт, чтобы ссылки компилировались.

func _ready() -> void:
	pass
```

---

## 4. Главная сцена: почему именно такое дерево

```
Main (Control, Full Rect)
├── WorldContainer (SubViewportContainer, stretch=true, stretch_shrink=2)
│   └── WorldViewport (SubViewport 640×360)
├── HUDLayer   (CanvasLayer, layer=10)
├── PanelLayer (CanvasLayer, layer=20)
├── BannerLayer(CanvasLayer, layer=30)
└── DebugLayer (CanvasLayer, layer=100)
```

Технические факты, которые надо знать:

1. **`SubViewportContainer` рисует своих детей-SubViewport'ов сам.** `stretch = true` обязателен, иначе SubViewport останется своего размера и не растянется. Размер SubViewport при `stretch=true` **переустанавливается контейнером автоматически** — задавать `size = Vector2i(640,360)` в инспекторе бессмысленно, значение перезапишется как `размер_контейнера / stretch_shrink`.
2. **Каскад темы рвётся на `CanvasLayer`.** Это подтверждено формулировкой доки Theme: тема применяется «to the control itself, as well as all of its direct and indirect children» — но `CanvasLayer` не `Control`, цепочка Control'ов прерывается. → тему на этапе 12 надо назначать **корневому Control внутри каждого слоя**, а не только в Project Settings. Промпт 00 это учитывает.
3. **`CanvasLayer` не наследует `visible` родителя** и не участвует в `Control`-лейауте: дети должны сами быть Full Rect / с якорями.
4. **Ввод идёт сверху вниз по слоям:** более высокий `layer` получает `_gui_input`/`_unhandled_input` раньше. DebugLayer=100 перехватит F1 раньше HUD — это то, что нужно.
5. `Main` — `Control`, не `Node2D`: иначе якоря Full Rect не работают.

**`main.gd` — минимальный контракт для следующих этапов:**
```gdscript
extends Control
class_name MainRoot   # ⚠️ НЕ давать, если появится автолоад с таким же именем

@onready var world_container: SubViewportContainer = $WorldContainer
@onready var world_viewport: SubViewport = $WorldContainer/WorldViewport
@onready var hud_layer: CanvasLayer = $HUDLayer
@onready var panel_layer: CanvasLayer = $PanelLayer
@onready var banner_layer: CanvasLayer = $BannerLayer
@onready var debug_layer: CanvasLayer = $DebugLayer

# Зум мира ступенями. См. doc 10 §1: shrink=3 даёт нецелое деление 1280/3,
# поэтому по умолчанию оставляем 2 и зумим камерой.
func set_world_zoom(factor: int) -> void:
	world_container.stretch_shrink = clampi(factor, 2, 4)
```

---

## 5. Input Map из кода (быстрее и надёжнее, чем кликать в редакторе)

Промпт требует 15 действий + геймпад. Руками в редакторе это 40+ кликов и источник опечаток. **Быстрый путь: одноразовый `EditorScript`,** который прописывает всё в `InputMap` и сохраняет ProjectSettings.

```gdscript
@tool
extends EditorScript
## Одноразовая генерация Input Map. File → Run. После прогона файл можно удалить.

const ACTIONS: Dictionary[String, Array] = {
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

const PADS: Dictionary[String, Array] = {
	"recall":       [JOY_BUTTON_B],
	"build_radial": [JOY_BUTTON_Y],
	"policies":     [JOY_BUTTON_LEFT_SHOULDER],
	"beacon":       [JOY_BUTTON_X],
	"pause_menu":   [JOY_BUTTON_START],
	"speed_1":      [JOY_BUTTON_DPAD_LEFT],
	"speed_2":      [JOY_BUTTON_DPAD_UP],
	"speed_3":      [JOY_BUTTON_DPAD_RIGHT],
}

func _run() -> void:
	for action: String in ACTIONS:
		var path: String = "input/" + action
		var events: Array[InputEvent] = []
		for key: int in ACTIONS[action]:
			var e := InputEventKey.new()
			e.physical_keycode = key   # physical, а не keycode: работает на любой раскладке
			events.append(e)
		for btn: int in PADS.get(action, []):
			var j := InputEventJoypadButton.new()
			j.button_index = btn
			events.append(j)
		ProjectSettings.set_setting(path, {"deadzone": 0.5, "events": events})
	ProjectSettings.save()
	print("input map written: %d actions" % ACTIONS.size())
```

**Почему `physical_keycode`, а не `keycode`:** на кириллической раскладке `KEY_W` по `keycode` не сработает — придёт «ц». `physical_keycode` привязан к позиции клавиши. Для игры с русской локализацией это обязательное решение, промпт про него не говорит — **записать как `# РЕШЕНИЕ:`**.

**Не забыть `deadzone`**: без ключа `deadzone` в словаре действие создастся, но аналоговые оси геймпада будут дёргаться.

---

## 6. Локализация: CSV, импорт, и что ломается

- Файл `assets/i18n/strings.csv`, первая строка — заголовок `keys,ru,en`. **Первая колонка называется как угодно, важен порядок.** Godot импортирует CSV в набор `.translation`-файлов (по одному на локаль) и их надо добавить в `internationalization/locale/translations`.
- **Разделитель определяется при импорте** (запятая/точка с запятой/таб) — в доке импорта это опция `delimiter`. Русский текст с запятыми обязан быть в кавычках. ⚠️ Excel в русской локали сохраняет CSV с `;` — если правит человек, зафиксировать делимитер в `.import` и написать это в README.
- **Кодировка только UTF-8 без BOM.** BOM попадёт в первый ключ и `tr("APP_NAME")` вернёт ключ как есть.
- Смена языка в рантайме: `TranslationServer.set_locale("en")`. Узлы **не обновляются сами** — прилетает `NOTIFICATION_TRANSLATION_CHANGED`; `Label`/`Button` со свойством `text` его обрабатывают и перепереводят **только если строка была установлена как ключ и `auto_translate_mode` не выключен**. Строки, собранные в коде (`"Цикл %d/12" % n`), не обновятся никогда — их надо перестраивать вручную по нотификации. Подробности — doc 22.

Смоук-проверка на этапе 00: одна строка `APP_NAME,Отлив,Tidebound`, в `main.gd` временно `print(tr("APP_NAME"))` — должно печатать «Отлив», а не «APP_NAME».

---

## 7. Headless: запуск, импорт, коды выхода

```bash
# Одноразово (и в CI перед каждым прогоном тестов):
godot --headless --import --quit          # прогревает .godot/imported, иначе тесты падают
# Тесты:
godot --headless -s res://tests/run_all.gd
echo $?                                    # 0 = OK
```

Технические факты:
- `-s` / `--script` требует, чтобы скрипт наследовал `SceneTree` **или** `MainLoop`. При `extends SceneTree` точка входа — `_initialize()`. Выход — `quit(code)`.
- `quit(code)` из `_initialize()` не завершает процесс мгновенно: движок доработает текущий кадр. Если нужно вернуть код — сохранить его и вызвать `quit(code)` один раз.
- **`assert()` вырезается в release-сборке** (док GDScript: «Ignored in non-debug builds»). Headless-раннер из шаблонов запускается редактором/debug-бинарём, там assert работает; но **свои проверки в тестах писать через собственный хелпер `check(cond, msg)`, а не через `assert`** — иначе экспорт-сборка «пройдёт» все тесты молча. Подробнее — doc 24.
- `--headless` не создаёт окно → `DisplayServer` в режиме `headless`, `get_window()` возвращает валидный объект, но размеры фиктивные. Любой код, читающий `DisplayServer.get_display_safe_area()` в тестах, обязан иметь фолбэк.
- Вывод `print()` в headless идёт в stdout; `push_error` — в stderr и **делает код выхода ненулевым только если сам скрипт так решит**. Движок не падает от `push_error`.

---

## 8. .gitignore для Godot 4.7 (минимально достаточный)

```gitignore
# Godot 4+
.godot/
/android/
*.translation

# Экспорт
export_presets.cfg      # ⚠️ содержит пути и иногда ключи подписи — см. ниже
build/

# ОС
.DS_Store
Thumbs.db
```

⚠️ **Нюанс с `export_presets.cfg`:** промпт 16 требует коммитить пресеты. Файл может содержать пути к keystore и (в старых версиях) пароли. В 4.7 пароли выносятся в `.godot/export_credentials.cfg` — **его в git нельзя**. Итог: `export_presets.cfg` коммитим, `.godot/` игнорируем целиком — этого достаточно. `*.translation` игнорируем, потому что они генерируются из CSV при импорте.

---

## 9. Чек-лист приёмки этапа 00 (то, что реально ломается)

- [ ] `godot --headless --import --quit` завершается кодом 0 (если нет — битый .tres/.csv).
- [ ] `godot --headless -s res://tests/run_all.gd` печатает `TESTS OK`, код 0.
- [ ] В окне 1280×720 `WorldViewport.size == Vector2i(640, 360)` (проверить `print` в `_ready`).
- [ ] Ресайз окна в 1366×768: `WorldViewport.size` стал 683×384 — **это нормально**, мир просто показывает больше. Пиксель при этом дробный (§1) — решение зафиксировано в README проекта.
- [ ] `tr("APP_NAME")` возвращает «Отлив».
- [ ] `InputMap.has_action("overlay_jobs") == true` для всех 16 действий.
- [ ] Ни одного `var` без типа: проект открывается без ошибок при `untyped_declaration = Error`.

---

## Источники

- [Multiple resolutions (Godot 4.7)](https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html) — stretch modes, scale_mode integer, рекомендации для пиксель-арта и мобилок
- [SubViewportContainer](https://docs.godotengine.org/en/stable/classes/class_subviewportcontainer.html) — stretch, stretch_shrink
- [Theme](https://docs.godotengine.org/en/stable/classes/class_theme.html) — каскад темы
- [GDScript reference](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html) — assert в release, типизированные словари с 4.4
- [Handling quit requests](https://docs.godotengine.org/en/stable/tutorials/inputs/handling_quit_requests.html) — NOTIFICATION_WM_CLOSE_REQUEST, APPLICATION_PAUSED
- [voithos/godot-smooth-pixel-camera-demo](https://github.com/voithos/godot-smooth-pixel-camera-demo) — physics_jitter_fix=0, виртуальная позиция камеры
- [godot#93048 Camera2D pixel position jittery in scaled subviewport](https://github.com/godotengine/godot/issues/93048)
