# 19 — UI-фундамент: тема из кода, компоненты, пиксельные шрифты

**Для этапов:** 12 (весь), 13–15 (всё строится на этом), 18 п.8 (атласный скин).
**Дата ресерча:** 2026-08-21. **Движок:** Godot 4.7.x stable.

Промпт 12 прямо говорит: «от качества этого этапа зависит скорость всех следующих». Ниже — три вещи, которые определяют эту скорость: генератор темы, правила компонента и настройки шрифта.

---

## 1. Тема из кода: точный API (частая галлюцинация)

**Метод называется `set_type_variation`, а НЕ `set_type_variation_base`.**
```gdscript
void  set_type_variation(theme_type: StringName, base_type: StringName)
StringName get_type_variation_base(theme_type: StringName) const
Array[StringName] get_type_variation_list(base_type: StringName) const
bool  is_type_variation(theme_type: StringName, base_type: StringName) const
void  clear_type_variation(theme_type: StringName)
```
Пары сеттеров/геттеров: `set_stylebox/get_stylebox`, `set_font`, `set_font_size`, `set_color`, `set_constant`, `set_icon` (+ `has_*`, `clear_*` у каждого).
Свойства темы: `default_font`, `default_font_size` (значения <1 невалидны), `default_base_scale` (0.0 = глобальный масштаб).

**Как это применяется в узле:**
```gdscript
button.theme_type_variation = "ButtonPrimary"
```
`theme_type_variation` — свойство `Control`, тип `StringName`. Тема должна знать, что `"ButtonPrimary"` — вариация от `"Button"`, иначе унаследованные свойства не подтянутся.

---

## 2. Генератор темы: скелет `theme_builder.gd`

```gdscript
@tool
extends EditorScript
## ui/theme/theme_builder.gd — File → Run. Перегенерирует main_theme.tres из токенов.
## Правишь tokens.gd -> жмёшь Run -> смотришь _gallery.tscn. Сцены не трогаются.

const OUT: String = "res://ui/theme/main_theme.tres"
const USE_ATLAS: bool = false          # этап 18 п.8 переключит в true

func _run() -> void:
	var th := Theme.new()
	th.default_font = _load_font()
	th.default_font_size = UITokens.FONT_M

	_build_panel(th)
	_build_button(th)
	_build_label(th)
	_build_slider(th)
	_build_checkbox(th)
	_build_lineedit(th)
	_build_tooltip(th)
	_build_variations(th)

	var err: Error = ResourceSaver.save(th, OUT)
	print("theme: %s (%s)" % [OUT, "OK" if err == OK else "ERR %d" % err])

func _flat(bg: Color, border: Color, w: int = UITokens.BORDER_W) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(w)
	sb.set_corner_radius_all(0)             # пиксель-арт: никаких скруглений
	sb.anti_aliasing = false                # ОБЯЗАТЕЛЬНО: иначе мыло на кромках
	sb.set_content_margin_all(UITokens.SPACE_2)
	return sb

func _build_button(th: Theme) -> void:
	th.set_stylebox("normal",   "Button", _flat(UITokens.PANEL_BG, UITokens.MUTED))
	th.set_stylebox("hover",    "Button", _flat(UITokens.PANEL_BG.lightened(0.08), UITokens.ACCENT))
	th.set_stylebox("pressed",  "Button", _flat(UITokens.PANEL_BG.darkened(0.15), UITokens.ACCENT))
	th.set_stylebox("disabled", "Button", _flat(UITokens.PANEL_BG.darkened(0.3), UITokens.MUTED))
	# focus — ОТДЕЛЬНЫЙ stylebox, рисуется ПОВЕРХ остальных. Прозрачный фон + рамка.
	var foc := _flat(Color(0, 0, 0, 0), UITokens.ACCENT, UITokens.BORDER_W + 1)
	th.set_stylebox("focus", "Button", foc)
	th.set_color("font_color", "Button", UITokens.INK)
	th.set_color("font_hover_color", "Button", UITokens.PAPER)
	th.set_color("font_disabled_color", "Button", UITokens.MUTED)
	th.set_font_size("font_size", "Button", UITokens.FONT_M)

func _build_variations(th: Theme) -> void:
	# 1) объявить вариацию, 2) переопределить только отличия
	th.set_type_variation("ButtonPrimary", "Button")
	th.set_stylebox("normal", "ButtonPrimary", _flat(UITokens.ACCENT, UITokens.INK))
	th.set_type_variation("ButtonDanger", "Button")
	th.set_stylebox("normal", "ButtonDanger", _flat(UITokens.DANGER, UITokens.INK))
	th.set_type_variation("ButtonGhost", "Button")
	th.set_stylebox("normal", "ButtonGhost", _flat(Color(0,0,0,0), UITokens.MUTED))
	th.set_type_variation("LabelTitle", "Label")
	th.set_font_size("font_size", "LabelTitle", UITokens.FONT_TITLE)
	th.set_type_variation("LabelSmall", "Label")
	th.set_font_size("font_size", "LabelSmall", UITokens.FONT_S)
	th.set_type_variation("LabelNum", "Label")
	th.set_font_size("font_size", "LabelNum", UITokens.FONT_M)
	th.set_type_variation("PanelDark", "Panel")
	th.set_type_variation("PanelRaised", "Panel")
	th.set_type_variation("CardPanel", "Panel")
	th.set_type_variation("TooltipPanel", "PanelContainer")
```

**Технические моменты:**
- **`anti_aliasing = false` на каждом `StyleBoxFlat`.** Дефолт `true` — и все рамки получат полупрозрачные кромки, что в пиксель-арте выглядит как грязь.
- **`set_corner_radius_all(0)`** — дефолт и так 0, но явно, чтобы никто не «улучшил».
- **`focus` — отдельный stylebox поверх**, а не замена `normal`. Приёмка требует «фокус ходит клавиатурой» и «видимая рамка ACCENT».
- **`TooltipPanel` — вариация от `PanelContainer`**, не от `Panel`. Godot рисует тултип как `PanelContainer` + `Label` с типами `TooltipPanel`/`TooltipLabel`. Частая ошибка — сделать вариацию от `Panel` и не понять, почему тултип не меняется.
- **`ResourceSaver.save(theme, path)`** — порядок аргументов (см. doc 14 §3).
- ⚠️ `EditorScript` запускается через **File → Run** (`Ctrl+Shift+X`), не кнопкой Play. Написать это комментарием в первой строке — иначе следующий агент будет искать кнопку.

**Ветка `USE_ATLAS`** (задел под этап 18): вместо `_flat()` — `_texture(region: Rect2i, margins: int) -> StyleBoxTexture`. Тело `_build_*` не меняется, меняется только фабрика стилей. **Это и есть смысл требования «смена скина — одной константой».**

---

## 3. Каскад темы рвётся: где назначать

Док Theme: тема применяется к контролу *«as well as all of its direct and indirect children»* — пока цепочка `Control`-ов не прервана. `CanvasLayer` — не `Control`, значит цепочка рвётся.

**Значит `gui/theme/custom` в Project Settings покрывает только детей корневого окна, но НЕ содержимое `HUDLayer`/`PanelLayer`/`BannerLayer`/`DebugLayer`.**

```gdscript
# main.gd
func _ready() -> void:
	var th: Theme = load("res://ui/theme/main_theme.tres")
	for layer: CanvasLayer in [hud_layer, panel_layer, banner_layer]:
		for child: Node in layer.get_children():
			if child is Control:
				(child as Control).theme = th
```
Проще и надёжнее: **каждый корневой `Control` внутри слоя имеет `theme` прописанной в своей сцене**. Тогда сцена самодостаточна и открывается в редакторе с правильным видом — это ускоряет вёрстку этапов 13–15 в разы.

⚠️ `SubViewport` тоже рвёт каскад. Если когда-нибудь понадобится `Control` внутри `WorldViewport` — тему назначать явно.

---

## 4. Пиксельные шрифты: настройки импорта, без которых всё мылит

Промпт 12 п.2 перечисляет: Antialiasing=None, Hinting=None, Subpixel=Disabled, MSDF=off, Mipmaps=off. **К этому списку в 4.4+ добавились ещё два пункта, без которых текст всё равно поедет:**

| Настройка (`FontFile`) | Значение | Почему |
|---|---|---|
| `antialiasing` | `None` (0) | сглаживание = мыло на 1px-штрихах |
| `hinting` | `None` (0) | хинтинг двигает пиксели |
| `subpixel_positioning` | `Disabled` (0) | иначе глиф встаёт на полпикселя |
| `msdf_pixel_range` / `multichannel_signed_distance_field` | off | MSDF — для векторного масштабирования, не для пиксель-арта |
| `generate_mipmaps` | off | мипмапы = блюр при уменьшении |
| **`keep_rounding_remainders`** | **false** | ⚠️ при `true` текст сдвигается на ~полпикселя каждые ~18 символов |
| **`oversampling`** | 0 / выключено | ⚠️ 4.x включает oversampling по умолчанию (док multiple_resolutions: *«Font oversampling is enabled by default»*) — для растрового пиксель-шрифта это лишний ресемплинг |

**Размер шрифта — только кратный «родному».** Если шрифт нарисован под 8 px, допустимы 8/16/24. `FONT_S=8, FONT_M=16, FONT_TITLE=24` — так и задать в токенах. `FONT_M = 14` даст мыло независимо от всех настроек выше.

⚠️ В 4.7 у `CanvasItem.draw_string` появился параметр `oversampling: float = 0.0` — признак того, что движок в этой версии активно менял работу с масштабированием шрифтов. **Проверить на глаз при первом же прогоне витрины и, если текст мылит, играть именно этими двумя настройками.**

**Кириллица.** Промпт называет monogram и Public Pixel (CC0) и Press Start 2P (OFL). ⚠️ **Press Start 2P кириллицу не содержит** — заголовки на русском будут «тофу»-квадратами. Варианты: (а) заголовки тем же monogram крупнее, (б) фолбэк-шрифт. Godot поддерживает цепочку фолбэков: `FontFile.fallbacks: Array[Font]`. **Рекомендация: один шрифт с кириллицей на всё, разные размеры — это и проще, и стилистически цельнее.**

**Фолбэк без файла (чтобы не блокироваться):**
```gdscript
func _load_font() -> Font:
	var path: String = "res://assets/fonts/monogram.ttf"
	if ResourceLoader.exists(path):
		return load(path)
	push_warning("TODO: нет пиксель-шрифта, используется системный")
	return ThemeDB.fallback_font
```

---

## 5. Правила компонента (то, что делает этапы 13–15 быстрыми)

Каждый компонент в `ui/components/`:

1. **`setup(...)` типизирован и вызывается извне.** Никаких `_ready`, лезущих в `Game`/`Events`. Приёмка промпта: «ни один компонент не обращается к Game/Events/sim».
2. **Сигналы наружу, а не вызовы наружу.** `signal value_picked(policy: int, v: int)`, не `Game.cmd_set_policy(...)`.
3. **Реакция на смену темы:**
```gdscript
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_apply_theme()

func _apply_theme() -> void:
	# Кэшируем то, что рисуем в _draw — get_theme_* в _draw дорого
	_c_ink = get_theme_color("font_color", "Label")
	_font = get_theme_font("font", "Label")
	_font_size = get_theme_font_size("font_size", "Label")
	queue_redraw()
```
⚠️ **`get_theme_*` внутри `_draw()` — заметная стоимость** (поиск по цепочке тем на каждый вызов). Кэшировать по `NOTIFICATION_THEME_CHANGED`. Прямо касается `TideGauge` (этап 13), который рисуется целиком в `_draw`.

4. **`mouse_filter` — самая частая причина «кнопка не нажимается».**
   - `MOUSE_FILTER_STOP` (дефолт у `Button`) — ест событие;
   - `MOUSE_FILTER_PASS` — обрабатывает и пропускает дальше;
   - `MOUSE_FILTER_IGNORE` — прозрачен для мыши.
   **Правило: у декоративных `Control`-контейнеров и фонов панелей ставить `IGNORE`**, иначе они перехватят тап, предназначенный миру. Полноэкранный `Control` с дефолтным `STOP` поверх мира — гарантированно сломает всё управление на этапах 13–14.

5. **Размеры — из токенов, не из инспектора.** `custom_minimum_size = Vector2(UITokens.TOUCH_MIN, UITokens.TOUCH_MIN)` в `_ready`. Тогда изменение `TOUCH_MIN` меняет все цели касания разом (нужно этапу 16).

---

## 6. Радиал: своя реализация, что важно технически

Промпт требует свою реализацию (до 6 слотов, тап или drag-в-сторону+отпуск, геймпад-стик).

**Готовые аналоги для сверки подхода** (не для копирования — лицензии и лишние зависимости):
- [ericanderson2/radial-menu-godot](https://github.com/ericanderson2/radial-menu-godot) — рисование через `_draw()`, ближе всего к нашему случаю;
- [jesuisse/godot-radial-menu-control](https://github.com/jesuisse/godot-radial-menu-control) — темизируемый, с подменю;
- шейдерная реализация из Asset Library — быстрее, но нам не нужен перф.

**Ключевая математика (одна формула, из которой всё следует):**
```gdscript
func _sector_at(local_pos: Vector2) -> int:
	var v: Vector2 = local_pos - _center
	if v.length() < DEAD_ZONE:
		return -1                                    # центр = отмена
	# angle() даёт -PI..PI, где 0 = вправо. Приводим к 0..TAU с началом СВЕРХУ:
	var a: float = fposmod(v.angle() + TAU * 0.25, TAU)
	return int(a / (TAU / float(_slots.size())))
```
⚠️ **`fposmod`, а не `fmod`**: `fmod` для отрицательных даёт отрицательное, и верхний-левый сектор будет отдавать −1.
⚠️ **Мёртвая зона в центре обязательна** — иначе при тапе точно в центр сектор выбирается случайно от дрожания пальца.

**Один жест «тап-или-свайп»:** обрабатывать по `InputEventScreenTouch(pressed=false)` / `InputEventMouseButton(released)`: если палец не сдвинулся дальше `DEAD_ZONE` — это тап по слоту под пальцем; если сдвинулся — это выбор сектора направления. **Один обработчик отпускания на оба случая**, не два режима.

**Геймпад:** сектор от `Input.get_vector("ui_left","ui_right","ui_up","ui_down")` той же формулой, подтверждение — `A`. Ноль дополнительного кода.

---

## 7. `InputService`: почему нода, а не автолоад

Промпт 12 п.5 требует ноду в `Main`, не автолоад. Технически это правильно: автолоад получал бы `_input` **раньше** всего GUI и ел бы события у панелей. Нода в дереве получает их в порядке дерева и может корректно уступать `Control`-ам.

Подробности распознавания жестов, пинча и мультитача — **doc 20**.

---

## 8. Витрина `_gallery.tscn` — не «приятный бонус», а инструмент

Она окупается на этапах 13–15: любую правку токенов видно за 3 секунды вместо запуска игры и доигрывания до нужной панели.

**Что в ней должно быть обязательно:**
- каждый компонент во **всех** состояниях (normal/hover/pressed/disabled/**focus**);
- обе локали — кнопка переключения `TranslationServer.set_locale()`, чтобы сразу видеть, что русский текст на 20% длиннее и вылезает (приёмка этапа 19 п.6, а поймать можно уже здесь);
- слайдер `content_scale_factor` 75–150% (приёмка этапа 15) — тут же видно, что ломается;
- тёмный/светлый фон-подложка, чтобы проверять читаемость.

**Это ускоритель, который окупается трижды. Не сокращать.**

---

## 9. Чек-лист приёмки этапа 12

- [ ] Смена одного значения в `tokens.gd` + Run билдера меняет вид **всех** компонентов; ни одна `.tscn` не тронута.
- [ ] Фокус ходит по всем интерактивным элементам Tab'ом и виден.
- [ ] Все подписи через `tr()`; переключение локали в витрине меняет текст.
- [ ] Радиал работает мышью (удержание ПКМ) и одним жестом тап-свайпа при `emulate_touch_from_mouse`.
- [ ] Ни один компонент не упоминает `Game`, `Events`, `sim` (grep по `ui/components/`).
- [ ] Пиксель-шрифт не мылит на 100% и на 150% `content_scale_factor` (проверить `keep_rounding_remainders=false`).
- [ ] Полноэкранные декоративные `Control` имеют `mouse_filter = IGNORE`.
- [ ] Тема назначена на корневые `Control` внутри каждого `CanvasLayer` (каскад).

---

## Источники

- [Theme (Godot 4.7)](https://docs.godotengine.org/en/stable/classes/class_theme.html) — `set_type_variation`, сеттеры, каскад
- [StyleBoxFlat](https://docs.godotengine.org/en/stable/classes/class_styleboxflat.html) — `anti_aliasing`, corner radius, border
- [Control](https://docs.godotengine.org/en/stable/classes/class_control.html) — `theme_type_variation`, `mouse_filter`, `NOTIFICATION_THEME_CHANGED`
- [Multiple resolutions](https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html) — font oversampling включён по умолчанию, `content_scale_factor`
- [godot#71046 «Font is blurry in Godot 4»](https://github.com/godotengine/godot/issues/71046) и обсуждения — `keep_rounding_remainders = false`, subpixel positioning disabled
- [ericanderson2/radial-menu-godot](https://github.com/ericanderson2/radial-menu-godot) — радиал через `_draw()`
- [jesuisse/godot-radial-menu-control](https://github.com/jesuisse/godot-radial-menu-control) — темизируемый радиал с подменю
