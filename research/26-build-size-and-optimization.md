# 26 — Размер сборки и оптимизация в конце проекта

**Для этапов:** 19 (стабилизация и релиз), частично 16 (пресеты экспорта), 18 (профилирование).
**Дата ресерча:** 2026-08-21. **Движок:** Godot 4.7.x stable, рендерер Mobile, только 2D.
Проверено по `docs.godotengine.org/en/stable` (баннер «Godot Engine 4.7 documentation»), трекеру issues и практическим отчётам сообщества. Помеченное `⚠️ НЕ ПОДТВЕРЖДЕНО` — вывод из старых источников или инженерная оценка; проверять на своей сборке.

---

## 0. Главное за 30 секунд

Порядок работ — строго по возрастанию цены и риска. **Не начинать с конца.**

| Уровень | Что | Выигрыш | Риск | Время |
|---|---|---|---|---|
| **0** | Настройки экспорта и импорта | pck: −40…−70% | нулевой | час |
| **1** | `strip` + архив дистрибутива `7z -mx9` | −5…10× на символах, −30% на архиве | нулевой | 20 мин |
| **2** | Кастомный шаблон экспорта (`scons`) | 92 МБ → ~17–21 МБ | средний | день + пересборка при каждом апдейте движка |
| **✗** | UPX | −70% на диске | **высокий** | — |

**Вердикт по нашему проекту:** уровни 0 и 1 делать обязательно на этапе 19. Уровень 2 — **опционально, и только если размер реально мешает** (мобильный сторе, itch с лимитом). UPX — **не использовать**, причины в §4.

⚠️ **Ключевая цифра:** движок в билде весит десятки мегабайт, наш контент (пиксель-арт 32×32, WAV-заглушки, ~70 крошечных `.tres`, GDScript) — **единицы мегабайт**. То есть 90% размера — это шаблон экспорта, и уровни 0–1 его почти не трогают. Об этом надо помнить, прежде чем тратить день на уровень 2.

---

## 1. Из чего состоит билд

```
tidebound.exe   = [ шаблон экспорта (движок) ] + [ tidebound.pck, если Embed PCK ]
tidebound.pck   = импортированные ресурсы + скрипты + project.binary
```

**Что в pck попадает, а что нет:**

- **Исходники ассетов НЕ попадают.** `.png` импортируется в `.ctex`, `.wav` — в свой формат, `.csv` — в `.translation`. В pck едет только импортированная форма. Значит слои `.aseprite`, эталонные `.wav` 44 кГц и прочее в `assets/` размер билда не раздувают — но **только если они лежат как источники импорта, а не как «просто файлы»**.
- **Файлы и папки, чьё имя начинается с точки, не попадают никогда** (док Exporting projects) — это защита от `.git`.
- **GDScript попадает в виде сжатых бинарных токенов** (по умолчанию, см. §2.1), а не текстом.
- `project.godot` конвертируется в `project.binary`.

**Как проверить, что реально уехало в билд** (обязательный пункт приёмки этапа 19):
```bash
godot --headless --export-pack "Windows Desktop" build/audit.pck
ls -l build/audit.pck
```
Содержимое pck читается сторонним [gdsdecomp](https://github.com/GDRETools/gdsdecomp) — им стоит один раз посмотреть **свой** билд и убедиться, что `tests/`, `tools/`, `debug/` и черновики арта туда не уехали. Это единственный надёжный способ; «на глаз по фильтрам» ошибиться легко.

---

## 2. Уровень 0: настройки, которые ничего не стоят

### 2.1 GDScript Export Mode

Опция пресета экспорта, три значения:
- **Text** — plain text, для отладки;
- **Binary tokens** — компиляция в бинарные токены, «makes loading the scripts a lot faster»;
- **Compressed binary tokens** — **значение по умолчанию**: токены + сжатие, меньше размер, быстрая загрузка, как бонус — обфускация.

**Ничего менять не надо, но надо знать:** если сборка падает с непонятной ошибкой парсинга только в экспорте, а в редакторе всё зелено — временно переключить в **Text** и проверить (известные регрессии: [#94150](https://github.com/godotengine/godot/issues/94150), [#113577](https://github.com/godotengine/godot/issues/113577)).

⚠️ **Не путать со «защитой кода».** Ключ шифрования pck лежит в бинарнике открытым 32-байтовым блобом и достаётся публичными инструментами за секунды. Шифрование pck **не** защищает от реверса и **увеличивает** риск ложных срабатываний антивируса. Для нашего проекта не нужно.

### 2.2 Фильтры экспорта — то, что действительно вырезает лишнее

В пресете, вкладка Resources:

```
Filters to exclude files/folders from project:
    tests/*, tools/*, debug/*, research/*, *.md, *.aseprite, *.psd, *.xcf, *.wav.bak
```
Плюс `Export Mode` — оставить **«Export all resources»** (режимы «selected scenes/resources» ломаются при динамическом `load()` по строке, а у нас `DB` грузит `.tres` сканированием папки — см. research/14 §4).

⚠️ **`res://debug/*` в exclude — это второй рубеж к рантайм-гейту `OS.is_debug_build()`** (research/13 §3). Если `preload` дебаг-панели всё же остался в коде, экспорт **упадёт с ошибкой** — и это правильно: лучше сломанный экспорт, чем дебаг-панель в релизе.

⚠️ **`*.md` исключать осторожно:** если `assets/sfx/README.md` где-то читается кодом — сломается. У нас не читается.

**Проверка после настройки:** сравнить размер pck до и после. Если не изменился — фильтры не сработали (частая причина: путь написан как `res://tests/*` вместо `tests/*`).

### 2.3 Импорт текстур: пиксель-арт

Док importing_images (4.7) прямо: **Lossless — «This is also the recommended setting for pixel art»**.

| Опция | Значение для нас | Почему |
|---|---|---|
| `Compress > Mode` | **Lossless** | VRAM-компрессия разрушает пиксель-арт; Lossy — тем более |
| `Compress > High Quality` | off | относится к VRAM-режимам |
| `Mipmaps > Generate` | **off** | мипмапы = блюр при уменьшении + ~33% к размеру текстуры |
| `Detect 3D > Compress To` | **Disabled** | ⚠️ см. ниже |
| `Process > Fix Alpha Border` | off | нужен для 3D/фильтрации, на Nearest вредит |
| `Process > Premultiply Alpha` | off | ломает обычный alpha-blend |
| `Process > Size Limit` | 0 | у нас нет больших текстур |

⚠️ **`Detect 3D` — главная ловушка.** Док: *«If this happens, several import options are changed so the texture flags are friendlier to 3D. Mipmaps are enabled and the compression mode is changed to VRAM Compressed.»* То есть **движок сам молча переимпортирует текстуру в VRAM-компрессию**, если она хоть раз попала в 3D-контекст. У нас 3D нет, но `Detect 3D` лучше выключить в **дефолтах импорта проекта** (Project Settings → Import Defaults), чтобы это не могло произойти случайно на этапе 18 при добавлении атласа.

**Как выставить один раз на весь проект:** Project → Project Settings → Import Defaults → `texture` — там задаются дефолты для всех новых импортов. Существующие `.import`-файлы придётся поправить руками или удалить папку `.godot/imported` и переимпортировать.

### 2.4 Импорт звука

Наши плейсхолдеры — 16-бит моно 22050 Гц (research/23 §6), это уже минимально. Для реальных ассетов:

| Что | Формат | Настройки |
|---|---|---|
| Короткие SFX (колокол, тап, всплеск) | **WAV** | `Compress > Mode = Quite OK Audio (QOA)`, `Force > Mono = on`, `Force > Max Rate = 22050` |
| Музыка, эмбиент-лупы | **Ogg Vorbis** | док: «music, speech, and long sound effects» |

**QOA — дефолтный режим сжатия WAV в 4.x.** Док: *«reduces file size a bit more than IMA ADPCM and the quality decrease is much less noticeable»*; ~17 КБ на секунду моно 44 кГц — сопоставимо с Ogg 128 Кбит/с, но **существенно дешевле по CPU**. Для нашего слоя SFX это правильный компромисс.

⚠️ **`Force > Mono` для эмбиента — нет.** Вертикальный кроссфейд «верх/низ» (research/23 §3) выигрывает от стерео-панорамы. Моно — только точечные SFX.

⚠️ **`Edit > Loop Mode`** для эмбиент-лупов ставить в `Forward` **в настройках импорта**, а не в коде: иначе после замены файла художником настройка потеряется.

### 2.5 Шрифты

Один пиксель-шрифт с кириллицей (research/19 §4) — это десятки килобайт. Но:
- ⚠️ **Не тащить `.ttf` с полным юникодом** ради «на всякий случай»: шрифт с CJK — это 10–20 МБ, больше всего остального контента вместе взятого.
- Если понадобится fallback-шрифт — брать урезанный по диапазонам (subset), а не полный.
- `multichannel_signed_distance_field = off` (research/19 §4) заодно экономит место: MSDF-атлас крупнее растрового.

### 2.6 PCK или ZIP, Embed или рядом

| | PCK (дефолт) | ZIP |
|---|---|---|
| Размер | больше (без сжатия) | меньше |
| Скорость чтения | быстрее | медленнее |
| Моддинг | сложнее | проще |

Док прямо описывает этот компромисс. **Наш выбор — PCK:** контент маленький, выигрыш ZIP в мегабайтах несущественен, а замедление загрузки — заметно.

**Embed PCK (вшить pck в exe):**
- ✅ один файл вместо двух — аккуратнее для дистрибуции;
- ⚠️ **лимит ~3.89 ГБ** на итоговый exe (док exporting_for_windows) — нам не грозит;
- ❌ **повышает шанс ложного срабатывания антивируса**: Windows Defender эвристически подозревает неподписанный бинарник с прицепленным сжатым блобом — это сигнатура упаковщиков вроде UPX;
- ❌ **несовместим с UPX** (§4).

**Рекомендация: для Steam/itch — Embed PCK включён** (один файл, а магазины дают доверие), **для прямой раздачи exe — выключить** и класть `.pck` рядом.

**Радикальное лечение ложных срабатываний — подпись кода.** В пресете Windows есть секция Code Signing (`Enabled`, `Identity`), поддерживаются `signtool` (Windows SDK) и `osslsigncode` (не-Windows), пароль через переменные `GODOT_WINDOWS_CODESIGN_IDENTITY` / `GODOT_WINDOWS_CODESIGN_PASSWORD`. Сертификат стоит денег, но это единственное, что убирает предупреждения SmartScreen надёжно. Для беты — не обязательно, **записать в backlog**.

---

## 3. Уровень 1: strip и упаковка дистрибутива

### 3.1 `strip`

```bash
strip build/tidebound.x86_64        # Linux
strip build/tidebound.exe           # Windows, если шаблон собран MinGW
```
Док optimizing_for_size: экономия «very high» (**5–10× сокращение**), цена — пропадают бэктрейсы при крашах и имена функций в профайлере.

⚠️ **Не работает для MSVC, Android и Web** — там вместо этого флаг сборки `debug_symbols=no`.
⚠️ **Официальные release-шаблоны уже собраны без символов** — `strip` на них ничего не даст. Эффект появляется только на **своём** шаблоне (уровень 2), собранном без `debug_symbols=no`.
⚠️ **Не стриптить debug-сборку**, которую раздаёте тестерам: бэктрейсы из репортов ценнее мегабайтов.

### 3.2 Архив дистрибутива

Док рекомендует 7-Zip с максимальным сжатием:
```bash
7z a -mx9 tidebound-win64.zip build/
```
Экономия «1–5 МБ» в среднем, «десятки мегабайт» для крупных проектов. Это бесплатно и не влияет на игру. Для itch.io — единственный формат раздачи.

---

## 4. UPX — почему нет

Соблазн понятен: сообщество отчитывается о **16.7 МБ → 5.37 МБ**. Три причины не делать:

1. **Ломает Embed PCK.** UPX упаковывает весь `.exe`; распаковка идёт в память, а Godot читает вшитый pck **со структуры файла на диске**. Результат — «missing PCK file» на старте ([godot-docs#3093](https://github.com/godotengine/godot-docs/issues/3093), [godot#18404](https://github.com/godotengine/godot/issues/18404)). Обойти можно только раздачей `.pck` рядом — и тогда «один аккуратный файл», ради которого всё затевалось, теряется.
2. **Антивирусы.** UPX массово используется малварью; упакованный неподписанный бинарник — почти гарантированный флаг у Defender и мелких антивирусов. Для игры, которую скачивают с itch, это прямые потери игроков.
3. **Плата в рантайме.** Распаковка в память даёт **~+20 МБ RSS** и задержку старта. Мы экономим на диске, платя оперативной памятью — для мобильного/Deck-таргета это плохой размен.

**Вердикт: не использовать. Если размер критичен — уровень 2 даёт больше и без побочных эффектов.**

---

## 5. Уровень 2: кастомный шаблон экспорта

### 5.1 Что это даёт (измерения сообщества, Godot 4.5, Windows)

| Шаг | Размер, МБ | Флаг |
|---|---|---|
| дефолт | 92.8 | — |
| `optimize="size"` | 53.6 | |
| `disable_3d="yes"` | 44.0 | |
| fallback text server | 41.9 | `module_text_server_adv_enabled="no"` |
| `disable_advanced_gui="yes"` | 39.7 | |
| убрать Vulkan/OpenXR/minizip | 33.6 | |
| `modules_enabled_by_default="no"` | 29.8 | |
| build profile (отсечение классов) | 21.0 | `build_profile=...` |
| **итог у автора** | **16.7** | + `lto`, `strip` |

⚠️ Цифры — из [практического отчёта popcar](https://popcar.bearblog.dev/how-to-minify-godots-build-size/), не из официальной доки. Порядок величин совпадает с официальной таблицей «space savings», но **конкретные значения зависят от версии и набора модулей** — свои надо мерить самому.

### 5.2 Флаги, проверенные по официальной доке

```bash
scons platform=windows target=template_release arch=x86_64 \
      optimize=size lto=full debug_symbols=no \
      disable_3d=yes \
      module_text_server_adv_enabled=no module_text_server_fb_enabled=yes \
      modules_enabled_by_default=no \
      module_freetype_enabled=yes module_svg_enabled=no \
      build_profile=/path/to/tidebound.gdbuild
```

| Флаг | Экономия (док) | Замечание |
|---|---|---|
| `optimize=size` | High | для Web уже дефолт |
| `lto=full` | High | ⚠️ **требует 6–8 ГБ RAM** и заметно дольше линкуется |
| `debug_symbols=no` | Very high | для MSVC/Android/Web — вместо `strip` |
| `disable_3d=yes` | Moderate (~15%) | ⚠️ **также отключает 2D-навигацию** ([#89185](https://github.com/godotengine/godot/issues/89185)); tools должны быть отключены |
| `disable_advanced_gui=yes` | Moderate | ⚠️ **нам, вероятно, нельзя — см. §5.4** |
| `module_text_server_adv_enabled=no` + `module_text_server_fb_enabled=yes` | High | **оба флага обязательны**, иначе текст не рисуется вовсе |
| `modules_enabled_by_default=no` | Very low → moderate | дальше включать нужное поимённо |
| `build_profile=…` | зависит | отсечение неиспользуемых классов |

**Про text server — прямое попадание в наш случай.** Док: fallback-сервера достаточно для **Latin/Greek/Cyrillic**. У нас ровно ru + en. То есть самая «дорогая» экономия достаётся нам без потерь.
⚠️ Проверить после сборки: русские строки, `String.format`, ширина текста в панелях. Fallback не умеет сложную типографику (лигатуры, BiDi, шейпинг) — нам не нужно, но убедиться глазами.

### 5.3 Build profile (`.gdbuild`) — 4.7

Официальная страница «Using the engine compilation configuration editor» (4.7):
- **Меню: Project → Tools → Engine Compilation Configuration Editor.**
- Формат — **JSON, расширение `.gdbuild`** (в 4.4 и раньше было `.build`), поля: `disabled_build_options`, `disabled_classes`, `type: "build_profile"`.
- Кнопка **«Detect from project»** сканирует проект (секунды–минуты) и **перезаписывает ручные галки**.
- Передаётся в сборку: `scons target=template_release build_profile=/path/to/profile.gdbuild`.
- ⚠️ **Прямая цитата-предупреждение:** *«Unchecking features in this dialog will not reduce binary size directly on export.»* Профиль сам по себе ничего не даёт — нужен пересобранный шаблон.

⚠️ **Автодетект ненадёжен.** Док перечисляет, чего он не видит: процедурно созданные скрипты, `Expression`, GDExtension, внешние PCK. Практические отчёты добавляют: **вырезает нужные классы вроде `MainLoop` и `TextServer`**. Порядок работы: `Detect from project` → **вручную вернуть галки** → собрать → **прогнать полный забег и все экраны** → повторить.

**Для нас особенно рискованно:**
- `DB` грузит `.tres` через `load()` по строке пути (research/14 §4) — детектор классов ресурсов может это не увидеть;
- дебаг-панель подписывается на сигналы рефлексией (research/13 §6);
- тема грузится по пути в рантайме.

**Правило: после сборки кастомного шаблона обязателен ручной полный прогон** — меню, забег 12 циклов, все панели, оба языка, сохранение/загрузка. Автотесты этого не покроют: они гоняют `sim/`, а вырезаются классы `scene/`.

### 5.4 Что нам можно и нельзя отключать

| Возможность | Нужна TIDEBOUND? | Решение |
|---|---|---|
| 3D | нет | `disable_3d=yes` ✅ |
| Навигация (в т.ч. 2D) | нет — свой граф на `AStar2D` (research/12 §4) | ✅ отключаемо; ⚠️ `AStar2D` — это `core`, не `NavigationServer`, он остаётся |
| Физика 2D/3D | нет (docs/02 §1) | ✅ |
| Advanced text server | нет (ru/en) | ✅ заменить на fallback |
| **Advanced GUI** | **скорее да** | ⚠️ **см. ниже** |
| Vulkan | нет (рендерер Mobile → тоже Vulkan!) | ❌ **не трогать**, см. ниже |
| OpenXR, WebXR, mobile_vr | нет | ✅ |
| Мультиплеер, ENet, WebRTC, WebSocket, UPnP | нет | ✅ |
| Theora, WebM (видео) | нет | ✅ |
| Vorbis/Ogg | **да** (музыка) | ❌ оставить |
| minimp3 | нет (не используем mp3) | ✅ |
| RegEx | ⚠️ проверить грепом по проекту | по факту |
| Noise, CSG, GridMap, Raycast, VHACD, meshoptimizer, squish, basis_universal | нет | ✅ |
| Форматы картинок: bmp, dds, hdr, ktx, tga, tinyexr | нет (только PNG/WebP) | ✅ |
| SVG | ⚠️ иконки движка/редактора; в шаблоне обычно не нужен | проверить |
| FreeType | **да** (шрифты) | ❌ оставить |
| JSONRPC | нет | ✅ |
| mbedTLS | нет (нет сети) | ✅, но ⚠️ проверить, не тянет ли что-то ещё |
| zip / minizip | нет, если pck (не ZIP) | ✅ при формате PCK |

⚠️ **Про Vulkan.** Рендерер Mobile в Godot 4 — это **Vulkan Mobile**, а не «мобильный API». Отключение Vulkan сломает игру на десктопе. Оставлять всегда. (Отчёты, где Vulkan убирают, — это Web-сборки, где используется OpenGL/WebGL.)

⚠️ **Про `disable_advanced_gui`.** Списки «что именно вырезается» в открытых источниках относятся к Godot 3 и включают `MarginContainer`, `PopupMenu`, `AcceptDialog`, `ConfirmationDialog`, `OptionButton`, `SpinBox`, `RichTextLabel`, `Tree`, `TextEdit`, `SplitContainer`, `ColorPicker`, `GraphEdit`. ⚠️ **НЕ ПОДТВЕРЖДЕНО для 4.7** — список менялся. Но у нас **точно используются**: `MarginContainer` (safe area, research/20 §7), `ConfirmationDialog` (`confirm_dialog` из промпта 12), `OptionButton` (выбор языка, промпт 15), возможно `ItemList` (история забегов) и `TabContainer` (Журнал).
**Вывод: `disable_advanced_gui=yes` для нас, скорее всего, неприменим.** Проверять надёжнее всего по исходникам движка своей версии: `grep -rn ADVANCED_GUI_DISABLED scene/`. Экономия «moderate» — не стоит переписывания половины UI.

### 5.5 Подключение своего шаблона и эксплуатация

1. Собранный бинарь положить куда угодно и указать путь в пресете: **Options → Custom Template → Release** (и **Debug**, если собрали и его).
2. ⚠️ **Пересобирать при каждом обновлении движка.** Шаблон, собранный на 4.7.1, с редактором 4.7.2 может не работать. Это постоянная стоимость владения — главный аргумент против уровня 2 на бете.
3. ⚠️ **Собирать в контейнере или на чистой машине.** Иначе билд зависит от локальных версий MinGW/MSVC/SDK, и «у меня собирается» перестаёт что-то значить. Официальные шаблоны собираются скриптами `godotengine/godot-build-scripts` в Docker — их же стоит взять, если дело дойдёт до релиза.
4. **Хранить `tidebound.gdbuild` и командную строку сборки в репозитории** (`tools/build_template.sh`). Иначе через месяц никто не вспомнит набор флагов.

---

## 6. Рантайм-оптимизация в конце проекта

### 6.1 Сначала измерить

Док CPU optimization: *«Focusing on bottlenecks allows us to concentrate our efforts on optimizing the areas which will give us the greatest speed improvement»*, профайлер **надо запускать и останавливать вручную**.

У нас уже есть два измерителя, заложенных раньше:
- **график времени тика** в дебаг-панели (research/13 §9), бюджет из docs/00 §16 — **2 мс на тик**;
- `Performance.get_monitor(...)` для нод/орфанов/памяти (research/24 §7).

**Порядок на этапе 19:** сначала снять цифры на 12-м цикле полного забега (худший случай: максимум построек, агентов, существ), потом решать, надо ли что-то делать. С высокой вероятностью — не надо: 6 агентов и ~40 построек при 10 Гц не создают нагрузки.

### 6.2 Настройки, которые стоит проверить

| Настройка | Значение | Почему |
|---|---|---|
| `application/run/max_fps` | **60** | без ограничения игра будет жарить GPU на 300+ fps в меню; на Deck/ноутбуке это батарея и шум |
| `display/window/vsync/vsync_mode` | Enabled | то же; отключать только для замеров |
| `rendering/anti_aliasing/quality/msaa_2d` | **Disabled** | пиксель-арт + MSAA = размытые кромки и лишняя работа |
| `rendering/anti_aliasing/quality/screen_space_aa` | Disabled | то же |
| `rendering/2d/shadow_atlas/size` | 1024 (вместо 2048) | у нас ≤8 светов (docs/00 §16), 2048 избыточно; читается **только при старте** |
| `rendering/environment/defaults/default_clear_color` | цвет фона игры | иначе кадр начинается с лишней заливки другим цветом |
| `physics/common/physics_ticks_per_second` | **60, не менять** | физику не используем, но на `_physics_process` висит аккумулятор сим-тика (research/11 §3); снижение до 30 сделает ввод и тик грубее |
| `physics/common/physics_jitter_fix` | **0** | подкрутка дельты вредит и камере, и аккумулятору (research/10 §2) |
| `rendering/textures/canvas_textures/default_texture_filter` | Nearest | уже стоит с этапа 00 |

⚠️ **`application/run/low_processor_mode` — НЕ включать.** Он предназначен для приложений, а не игр: движок засыпает между кадрами (`low_processor_mode_sleep_usec`). У нас непрерывная анимация воды, частицы и шейдеры — картинка станет дёрганой. Плюс есть отчёты, что в отдельных версиях он **увеличивает** нагрузку на пустой сцене ([#101058](https://github.com/godotengine/godot/issues/101058)). Для экономии батареи достаточно `max_fps` + vsync.

⚠️ Тактическая пауза (`Game.speed = 0`) **не снижает нагрузку**: мир не тикает, но рендер и шейдеры идут. Если понадобится экономить на паузе — снижать `Engine.max_fps` до 30 при `speed == 0`. ⚠️ Делать только если замеры покажут проблему: скачок fps заметен глазом.

### 6.3 Что оптимизировать в коде (и чего почти наверняка не надо)

Заложено раньше и должно быть проверено на этапе 19:
- пул задач перестраивается по событиям, а не каждый тик (research/16 §2);
- пути кэшируются по `graph_version` (research/15 §3);
- оверлеи и виджеты перерисовываются по событиям (research/13 §2.1, research/21 §2);
- призрак стройки дёргает sim только при смене клетки (research/17 §3);
- `get_theme_*` кэшируется по `NOTIFICATION_THEME_CHANGED` (research/19 §5).

**Чего не делать без замеров:** пулы объектов, упаковку состояния в `Packed*Array`, многопоточность, отказ от `Dictionary` в пользу массивов. Наш масштаб этого не требует, а детерминизм от таких правок страдает первым.

---

## 7. Чек-лист этапа 19 (релизная часть)

**Размер и содержимое:**
- [ ] Фильтры экспорта исключают `tests/`, `tools/`, `debug/`, исходники арта.
- [ ] `godot --headless --export-pack` + просмотр содержимого pck: ничего лишнего.
- [ ] Все текстуры — `Lossless`, mipmaps off, `Detect 3D` disabled (проверить `.import`-файлы грепом).
- [ ] SFX — QOA/mono/22050; музыка — Ogg; шрифт один, без CJK.
- [ ] GDScript Export Mode = Compressed binary tokens (дефолт, не сбит).
- [ ] Размер release-билда зафиксирован в `docs/backlog.md` как базовая линия.

**Сборка и раздача:**
- [ ] Release-пресеты собираются из CLI без ручных шагов.
- [ ] Дистрибутив архивируется `7z -mx9`.
- [ ] Решение по Embed PCK принято и записано (Steam/itch — да; прямая раздача — нет).
- [ ] UPX **не используется**; решение записано, чтобы не всплыло снова.
- [ ] Подпись кода — в backlog с оценкой стоимости.

**Рантайм:**
- [ ] `max_fps = 60`, vsync включён, MSAA 2D выключен.
- [ ] Время тика ≤ 2 мс на 12-м цикле полного забега (график в дебаг-панели).
- [ ] 3 забега подряд: прирост нод < 50, орфанов 0 (research/24 §7).
- [ ] Профайлер снят на худшем кадре; узкие места — в отчёт, а не «оптимизированы на всякий случай».

**Если решено идти на уровень 2:**
- [ ] `tidebound.gdbuild` и `tools/build_template.sh` в репозитории.
- [ ] Собрано с `optimize=size lto=full debug_symbols=no disable_3d=yes` + fallback text server.
- [ ] `disable_advanced_gui` проверен по исходникам своей версии, решение записано.
- [ ] Vulkan **не** отключён.
- [ ] Ручной полный прогон на кастомном шаблоне: меню → забег 12 циклов → все панели → оба языка → save/load.
- [ ] Записано, что шаблон надо пересобирать при апдейте движка.

---

## 8. Что НЕ делать

| Соблазн | Почему нет |
|---|---|
| UPX | ломает Embed PCK, антивирусы, +20 МБ RAM (§4) |
| Шифрование pck «для защиты кода» | ключ достаётся за секунды, растёт риск ложных срабатываний AV |
| `disable_3d` **вместе с** использованием NavigationServer2D | 2D-навигация отключается вместе с 3D ([#89185](https://github.com/godotengine/godot/issues/89185)); у нас навигации нет, но помнить |
| Отключить Vulkan «потому что рендерер Mobile» | Mobile = Vulkan Mobile; сломает десктоп (§5.4) |
| `low_processor_mode` для экономии батареи | не для игр с непрерывной анимацией (§6.2) |
| Снизить `physics_ticks_per_second` до 30 | на нём висит аккумулятор сим-тика (research/11 §3) |
| ZIP вместо PCK ради мегабайтов | медленнее чтение, выигрыш незначим при нашем объёме контента |
| Кастомный шаблон на этапе беты | постоянная стоимость: пересборка при каждом апдейте движка |
| Оптимизировать код до профилирования | док CPU optimization прямо против; у нас запас по бюджету в разы |

---

## Источники

**Официальная документация 4.7:**
- [Using the engine compilation configuration editor](https://docs.godotengine.org/en/stable/tutorials/editor/using_engine_compilation_configuration_editor.html) — `.gdbuild`, Project → Tools, «Detect from project», предупреждение про то, что галки сами по себе размер не уменьшают
- [Exporting projects](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html) — режимы экспорта ресурсов, фильтры, PCK vs ZIP, файлы с точкой
- [Exporting for Windows](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html) — архитектуры, лимит ~3.89 ГБ на Embed PCK, code signing и переменные окружения
- [Importing images](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html) — Lossless «recommended setting for pixel art», поведение Detect 3D
- [Importing audio samples](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_audio_samples.html) — QOA как дефолт, WAV vs Ogg vs MP3, Force Mono/Max Rate
- [CPU optimization](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html) — профилировать до оптимизации

**Официальная документация (страница по размеру, ветка 4.4 — в 4.7 по тому же пути 404):**
- [Optimizing a build for size](https://docs.godotengine.org/en/4.4/contributing/development/compiling/optimizing_for_size.html) — таблица экономии, `optimize=size`, `lto=full`, `debug_symbols=no`, `disable_3d`, `disable_advanced_gui`, text server, список 30+ модулей, `strip`, `7z -mx9`

**Практика сообщества (цифры не из доки — проверять у себя):**
- [How to Minify Godot's Build Size (93MB → 6.4MB) — popcar](https://popcar.bearblog.dev/how-to-minify-godots-build-size/) — пошаговые измерения, предупреждение про ненадёжность автодетекта build profile и про UPX
- [Optimize Size of Godot Releases — amann.dev](https://amann.dev/blog/2025/godot_web_size/) — Web-сборка, brotli/gzip
- [OptimizeGodotLibSizeGuide](https://github.com/GameSiProjects/OptimizeGodotLibSizeGuide)
- [Avoid false positives with anti-viruses and Godot 4 exports — itch.io](https://itch.io/t/3990804/tips-avoid-false-positives-with-anti-viruses-and-godot-engine-4-exports)

**Трекер:**
- [godot-docs#3093](https://github.com/godotengine/godot-docs/issues/3093) — UPX + Embed PCK: официально известная проблема
- [godot#18404](https://github.com/godotengine/godot/issues/18404) — UPX ломает запуск шаблона
- [godot#89185](https://github.com/godotengine/godot/issues/89185) — `disable_3d=yes` ломает 2D-навигацию
- [godot#101058](https://github.com/godotengine/godot/issues/101058) — `low_processor_usage_mode` увеличивает нагрузку
- [godot#94150](https://github.com/godotengine/godot/issues/94150), [godot#113577](https://github.com/godotengine/godot/issues/113577) — регрессии бинарной токенизации GDScript при экспорте
- [godot-proposals#11816](https://github.com/godotengine/godot-proposals/issues/11816) — смена `.build` → `.gdbuild`
- [godot#104965](https://github.com/godotengine/godot/issues/104965) — генерация build profile использует неверные имена опций
- [godot-docs#5334](https://github.com/godotengine/godot-docs/issues/5334) — список классов advanced GUI (эпоха 3.x, ⚠️ не подтверждён для 4.7)
- [GDRETools/gdsdecomp](https://github.com/GDRETools/gdsdecomp) — аудит содержимого собственного pck
