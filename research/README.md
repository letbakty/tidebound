# research/ — предварительный ресерч TIDEBOUND

Технический ресерч под промпты из `../prompts/`. Задача материалов — чтобы агент, выполняющий этап, **не тратил сессию на выяснение API, не галлюцинировал сигнатуры и не наступал на известные грабли**, а сразу писал код.

**Дата ресерча:** 2026-08-21. **Движок:** Godot 4.7.x stable, рендерер **Mobile**.
Всё проверено по официальной документации 4.7 (баннер «Godot Engine 4.7 documentation»), migration guides и трекеру issues. Помеченное `⚠️ НЕ ПОДТВЕРЖДЕНО` — вывод из исходников или инженерная оценка, а не факт из документации; такое **нельзя вписывать в CONVENTIONS как правило**.

---

## Как этим пользоваться

Начинай сессию этапа так:

> Прочитай `prompts/CONVENTIONS.md`, `research/<файл из таблицы ниже>` и выполни этап из `prompts/NN-….md`. Готовый код лежит в `research/code/` — переноси его, а не пиши с нуля.

Код в `research/code/` — **черновики к переносу**, а не рабочий проект. Он написан под контракты docs/02 (`Events`, `Game.cmd_*`, `SimTypes`), со статической типизацией и русскими комментариями «почему» — то есть по CONVENTIONS. Но он **не компилировался**: имена полей sim надо сверить с тем, что реально сделали предыдущие этапы.

---

## Карта: промпт → что читать

| Этап | Промпт | Основной ресерч | Дополнительно |
|---|---|---|---|
| 00 | project-setup | [10](10-project-setup-viewport-scaling.md) | [24](24-testing-headless-hardening.md) (раннер) |
| 01 | sim-clock-and-bus | [11](11-sim-core-determinism.md) | [25](25-cross-engine-patterns.md) §2.1 |
| 02 | terrain-water | [12](12-terrain-tilemap-camera.md) | [01](01-water-shader.md), [06](06-pixel-art-pitfalls.md) |
| 03 | debug-tools | [13](13-debug-overlays-drawing.md) | [11](11-sim-core-determinism.md) §10 |
| 04 | items-storage | [14](14-data-resources-tres.md) | [12](12-terrain-tilemap-camera.md) §5 (затопление) |
| 05 | agents-core | [15](15-agents-fsm-views.md) | [11](11-sim-core-determinism.md) §1.3 |
| 06 | jobs-policies | [16](16-jobs-utility-ai-reservation.md) | [25](25-cross-engine-patterns.md) |
| 07 | buildings-construction | [17](17-buildings-production.md) | [14](14-data-resources-tres.md), [16](16-jobs-utility-ai-reservation.md) §9 |
| 08 | production | [17](17-buildings-production.md) §7 | [14](14-data-resources-tres.md) |
| 09 | crises | [16](16-jobs-utility-ai-reservation.md) §8 | [04](04-weather-particles-vignette.md), [17](17-buildings-production.md) §8 |
| 10 | expedition-cards | [14](14-data-resources-tres.md) | [25](25-cross-engine-patterns.md) §2.4 (blackboard) |
| 11 | run-meta-save | [18](18-save-serialization.md) | [11](11-sim-core-determinism.md) §8 |
| 12 | ui-foundation | [19](19-ui-theme-components.md) | [20](20-input-gestures-gamepad.md) |
| 13 | ui-hud | [21](21-hud-panels-tween.md) | [06](06-pixel-art-pitfalls.md) §9 |
| 14 | ui-panels-game | [21](21-hud-panels-tween.md) | [17](17-buildings-production.md) §3 (призрак) |
| 15 | ui-screens | [22](22-screens-routing-i18n.md) | [21](21-hud-panels-tween.md) |
| 16 | touch-gamepad | [20](20-input-gestures-gamepad.md) | [10](10-project-setup-viewport-scaling.md) §1, [26](26-build-size-and-optimization.md) §2 (пресеты) |
| 17 | audio | [23](23-audio-architecture.md) | — |
| 18 | visual-polish | [07](07-stage-18-plan.md) | [00](00-godot-4.7-api-facts.md)–[06](06-pixel-art-pitfalls.md) — весь блок шейдеров |
| 19 | release-hardening | [24](24-testing-headless-hardening.md) + [26](26-build-size-and-optimization.md) | [11](11-sim-core-determinism.md) §10 |

---

## Блок 1 — шейдеры и визуал (этап 18, частично 02 и 13)

| Файл | О чём |
|---|---|
| [00-godot-4.7-api-facts.md](00-godot-4.7-api-facts.md) | Проверенные факты API: screen texture, built-ins, SubViewport, Mobile+свет, TIME и пауза, изменения 4.6/4.7, открытые баги |
| [01-water-shader.md](01-water-shader.md) | **Главный документ визуала.** Шейдер воды: рефракция без depth-буфера, единая функция волны, где физически живёт нода, отражения, производительность |
| [02-light-fog-atmosphere.md](02-light-fog-atmosphere.md) | Глубинный туман, бюджет 8 светов, пиксельное освещение, Parallax2D |
| [03-wet-tiles-reflections.md](03-wet-tiles-reflections.md) | Мокрые тайлы через один uniform, три подхода к отражениям и почему выбран третий |
| [04-weather-particles-vignette.md](04-weather-particles-vignette.md) | Дождь шейдером, виньетка снаружи вьюпорта, молния, пул брызг, частицы и пауза |
| [05-shader-time-and-pause.md](05-shader-time-and-pause.md) | Почему `TIME` запрещён и как устроен global uniform `sim_time` |
| [06-pixel-art-pitfalls.md](06-pixel-art-pitfalls.md) | Подводные камни пиксель-арта с шейдерами + таблица «симптом → причина» |
| [07-stage-18-plan.md](07-stage-18-plan.md) | Пошаговый план этапа 18, профилирование, финальная приёмка |

## Блок 2 — симуляция, данные, UI, инфраструктура (этапы 00–17, 19)

| Файл | О чём | Для этапов |
|---|---|---|
| [10-project-setup-viewport-scaling.md](10-project-setup-viewport-scaling.md) | Гибридный вьюпорт и дробный масштаб, точные ключи ProjectSettings, автолоады, Input Map из кода, i18n, headless | 00, 16 |
| [11-sim-core-determinism.md](11-sim-core-determinism.md) | **Шесть источников недетерминизма** и как каждый закрыть; хеш состояния; аккумулятор тика; `to_dict/from_dict`; grep-аудит | 01, 19 |
| [12-terrain-tilemap-camera.md](12-terrain-tilemap-camera.md) | TileMapLayer 4.7, генерация тайлсета скриптом, `WorldGeo`, `AStar2D` вместо BFS, `is_flooded` с эпсилоном, камера и пиксель | 02 |
| [13-debug-overlays-drawing.md](13-debug-overlays-drawing.md) | `_draw` и троттлинг, гейт релиза, подписка на все сигналы рефлексией, кольцевой лог, промотка времени | 03 |
| [14-data-resources-tres.md](14-data-resources-tres.md) | **Генерация ~70 `.tres` скриптом** вместо кликов, ограничения типизированных словарей, `DB` и ловушка `.remap`, валидаторы ссылок | 04, 05, 07, 08, 10, 11 |
| [15-agents-fsm-views.md](15-agents-fsm-views.md) | FSM без нод, прерывания, гистерезис потребностей, утопление, синхронизация View, хит-тест без физики | 05 |
| [16-jobs-utility-ai-reservation.md](16-jobs-utility-ai-reservation.md) | Утилитарный скоринг (The Sims), резервирование (RimWorld), пул задач по событиям, маяк, существа на инвертированном графе | 06, 09 |
| [17-buildings-production.md](17-buildings-production.md) | Три состояния + два флага, сетка занятости, призрак, лестницы и граф, **дедупликация HAUL**, буфер станции, шторм | 07, 08 |
| [18-save-serialization.md](18-save-serialization.md) | Четыре ловушки JSON (float-типы, `full_precision`, NAN, атомарность), безопасность, `rebroadcast_state`, когда сохранять | 11 |
| [19-ui-theme-components.md](19-ui-theme-components.md) | Тема из кода (`set_type_variation`), каскад и CanvasLayer, **настройки пиксель-шрифта**, правила компонента, радиал | 12, 18 |
| [20-input-gestures-gamepad.md](20-input-gestures-gamepad.md) | Порядок обработки ввода, мультитач по `index`, пинч вручную, long-press, геймпад и фокус, safe area, экспорт | 12, 16 |
| [21-hud-panels-tween.md](21-hud-panels-tween.md) | Кэши виджетов вместо чтения sim, `TideGauge` в `_draw`, Tween 4.7, тосты, `PanelHost`, bottom sheet | 13, 14 |
| [22-screens-routing-i18n.md](22-screens-routing-i18n.md) | Роутер по видимости (не `change_scene`), автопауза со счётчиком, локализация на лету, настройки и масштаб UI | 15 |
| [23-audio-architecture.md](23-audio-architecture.md) | Шины из кода, `AudioStreamPolyphonic`, равномощностный кроссфейд, маппинг событий, генерация `.wav`-плейсхолдеров | 17 |
| [24-testing-headless-hardening.md](24-testing-headless-hardening.md) | `assert` вырезается в release, свой раннер, soak-тест с CSV, память и орфаны, санитария сигналов, краевые случаи, CI | 00, 19 |
| [25-cross-engine-patterns.md](25-cross-engine-patterns.md) | 20 приёмов из других движков и игр (Unity, Unreal, Factorio, RimWorld, The Sims, ONI) + **что НЕ брать и почему** | сквозной |
| [26-build-size-and-optimization.md](26-build-size-and-optimization.md) | **Размер сборки и релизная оптимизация:** что реально весит, настройки импорта/экспорта, `strip` и архив, кастомный шаблон `scons`, почему UPX — нет, рантайм-настройки | 19, 16, 18 |

---

## Код

| Файл | Куда переносить | Для этапа |
|---|---|---|
| [code/run_all.gd](code/run_all.gd) | `tests/run_all.gd` | 00 |
| [code/test_ctx.gd](code/test_ctx.gd) | `tests/test_ctx.gd` | 00 |
| [code/audit_sim.sh](code/audit_sim.sh) | `tools/audit_sim.sh` | 01, 19 |
| [code/world_geo.gd](code/world_geo.gd) | `game/world_geo.gd` | 02 |
| [code/save_io.gd](code/save_io.gd) | `autoload/save_io.gd` (или внутрь `save_service.gd`) | 11 |
| [code/input_service.gd](code/input_service.gd) | `ui/input_service.gd` | 12 |
| [code/water.gdshader](code/water.gdshader) | `assets/shaders/water.gdshader` | 18 |
| [code/water_view.gd](code/water_view.gd) | `game/water_view.gd` | 18 (заготовка — 02) |
| [code/depth_fog.gdshader](code/depth_fog.gdshader) | `assets/shaders/depth_fog.gdshader` | 18 |
| [code/wet_tiles.gdshader](code/wet_tiles.gdshader) | `assets/shaders/wet_tiles.gdshader` | 18 |
| [code/rain.gdshader](code/rain.gdshader) | `assets/shaders/rain.gdshader` | 18 |
| [code/vignette.gdshader](code/vignette.gdshader) | `assets/shaders/vignette.gdshader` | 18 |
| [code/sprite_lit.gdshader](code/sprite_lit.gdshader) | `assets/shaders/sprite_lit.gdshader` | 18 |
| [code/weather_view.gd](code/weather_view.gd) | `game/weather_view.gd` | 18 |
| [code/light_budget.gd](code/light_budget.gd) | `game/light_budget.gd` | 18 |
| [code/shader_time.gd](code/shader_time.gd) | фрагмент врезается в `autoload/game.gd` | 18 (заготовка — 01) |

---

## Решения, которые определяют проект

### Визуал (подробности — блок 1)

1. **`TIME` в шейдерах запрещён.** Он не останавливается на паузе (подтверждено документацией). Всё идёт через global uniform `sim_time = tick/10 + accum`. Иначе тактическая пауза — главная фича управления — перестаёт читаться. → [05](05-shader-time-and-pause.md)
2. **Screen-read шейдер в проекте ровно один — вода.** Копия бэкбуфера делается автоматически при первом таком узле; второй увидит устаревшую копию. Поэтому виньетка, дождь и туман — обычные градиенты в `blend_mix`. → [00](00-godot-4.7-api-facts.md) §3
3. **Полноэкранные эффекты — статичные ColorRect на CanvasLayer внутри WorldViewport,** привязка к миру передаётся числом в uniform. → [06](06-pixel-art-pitfalls.md) §4
4. **Виньетка — снаружи SubViewport, в нативном разрешении.** Дождь — наоборот внутри. → [04](04-weather-particles-vignette.md) §2
5. **Отражения — зеркалим тот же бэкбуфер, что уже скопирован ради рефракции.** → [03](03-wet-tiles-reflections.md) §2

### Симуляция и инфраструктура (подробности — блок 2)

6. **Тик — единственные часы мира.** Все «за N секунд» из спеки живут в коде как целые тики. Плавающая точка — только там, где есть допуск. → [11](11-sim-core-determinism.md) §1
7. **`Array.sort_custom` не стабилен** (подтверждено документацией). Любой компаратор обязан быть тотальным: последним ключом всегда `id`. Лучше — линейный выбор максимума вместо сортировки. → [11](11-sim-core-determinism.md) §1.1
8. **`JSON.parse` возвращает все числа как float, а `stringify` по умолчанию усекает точность.** Это два независимых способа завалить приёмку сейвов. → [18](18-save-serialization.md) §1–2
9. **Данные (~70 `.tres`) генерируются скриптом из таблицы в коде,** а не набиваются в инспекторе. Самый крупный выигрыш по времени во всём ресерче. → [14](14-data-resources-tres.md) §3
10. **Задачи порождает мир, а не агент** (модель «рекламы» из The Sims), а конфликты решает резервирование (модель RimWorld). → [16](16-jobs-utility-ai-reservation.md) §1
11. **UI никогда не читает sim.** Каждый виджет держит свой кэш, наполняемый событиями; исключение — синхронные `Game.query_*`, отдающие отдельную view-проекцию. → [21](21-hud-panels-tween.md) §1, [25](25-cross-engine-patterns.md) §2.3
12. **`assert` вырезается в release-сборках.** Тесты пишутся на своём `check()`. → [24](24-testing-headless-hardening.md) §1
13. **90% размера билда — это шаблон движка, а не наш контент.** Настройки экспорта и импорта режут pck, но общий размер меняют мало; серьёзное сокращение даёт только кастомный шаблон `scons` — с постоянной стоимостью пересборки при каждом апдейте движка. → [26](26-build-size-and-optimization.md) §0
14. **UPX не использовать:** ломает Embed PCK, вызывает ложные срабатывания антивирусов и добавляет ~20 МБ RAM в рантайме. → [26](26-build-size-and-optimization.md) §4

---

## Что стоит учесть на ранних этапах, чтобы не переделывать позже

Дёшево сейчас, дорого потом. Ничего из списка не нарушает разделы «Не делать» соответствующих промптов.

**Этап 00.**
- Зум мира делать камерой, а не `stretch_shrink`: 1280/3 не делится нацело и даёт полупиксельный шов. → [10](10-project-setup-viewport-scaling.md) §1
- `physical_keycode` вместо `keycode` в Input Map: иначе WASD не работает на кириллической раскладке. → [10](10-project-setup-viewport-scaling.md) §5
- Раннер тестов должен пропускать отсутствующие сьюты, иначе сломается до этапа 01. → [24](24-testing-headless-hardening.md) §2

**Этап 01.** Шесть вещей на несколько строк каждая, которые нужны шести последующим этапам: `sim_seconds()`, `total_ticks()`, `graph_version`, `cycle_modifiers`, `phase_scale`, счётчик ошибок `Log.err`. Плюс `prev` в данных события `phase_changed` — без него этап 08 не отличит «конец LOW» от «начала SIGNAL». → [11](11-sim-core-determinism.md) §11, [17](17-buildings-production.md) §7.1

**Этап 02.**
- Заглушку-`ColorRect` воды сразу на `CanvasLayer` внутри WorldViewport (`layer = 10`, `follow_viewport_enabled = true`), Full Rect, позиция кромки — числом. На 18-м останется надеть материал. → [12](12-terrain-tilemap-camera.md) §7
- `WorldGeo` как единственное место конверсий; `TOP_MARK`/`PX_PER_MARK` — в `Balance`, а не продублированы. → [12](12-terrain-tilemap-camera.md) §3
- `World.pick_at(pos)` — один хит-тест на все этапы (05, 07, 09, 14). → [15](15-agents-fsm-views.md) §7

**Этап 04.** `MaterialRequester` (учёт уже заказанного) пригодится трижды: стройка, топливо, входы станций. → [17](17-buildings-production.md) §6

**Этап 09.** `Tide` должен хранить максимум уровня за цикл (`last_high_level`) — он и так нужен сизигии. Тогда мокрые тайлы на 18-м делаются без единой правки sim. → [03](03-wet-tiles-reflections.md) §1

**Этап 12.**
- Ветка `USE_ATLAS: bool = false` в `theme_builder.gd` — не забыть.
- `keep_rounding_remainders = false` и subpixel positioning disabled у шрифта, иначе текст поедет на полпикселя. → [19](19-ui-theme-components.md) §4

**Этап 13.**
- ⚠️ В 4.7 `CanvasItem` больше не добавляет antialiasing feather при рисовании линий (GH-105122). `TideGauge` рисуется через `_draw()` — ширину линий задавать явно. → [06](06-pixel-art-pitfalls.md) §9
- Единая очередь уведомлений (тост/банер/подсказка) с приоритетами: иначе на 15-м они начнут накладываться. → [25](25-cross-engine-patterns.md) §4

---

## Открытые баги Godot, за которыми стоит следить

| # | Что | Как нас касается |
|---|---|---|
| 78207 | альфа screen texture у прозрачного вьюпорта всегда 1.0 | не включать `transparent_bg` на WorldViewport |
| 84987 | `BackBufferCopy` rect mode некорректен на Mobile | если понадобится — только `COPY_MODE_VIEWPORT` |
| 77916 | `speed_scale = 0` не останавливает частицы | пауза частиц через `PROCESS_MODE_DISABLED` |
| 85213 | trails частиц продолжают симуляцию на паузе | то же |
| 113092 | Y-sort не действует на клоны повтора `Parallax2D` | параллакс — только в фоновых слоях вне Y-sort |
| 115335 | отрицательный `scroll_scale` ломает повтор `Parallax2D` | обратное движение — через `autoscroll` |
| 116838 | pixel jitter у края карты (регресс 4.6) | проверить панораму до лимитов карты |
| 93048 | Camera2D дрожит в масштабированном SubViewport с pixel snapping | виртуальная позиция камеры + snap → [12](12-terrain-tilemap-camera.md) §6.4 |
| 104581 | ключ экспортированного типизированного словаря нельзя изменить в инспекторе | `.tres` генерируются скриптом → [14](14-data-resources-tres.md) §3 |
| 109574 | типизированные коллекции кастомных типов без `class_name` ломают инспектор | у каждого дефа обязателен `class_name` |
| 71046 | размытый шрифт в 4.x | `keep_rounding_remainders = false` → [19](19-ui-theme-components.md) §4 |
| 27127 | `TIME` не останавливается на паузе | наш `sim_time` |
| proposals#4340 | нет кроссплатформенного API жестов | пинч считаем вручную → [20](20-input-gestures-gamepad.md) §3 |
| docs#3093, 18404 | UPX ломает запуск при Embed PCK | UPX не используем → [26](26-build-size-and-optimization.md) §4 |
| 89185 | `disable_3d=yes` отключает и 2D-навигацию | нам не мешает (свой граф), но помнить при кастомном шаблоне |
| 101058 | `low_processor_usage_mode` увеличивает нагрузку | не включать; экономия батареи — через `max_fps` |
| 94150, 113577 | регрессии бинарной токенизации GDScript при экспорте | при странных ошибках только в экспорте — временно GDScript Export Mode = Text |
