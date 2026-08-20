# Этап 01 — Ядро симуляции: SimWorld, часы, фазы, шина событий

**Модель:** Opus 5 или Fable 5 (архитектурный этап — фундамент всего).
**Зависит от:** этап 00. **Читать:** docs/02-architecture.md (весь), docs/00 §2, §4, §16.
**Результат:** тикающая симуляция с фазами прилива, командной очередью и трансляцией событий в Events; headless-тест зелёный.
**Ресерч:** [research/11-sim-core-determinism.md](../research/11-sim-core-determinism.md) — **шесть источников недетерминизма**, аккумулятор тика, хеш состояния, `to_dict/from_dict`. Дополнительно: [research/25](../research/25-cross-engine-patterns.md) §2.1.
**Готовый код:** `research/code/audit_sim.sh` → `tools/audit_sim.sh` — переноси, а не пиши с нуля (черновики под контракты docs/02, но не компилировались: сверь имена полей с тем, что реально сделали прошлые этапы).

## Контекст
Проект пуст после этапа 00: есть папки, автолоады-заглушки, настройки. Ты создаёшь скелет sim-ядра, на который встанут все остальные системы. Точность контрактов важнее объёма: другие агенты будут писать код против твоих сигнатур.

## Задача
1. `sim/sim_types.gd` — все enum'ы из docs/02 §3.1 (скопируй дословно).
2. `sim/balance.gd` — `class_name Balance`, только `const`. Заведи: `TICKS_PER_SEC=10`, длительности фаз в тиках (EBB=450, LOW=1500, SIGNAL=300, HIGH=750), `CYCLES_PER_RUN=12`, уровни воды (HIGH_LEVEL=0.0, LOW_LEVEL=-8.0, SIGNAL_LEVEL=-6.0, SPRING_BONUS=2.0), календарь кризисов из docs/00 §9.2 как const-словарь.
3. `sim/sim_rng.gd` — `class_name SimRNG`, обёртка над `RandomNumberGenerator`: `setup(seed)`, `randi_range`, `randf`, `pick(arr)`, `chance(p)`, `get_state()/set_state()` (через `rng.state`).
4. `sim/sim_event.gd` — `class_name SimEvent`: `type: String`, `data: Dictionary`; статический конструктор `SimEvent.make(type, data)`.
5. `sim/sim_clock.gd` — `class_name SimClock`: `tick_in_phase`, `phase: SimTypes.Phase`, `cycle: int` (с 1), `tick()` продвигает и возвращает `Array[SimEvent]` (события `phase_changed`, `cycle_started`, `cycle_ended` —報 итог цикла собирает пока пустой словарь). Прогресс фазы `phase_progress() -> float` 0..1.
6. `sim/tide.gd` — `class_name Tide`: `level: float`; `update(clock)` каждый тик: кривая по docs/00 §4 (EBB: 0→−8 smoothstep по прогрессу; LOW: плато −8; SIGNAL: −8→−6 линейно; HIGH: −6→плато за первые 20с, далее плато). Плато-значения — поля (`low_plateau`, `high_plateau`), чтобы карты/сизигия могли их менять. Эмитит событие `water_level_changed` не чаще раза в 3 тика и только при |Δ|>0.01.
7. `sim/sim_world.gd` — `class_name SimWorld`: владеет `clock, tide, rng`, `events_out: Array[SimEvent]`, очередь команд `_commands: Array[Dictionary]`; `apply_command(cmd: Dictionary)` кладёт в очередь; `tick()`: разобрать команды → clock → tide → (заглушки будущих систем по порядку из docs/02 §4) → собрать события. `to_dict()/from_dict()` для clock/tide/rng (версия `save_version=1`).
8. `autoload/game.gd` — аккумулятор из docs/02 §4: `speed: int` (0..3), `world: SimWorld`; `cmd_new_run(seed)`, `cmd_set_speed(mult)`; `_flush_events()` — маппинг `SimEvent.type` → сигнал `Events` (пока: sim_ticked, phase_changed, water_level_changed, cycle_started, cycle_ended).
9. `autoload/events.gd` — все сигналы из docs/02 §3.2 (объяви ВСЕ сразу, даже неиспользуемые: это контракт для следующих этапов).

## Заложить сейчас — иначе шесть последующих этапов будут переделывать ядро
Из [research/11](../research/11-sim-core-determinism.md) §11. Каждый пункт — несколько строк, но добавленный позже требует правки формулы фаз (самое опасное место для детерминизма):
- `Game.sim_seconds() -> float` — время для шейдеров (этап 18).
- `SimClock.total_ticks() -> int` — сквозной счётчик тиков забега (не `tick_in_phase`): нужен хешам, логам и графику времени тика.
- `SimWorld.graph_version: int` — инкремент при любом изменении графа (кэш путей этапов 05/06, оверлей этапа 03).
- `SimWorld.cycle_modifiers: Dictionary` — пустой, но заведённый: этапы 05/06/08/10 будут читать его, а не хардкод.
- `SimClock.phase_scale: Dictionary[int, float]` — единичный словарь; этап 09 шторма укорачивает LOW на 30% через него.
- `_error_count` в `Game`, инкремент в ветке `_:` маппинга событий — даёт этапу 19 бесплатную санитарию сигналов.
- В данные события `phase_changed` класть **`prev`** (предыдущая фаза) — без него этап 08 не отличит «конец LOW» от «начала SIGNAL».
- `MAX_TICKS_PER_FRAME = 12` в аккумуляторе — защита от «спирали смерти» ([research/11](../research/11-sim-core-determinism.md) §3).

## Логика и тонкости
- Тик — целое; никакого float-времени в sim. `world.tick()` должен быть детерминирован: одинаковый сид + одинаковая последовательность команд → одинаковое состояние.
- Команды применяются ТОЛЬКО в начале тика, в порядке поступления.
- Скорость: `Game` вызывает `world.tick()` 1–3 раза за физический шаг по аккумулятору; speed=0 — не вызывает.

## Приёмка (tests/test_clock.gd + run_all.gd)
- [ ] 3000 тиков = ровно один цикл; фазы сменяются на границах 450/1950/2250/3000.
- [ ] Уровень воды: тик 0 → 0.0; середина LOW → −8.0; конец SIGNAL → −6.0; конец HIGH → 0.0 (±0.01).
- [ ] Два SimWorld с одним сидом после 10 000 тиков имеют одинаковый `JSON.stringify(to_dict())`. ⚠️ Хеш считать хелпером из [research/11](../research/11-sim-core-determinism.md) §2 (`JSON.stringify(...).sha256_text()`), **не** через `Dictionary.hash()` — тот чувствителен к порядку вставки и даст ложные расхождения после `from_dict`.
- [ ] `to_dict → from_dict → to_dict` — идентичные словари.
- [ ] `godot --headless -s res://tests/run_all.gd` — код выхода 0.

## Не делать
Агентов, ресурсы, постройки, UI, отрисовку воды, сейв-файлы на диск (только to_dict/from_dict). Никаких нод кроме правки автолоадов.
