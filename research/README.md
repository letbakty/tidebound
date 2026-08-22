# research/ — предварительный ресерч TIDEBOUND

Технический ресерч под промпты из `../prompts/`. Задача материалов — чтобы агент, выполняющий этап, **не тратил сессию на выяснение API, не галлюцинировал сигнатуры и не наступал на известные грабли**, а сразу писал код.

**Дата ресерча:** 2026-08-21. **Движок:** Godot 4.7.x stable, рендерер **Mobile**.
Всё проверено по официальной документации 4.7 (баннер «Godot Engine 4.7 documentation»), migration guides и трекеру issues. Помеченное `⚠️ НЕ ПОДТВЕРЖДЕНО` — вывод из исходников или инженерная оценка, а не факт из документации; такое **нельзя вписывать в CONVENTIONS как правило**.

---

## Запланировано, но ещё не сделано

Три брифа с заданиями на 14 файлов. Исполнять по промпту [../prompts/RESEARCH-pass.md](../prompts/RESEARCH-pass.md).

| Бриф | Файлы | Темы |
|---|---|---|
| [BRIEF-next.md](BRIEF-next.md) | 34–38 | Захват геймплея и маркетинговые ассеты · звук: источники и лицензии · краш-репортинг · плейтест и телеметрия · юридический минимум |
| [BRIEF-next2.md](BRIEF-next2.md) | 39–42 | Взгляд геймдизайнера · взгляд маркетолога · взгляд игрока · сводный вердикт |
| [BRIEF-next3.md](BRIEF-next3.md) | 43–47 | Наблюдаемость симуляции · постмортемы провалов ниши · онбординг · миграция Godot · работа с AI-агентами |

Порядок: **43** → **44**, **39–42** → **34**, **35** → остальное. Обоснование — в `RESEARCH-pass.md`.

Готово сверх брифов: **48 — Steam API: что можно добавить сверх базовой интеграции** (Timeline, aggregated stats, лидерборды с 64 int32, Playtest, Rich Presence).

⚠️ Производительность симуляции ресерчить не надо: замер дал 0.137 мс на тик при бюджете 2 мс (запас 15×), подробности во вступлении `BRIEF-next3.md`.

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
| 02 | terrain-water | [12](12-terrain-tilemap-camera.md) | [01](01-water-shader.md), [06](06-pixel-art-pitfalls.md), [29](29-art-pipeline.md), [33](33-mobile-gpu-water-shader.md) §6 |
| 03 | debug-tools | [13](13-debug-overlays-drawing.md) | [11](11-sim-core-determinism.md) §10 |
| 04 | items-storage | [14](14-data-resources-tres.md) | [12](12-terrain-tilemap-camera.md) §5 (затопление) |
| 05 | agents-core | [15](15-agents-fsm-views.md) | [11](11-sim-core-determinism.md) §1.3, [29](29-art-pipeline.md) §5 |
| 06 | jobs-policies | [16](16-jobs-utility-ai-reservation.md) | [25](25-cross-engine-patterns.md) |
| 07 | buildings-construction | [17](17-buildings-production.md) | [14](14-data-resources-tres.md), [16](16-jobs-utility-ai-reservation.md) §9 |
| 08 | production | [17](17-buildings-production.md) §7 | [14](14-data-resources-tres.md) |
| 09 | crises | [16](16-jobs-utility-ai-reservation.md) §8 | [04](04-weather-particles-vignette.md), [17](17-buildings-production.md) §8 |
| 10 | expedition-cards | [14](14-data-resources-tres.md) | [25](25-cross-engine-patterns.md) §2.4 (blackboard) |
| 11 | run-meta-save | [18](18-save-serialization.md) | **[27](27-steam-integration.md) §2–3 (отчёт и user://)**, [30](30-balancing-methodology.md) §3 |
| 12 | ui-foundation | [19](19-ui-theme-components.md) | [20](20-input-gestures-gamepad.md), **[28](28-fonts-localization-process.md) (шрифт!)**, [32](32-accessibility-remap.md) |
| 13 | ui-hud | [21](21-hud-panels-tween.md) | [06](06-pixel-art-pitfalls.md) §9 |
| 14 | ui-panels-game | [21](21-hud-panels-tween.md) | [17](17-buildings-production.md) §3 (призрак) |
| 15 | ui-screens | [22](22-screens-routing-i18n.md) | [28](28-fonts-localization-process.md) §4, [32](32-accessibility-remap.md), [36](36-crash-reporting-and-feedback.md) §2, [38](38-legal-minimum.md) §1 |
| 16 | touch-gamepad | [20](20-input-gestures-gamepad.md) | [27](27-steam-integration.md) §4 (Deck), [26](26-build-size-and-optimization.md) §2, [33](33-mobile-gpu-water-shader.md) |
| 17 | audio | [23](23-audio-architecture.md) + **[35](35-audio-sources-and-design.md)** | — |
| 18 | visual-polish | [07](07-stage-18-plan.md) + **[34](34-capture-and-marketing-assets.md)** | [00](00-godot-4.7-api-facts.md)–[06](06-pixel-art-pitfalls.md) — весь блок шейдеров; [29](29-art-pipeline.md), [33](33-mobile-gpu-water-shader.md) |
| 19 | release-hardening | [24](24-testing-headless-hardening.md) + [26](26-build-size-and-optimization.md) | [30](30-balancing-methodology.md), [27](27-steam-integration.md) §7, [36](36-crash-reporting-and-feedback.md), [38](38-legal-minimum.md) |

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

## Блок 3 — платформы, продакшн, релиз (решения принимаются рано, работа делается поздно)

Эти документы не привязаны к одному этапу. Их читают **до** соответствующего этапа, потому что каждый содержит решение, которое потом дорого менять.

| Файл | О чём | Решение принимается на этапе |
|---|---|---|
| [27-steam-integration.md](27-steam-integration.md) | GodotSteam, достижения из отчётов забега без протечки в `sim/`, Steam Cloud и `use_custom_user_dir`, критерии Steam Deck Verified, демо через feature-флаги | **00** (`use_custom_user_dir`), **11** (поля отчёта), **12** (кегль ≥12 px), 15, 16 |
| [28-fonts-localization-process.md](28-fonts-localization-process.md) | Пиксельный шрифт с кириллицей **и** CJK, fallback vs один шрифт, субсеттинг, встроенная псевдолокализация, CSV→PO, бюджет переводов | **12** (выбор шрифта), 13–15, перед 3-м языком |
| [29-art-pipeline.md](29-art-pipeline.md) | Размеры и origin как контракт, Aseprite → Godot, палитра как данные, атласы, `AnimatedSprite2D` vs `AnimationPlayer`, лицензии ассетов | **02**, **05**, 07, 09, 12, 18 |
| [30-balancing-methodology.md](30-balancing-methodology.md) | Стратегические профили вместо одного автопилота, метрики забега и `timeline`, sweep-раннер, чтение CSV, поиск доминирующих стратегий | **01** (два RNG), **05–11** (счётчики), после 15 |
| [31-web-export-itch.md](31-web-export-itch.md) | Тянет ли Godot 4.7 Web наш проект: только Compatibility, однопоточный экспорт по умолчанию, IndexedDB-сейвы, вердикт и запасной план | до недели 7 |
| [32-accessibility-remap.md](32-accessibility-remap.md) | AccessKit в 4.5+, «не только цветом», контраст палитры, `reduce_motion`, архитектура под будущий ремап | **12**, 15, 18 |
| [33-mobile-gpu-water-shader.md](33-mobile-gpu-water-shader.md) | Цена бэкбуфера на тайловых GPU, фиксы Foundation после Kamaeru и Rift Riff, `water_lite`, точность float и `sim_time`, чек-лист замеров | замерять с **02**, решать на 18 |
| [34-capture-and-marketing-assets.md](34-capture-and-marketing-assets.md) | **Movie Maker mode**, режим съёмки в коде, целочисленный апскейл, GIF по палитре игры, точные размеры ассетов Steam, вертикальный кадр 9:16 | **18** (функции в код), itch-прототип, Steam-страница |
| [35-audio-sources-and-design.md](35-audio-sources-and-design.md) | Откуда берутся звуки: Sonniss/CC0/CC-BY, слои воды против усталости уха, колокол Сигнала, почему не процедурная генерация, −16 LUFS | **17**, 15, 38 |
| [36-crash-reporting-and-feedback.md](36-crash-reporting-and-feedback.md) | Файловое логирование и бэктрейсы в релизе, кнопка «сообщить о проблеме» с сидом и журналом команд, Sentry — за и против, приватность | **15**, 16, 19 |
| [37-playtest-and-telemetry.md](37-playtest-and-telemetry.md) | Что мерить в колони-симе, локальный CSV без сервера, волны тестеров, «не понял» против «не понравилось», стыковка с методикой баланса | после **15**, 19 |
| [38-legal-minimum.md](38-legal-minimum.md) | Титры и лицензии (Godot MIT, OFL, CC-BY), политика приватности, IARC, Steam Direct и налоговые формы, нужен ли EULA | **15**, 16, 19 |

⚠️ **Чего в ресерче сознательно нет:** модинг, мультиплеер, процедурная генерация утёсов, облачные сейвы помимо Steam, подпись iOS/TestFlight/App Store, глубокое профилирование через Tracy, план Б на GDExtension/C#, телеметрия плейтестов. Первые четыре — в списке «не входит никогда» из ТЗ, остальные — фаза 2. Ресерч по ним породил бы соблазн их сделать.


---

## Блок 4 — взгляд со стороны: стоит ли строить именно это

Файлы 00–38 отвечают на вопрос «как построить». Этот блок — про другой: **сойдётся ли задуманное с реальностью**. Разбор ведётся по нашим же документам (`docs/00`, `docs/01`, `docs/03`, `design/`), с указанием разделов и с ценником на каждую идею.

| Файл | Оптика | Главное |
|---|---|---|
| **[42-verdict.md](42-verdict.md)** | сводка | **Читать первым.** Три угрозы, три возможности, план на неделю |
| [39-design-critique.md](39-design-critique.md) | геймдизайнер | Одно действие в минуту; шесть пустых циклов из двенадцати; центральный конфликт поддержан одной постройкой; метапрогрессии хватает на 10–16 часов |
| [40-marketing-positioning.md](40-marketing-positioning.md) | маркетолог | **Название занято** игрой того же поля с издателем; полка выбрана неверно; в плане нет Next Fest |
| [41-player-experience.md](41-player-experience.md) | игрок | Первые 10 минут поминутно; три точки выхода; 27 автопауз за забег; обещание «провал = просчёт» интерфейсом не поддержано |

⚠️ Это разбор **документов**, а не игры: играбельной сборки нет. Выводы помечены `⚠️ НЕ ПОДТВЕРЖДЕНО` там, где нужен плейтест. Хвалебных разделов в этих файлах нет намеренно.

**Формат идей.** В каждом файле — финальная таблица «идея → что даёт → дней → **что вырезать взамен** → приоритет». Правило проекта: новая фича не добавляется, а меняется местами с запланированной. Идеи дороже недели вынесены в «отложить до второй игры».


---

## Блок 5 — инструменты и уроки чужих провалов

Третий бриф (`BRIEF-next3.md`). Первый файл ускоряет всю оставшуюся работу, второй может изменить продуктовые решения, пока их ещё дёшево менять.

| Файл | О чём | Для чего |
|---|---|---|
| [43-sim-observability.md](43-sim-observability.md) | `run_until`, дифф состояния с маской шума, `SCRIPT ERROR` валит прогон, трассировка решений, оверлеи; разбор дела о соли — какой инструмент сократил бы какой прогон | ремонтный проход `FIX-review`, балансировка, этап 19 |
| [44-failure-postmortems.md](44-failure-postmortems.md) | Постмортем билдера с числами (медиана демо **9 минут**), 90% EA не доходят до 1.0, две болезни связки «забег + мета», **20 граблей с отметкой «наступаем / не наступаем / под вопросом»** | продуктовые решения, план выхода, `docs/00 §17` |

⚠️ **Производительность в этом блоке не разбирается:** замер на текущем коде — 0,137 мс на тик при бюджете 2 мс из ТЗ §16. Точечные пункты — в `../review/04-performance.md`, включая раздел «что НЕ стоит оптимизировать».


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
| [code/crash_report.gd](code/crash_report.gd) | `autoload/crash_report.gd` | 15 |
| [code/credits_builder.gd](code/credits_builder.gd) | `ui/screens/credits_builder.gd` | 15 |
| [code/telemetry.gd](code/telemetry.gd) | `autoload/telemetry.gd` (только пресет `playtest`) | после 15 |
| [code/capture_mode.gd](code/capture_mode.gd) | `game/capture_mode.gd` | 18 |
| [code/make_gif.sh](code/make_gif.sh) | `tools/make_gif.sh` | 18 |
| [code/sim_probe.gd](code/sim_probe.gd) | `tests/sim_probe.gd` — `run_until`, дампы по тикам, пошаговый дифф | FIX-review |
| [code/sim_dump.gd](code/sim_dump.gd) | `tests/sim_dump.gd` — плоский снимок и дифф с маской шума | FIX-review |
| [code/error_guard.gd](code/error_guard.gd) | `tests/error_guard.gd` — `SCRIPT ERROR` валит прогон | FIX-review |
| [code/sim_trace.gd](code/sim_trace.gd) | `sim/sim_trace.gd` — трассировка выбора задач и причин простоя | FIX-review, баланс |
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
15. **Steam живёт ровно в одном файле** (`autoload/platform.gd`), достижения — чистые функции от отчёта забега. Grep `Steam` по проекту обязан давать одно совпадение. → [27](27-steam-integration.md) §2
16. **Шрифт обязан покрывать кириллицу И CJK в одной пиксельной сетке.** monogram/Press Start 2P из промпта 12 ведут в тупик при ZH-Hans; кандидат — Ark Pixel 12 px (OFL). → [28](28-fonts-localization-process.md) §2
17. **Размеры спрайтов и origin — контракт, а не вкус.** Заглушки этапов 02–09 задают сетку, в которую обязан встать финальный арт без правки кода. → [29](29-art-pipeline.md) §1
18. **Баланс измеряется профилями стратегий, а не одним автопилотом.** Один профиль, выигрывающий более чем в половине сидов, — доминирующая стратегия. → [30](30-balancing-methodology.md) §2
19. **Ролики снимаются Movie Maker mode, а не захватом экрана.** Режим включается сам по `OS.has_feature("movie")`, кадр пишется вне реального времени — идеальный тайминг и целочисленный апскейл 640×360 → 1920×1080. → [34](34-capture-and-marketing-assets.md) §1
20. **Процедурного звука в рантайме нет.** Документация Godot: `AudioStreamGenerator` *«best used from C# or from a compiled language via GDExtension»*, а проект — чистый GDScript. Вода и ветер — лупы. → [35](35-audio-sources-and-design.md) §4
21. **Ничего не отправляется по сети без действия игрока.** Диагностика — файл, который игрок сам присылает; телеметрия плейтеста — локальный CSV за feature-тегом. Это и техническое упрощение, и юридическое. → [36](36-crash-reporting-and-feedback.md) §4, [37](37-playtest-and-telemetry.md) §5
22. ⚠️ **Три вывода блока 4, которые меняют план, а не код:** название «Tidebound» занято на Steam и его надо сменить до создания страницы; полка сравнения — Loop Hero и Dome Keeper, а не Against the Storm; политики размечены в секундах, а опасность измеряется в ярусах — и связи между ними в интерфейсе нет. → [42](42-verdict.md)
23. **Зелёные тесты ничего не гарантируют, пока раннер не валится на `SCRIPT ERROR`.** `buffer_take` падал на каждом вызове одиннадцать этапов: 365 ошибок за прогон при полностью зелёном отчёте. Проверка stderr стоит пять минут. → [43](43-sim-observability.md) §5
24. ⚠️ **Медиана времени в демо у провалившегося билдера того же жанра — 9 минут.** Наша расчётная точка выхода — 6–10 минута. Два независимых источника сошлись на одном числе. → [44](44-failure-postmortems.md) §2

---

## Что стоит учесть на ранних этапах, чтобы не переделывать позже

Дёшево сейчас, дорого потом. Ничего из списка не нарушает разделы «Не делать» соответствующих промптов.

**Этап 00.**
- ⚠️ **`use_custom_user_dir = true` + `custom_user_dir_name = "Tidebound"`.** Меняется только до первого релиза: потом сейвы игроков осиротеют. → [27](27-steam-integration.md) §3.1
- Зум мира делать камерой, а не `stretch_shrink`: 1280/3 не делится нацело и даёт полупиксельный шов. → [10](10-project-setup-viewport-scaling.md) §1
- `physical_keycode` вместо `keycode` в Input Map: иначе WASD не работает на кириллической раскладке. → [10](10-project-setup-viewport-scaling.md) §5
- Раннер тестов должен пропускать отсутствующие сьюты, иначе сломается до этапа 01. → [24](24-testing-headless-hardening.md) §2

**Этап 01.** Семь вещей на несколько строк каждая, которые нужны шести последующим этапам: `sim_seconds()`, `total_ticks()`, `graph_version`, `cycle_modifiers`, `phase_scale`, счётчик ошибок `Log.err`. Плюс `prev` в данных события `phase_changed` — без него этап 08 не отличит «конец LOW» от «начала SIGNAL». → [11](11-sim-core-determinism.md) §11, [17](17-buildings-production.md) §7.1 Седьмая — **два потока RNG** (`rng_world` и `rng_ai`): без них любая правка ИИ сдвигает генерацию мира при том же сиде, и все прошлые баланс-прогоны становятся несравнимы. → [30](30-balancing-methodology.md) §4

**Этап 02.**
- Заглушку-`ColorRect` воды сразу на `CanvasLayer` внутри WorldViewport (`layer = 10`, `follow_viewport_enabled = true`), Full Rect, позиция кромки — числом. На 18-м останется надеть материал. → [12](12-terrain-tilemap-camera.md) §7
- `WorldGeo` как единственное место конверсий; `TOP_MARK`/`PX_PER_MARK` — в `Balance`, а не продублированы. → [12](12-terrain-tilemap-camera.md) §3
- `World.pick_at(pos)` — один хит-тест на все этапы (05, 07, 09, 14). → [15](15-agents-fsm-views.md) §7

**Этап 04.** `MaterialRequester` (учёт уже заказанного) пригодится трижды: стройка, топливо, входы станций. → [17](17-buildings-production.md) §6

**Этап 09.** `Tide` должен хранить максимум уровня за цикл (`last_high_level`) — он и так нужен сизигии. Тогда мокрые тайлы на 18-м делаются без единой правки sim. → [03](03-wet-tiles-reflections.md) §1

**Этап 12.**
- ⚠️ **Шрифт: Ark Pixel 12 px (пан-CJK, OFL), а не monogram/Press Start 2P.** И `FONT_S = 12`, а не 8 — иначе Steam Deck Verified не пройти (минимум 9 px при 1280×800). → [28](28-fonts-localization-process.md) §2, [27](27-steam-integration.md) §4.2
- Ни одна информация в UI не передаётся ТОЛЬКО цветом; тест контраста палитры — 20 строк. → [32](32-accessibility-remap.md) §2
- Ветка `USE_ATLAS: bool = false` в `theme_builder.gd` — не забыть.
- `keep_rounding_remainders = false` и subpixel positioning disabled у шрифта, иначе текст поедет на полпикселя. → [19](19-ui-theme-components.md) §4

**Этап 17.** Звук берётся из Sonniss GDC Bundle (royalty-free, **атрибуция не нужна**) и CC0; CC-BY-NC и CC-BY-SA в проект не попадают вовсе. `assets/sfx/SOURCES.csv` заводится с первого файла — иначе титры к релизу не собрать. → [35](35-audio-sources-and-design.md) §1

**Этап 18.** Пять функций режима съёмки (скрытие слоёв, автоопределение записи, фиксированная скорость, перемотка по журналу команд, `stretch_scale_mode = integer` на время сессии). Без них каждый дубль ролика переснимается вручную. → [34](34-capture-and-marketing-assets.md) §0

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
