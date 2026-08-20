# 22 — Экраны, роутер, локализация, настройки

**Для этапов:** 15 (весь), 19 п.6 (прогон обоих языков), 16 (масштаб UI).
**Дата ресерча:** 2026-08-21. **Движок:** Godot 4.7.x stable.

---

## 1. Роутер: не перезагружать игровую сцену

Промпт 15 п.1: «Game-сцена не перезагружается между панелями». Технически это значит — **не использовать `change_scene_to_*` внутри игры вообще.**

`SceneTree.change_scene_to_file/packed` выгружает текущую сцену и создаёт новую **в конце кадра**. Все View, кэши HUD, подписки — умирают. Для перехода «меню ↔ игра» это допустимо, для «игра ↔ панель итогов» — катастрофа.

**Схема, которая работает:**
```
Main (Control)
├── WorldContainer      ← мир; visible = false в меню
├── HUDLayer            ← visible = false вне игры
├── PanelLayer
├── ScreenLayer (CanvasLayer, layer=40)
│   ├── MainMenu   (Control, visible=false)
│   ├── DraftPanel (Control, visible=false)
│   ├── CycleSummary
│   ├── RunSummary
│   ├── Journal
│   ├── Settings
│   └── PausePanel
└── DebugLayer
```
Роутер — **конечный автомат по видимости**, а не по сценам:
```gdscript
enum Screen { BOOT, MAIN_MENU, GAME, DRAFT, CYCLE_SUMMARY, RUN_SUMMARY, JOURNAL, SETTINGS, PAUSE }

func goto(s: Screen) -> void:
	if s == _current: return
	_exit(_current)
	_current = s
	_enter(s)
```
**Плюсы:** мгновенные переходы, живой мир под полупрозрачным экраном итогов, никаких потерь состояния.
**Минус:** всё в памяти сразу. Для 8 экранов из `Control`-ов это десятки килобайт — неважно.

⚠️ **`MainMenu` — исключение.** Он показывается до создания мира. Его можно держать в том же дереве: `WorldContainer.visible = false` и мир просто не создан (`Game.world == null`). **Отдельная сцена меню не нужна и создаст проблему «где живёт роутер».**

**Фон меню:** промпт прямо запрещает живой мир («слишком дорого») — статичная картинка-заглушка. Согласен и технически: живой мир в меню означал бы тикающую симуляцию без забега.

---

## 2. Автопауза экранов: переиспользовать счётчик

Драфт (этап 10), CycleSummary, RunSummary, Pause — все ставят паузу. Использовать `Game.push_pause()/pop_pause()` из doc 21 §5, **а не `cmd_set_speed(0)` напрямую**. Иначе закрытие CycleSummary снимет паузу, поставленную драфтом.

⚠️ **Драфт паузит сам sim** (промпт 10 п.3: «эмит `draft_ready` + автопауза»). Значит UI **не должен** паузить второй раз — только показать панель. `pop_pause` при выборе карты делает `Game.cmd_pick_card`.

---

## 3. Локализация: что реально ломается

### 3.1 Поведение `tr()`
- Ключ не найден → **возвращается сам ключ**. Отсюда «сырые ключи на экране» из приёмки этапа 19. Ловится тестом (doc 14 §4.1) и глазами в витрине.
- `tr("KEY")` ищет в текущей локали, потом в фолбэк-локали (`internationalization/locale/fallback`, по умолчанию `en`).
- **Форматирование — после перевода:** `tr("CYCLE_OF").format({"n": n, "total": 12})` при значении `"Цикл {n}/{total}"`. Или `%`-формат: `tr("CYCLE_OF") % [n, 12]`. **Второй вариант хрупок** — если в русском и английском разный порядок подстановок, `%`-формат сломается. **Рекомендация: `String.format` с именованными ключами.**

### 3.2 Смена языка на лету
```gdscript
TranslationServer.set_locale("en")
```
- `Label`/`Button` со свойством `text`, установленным как **ключ**, перепереводятся автоматически по `NOTIFICATION_TRANSLATION_CHANGED`.
- **Строки, собранные в коде, — нет.** `label.text = tr("CYCLE_OF").format(...)` после смены языка останется старым.

**Решение — один паттерн на весь проект:**
```gdscript
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh_texts()

func _refresh_texts() -> void:
	cycle_label.text = tr("CYCLE_OF").format({"n": _cycle, "total": Balance.CYCLES_PER_RUN})
	# ...все динамические строки этого узла
```
⚠️ **Каждый узел с динамическим текстом обязан иметь `_refresh_texts()`** и вызывать его и из `_notification`, и из мест обновления данных. Приёмка «смена языка на лету меняет все строки» проверяет именно это.

- `Control.auto_translate_mode` (`INHERIT`/`ALWAYS`/`DISABLED`) — выключать (`DISABLED`) для узлов, где текст **не** ключ: имена агентов, числа, ввод сида. Иначе имя «Тарас» будет прогоняться через переводчик и в логах появится шум о ненайденных ключах.

### 3.3 CSV
- Заголовок `keys,ru,en`; кодировка **UTF-8 без BOM**; строки с запятыми — в кавычках.
- Делимитер фиксируется в `.import`-файле. ⚠️ Excel в русской локали сохраняет с `;` — если CSV правит человек, записать это в `assets/i18n/README.md`.
- Godot генерирует `strings.ru.translation` / `strings.en.translation`; они **игнорируются в git** (генерируются при импорте), а в `internationalization/locale/translations` прописываются оба.
- ⚠️ **Пустая ячейка = пустая строка**, а не фолбэк. Не переведённый ключ лучше оставить с английским текстом, чем пустым — иначе на экране будет пустое место, которое трудно заметить.

### 3.4 Длина строк
docs/02 и промпт 19: русский длиннее английского на ~20%. Технически: **не задавать `Control` фиксированную ширину под текст.** Использовать `HBoxContainer` + `size_flags_horizontal = SIZE_EXPAND_FILL`, `Label.autowrap_mode = AUTOWRAP_WORD_SMART`, `clip_text` для однострочных.
**Проверять в витрине (doc 19 §8) переключателем локали — до того, как панель попадёт в игру.**

---

## 4. Настройки: файл, масштаб, применение

```gdscript
## autoload/settings.gd
const PATH: String = "user://settings.json"

var master_db: float = 0.0
var music_db: float = 0.0
var sfx_db: float = 0.0
var ui_scale: float = 1.0            # 0.75..1.5
var locale: String = "ru"
var hints_enabled: bool = true
var haptics: bool = true
var default_zoom: int = 0

func apply() -> void:
	TranslationServer.set_locale(locale)
	get_tree().root.content_scale_factor = _auto_dpi_scale() * ui_scale
	AudioService.apply_volumes()
```

**Почему JSON, а не `ConfigFile`:** docs/02 §6 запрещает `ConfigFile` для пользовательских файлов (значения могут быть Object → исполнение кода). `settings.json` пользователь может править руками — значит на него распространяется то же правило. Тот же атомарный писатель, что и для сейва (doc 18 §4).

**`content_scale_factor`:**
- меняется в рантайме, применяется сразу;
- ⚠️ **снапить к ступеням 0.25** (doc 20 §7) — иначе пиксель-шрифт мылит;
- ⚠️ **не путать с `stretch/scale`**: `content_scale_factor` — множитель поверх stretch-режима, задаётся на `Window`/root.

**Сброс профиля — двойное подтверждение** (промпт). Технически: удаление `user://profile.json` + очистка `Meta` в памяти + `Meta.save_profile()`. ⚠️ **Не забыть очистить in-memory состояние** — иначе первый же автосейв запишет профиль обратно.

---

## 5. `Journal`: TabContainer и сетка

- `TabContainer` берёт заголовки вкладок из **имён дочерних узлов**. Значит имена нод должны быть ключами перевода? Нет — `TabContainer.set_tab_title(i, tr("TAB_UNLOCKS"))` в `_refresh_texts()`. Имена нод остаются английскими и служебными.
- Сетка 12 карточек — `GridContainer` с `columns`, пересчитываемым от ширины:
```gdscript
func _on_resized() -> void:
	grid.columns = clampi(int(size.x / 180.0), 2, 4)
```
Это дешевле, чем два лейаута для телефона и десктопа.
- **Подсветка новых разблокировок** после `RunSummary`: `Meta` хранит `seen_unlocks: Array[String]`; новое = `unlocked - seen`. Помечать просмотренными при закрытии Журнала.

---

## 6. `HintCard`: очередь уроков

```gdscript
const HINTS: Dictionary[String, String] = {
	"first_wet_wood":   "HINT_WET_WOOD",
	"first_storm":      "HINT_STORM",
	"first_visit":      "HINT_VISIT",
	"first_spoil":      "HINT_SPOIL",
	"first_flooded_storage": "HINT_FLOODED_STORAGE",
}
var _queue: Array[String] = []

func trigger(id: String) -> void:
	if not Settings.hints_enabled: return
	if Meta.hints_shown.has(id): return
	if _queue.has(id): return
	_queue.append(id)
	Meta.hints_shown.append(id)      # помечаем сразу: иначе при закрытии игры повторится
	Meta.mark_profile_dirty()
	if not _showing: _show_next()
```
⚠️ **Помечать показанным в момент постановки в очередь, а не показа** — иначе выход из игры с непоказанной подсказкой приведёт к её повторению каждый запуск.

⚠️ **Не перекрывать тосты** (промпт): правый верх для подсказок, правый низ — тосты и кнопка отзыва. Разные `MarginContainer`-ы с непересекающимися якорями.

**Триггеры приходят от `Events`.** ⚠️ Событий «первый мокрый плавник» и «первая порча» в контракте docs/02 §3.2 нет. Значит либо (а) вывести из существующих (`storage_changed` + запрос), либо (б) добавить поле в `cycle_ended.report`. **Рекомендация (б): отчёт цикла и так содержит потери — HintCard читает его.** Не расширять контракт сигналов ради подсказок.

---

## 7. `RunSummary` и «подъезд» чисел

`tween_method` (doc 21 §3, п.6). Три технических требования:
1. **Одна `Tween` на весь экран**, с `chain()` между строками — а не по твину на строку, иначе они пойдут вразнобой.
2. **Пропуск анимации по тапу:** `tw.kill()` + мгновенная установка финальных значений. Обязательно — иначе на 20-м забеге игрок возненавидит экран.
3. **Итог считает sim, а не UI.** UI только показывает `report` из `run_ended`. Пересчёт в UI = второй источник правды и расхождение с сейвом.

---

## 8. Чек-лист приёмки этапа 15

- [ ] Полная петля: меню → забег → 12 циклов → итог → журнал → покупка → новый забег с эффектом.
- [ ] Смена языка на лету меняет **все** строки, включая собранные в коде (проверить каждый экран).
- [ ] Ни одного сырого ключа (`UPPER_SNAKE` на экране) — грепом по логу + глазами.
- [ ] Масштаб UI 75/100/150% не ломает лейаут на 1280×720 и 1920×1080.
- [ ] `Continue` восстанавливает игру визуально и по данным.
- [ ] Автопауза не «залипает» при наложении драфта и банера (счётчик глубины).
- [ ] Подсказки не повторяются после перезапуска.
- [ ] Экран итогов пропускается тапом.
- [ ] Game-сцена ни разу не перезагружается между экранами (лог `_ready` мира — один раз за забег).

---

## Источники

- [Internationalizing games](https://docs.godotengine.org/en/stable/tutorials/i18n/internationalizing_games.html) — `tr()`, поведение при отсутствии ключа
- [Importing translations](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_translations.html) — CSV, делимитер, генерация `.translation`
- [TranslationServer](https://docs.godotengine.org/en/stable/classes/class_translationserver.html) — `set_locale`
- [Control](https://docs.godotengine.org/en/stable/classes/class_control.html) — `auto_translate_mode`, `NOTIFICATION_TRANSLATION_CHANGED`
- [Multiple resolutions](https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html) — `content_scale_factor`
- [SceneTree](https://docs.godotengine.org/en/stable/classes/class_scenetree.html) — `change_scene_to_packed` (и почему мы её не используем внутри игры)
