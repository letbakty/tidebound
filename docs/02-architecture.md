# TIDEBOUND — Архитектура проекта (Godot 4.7, GDScript)

Версия 1.0. Обязательна к прочтению каждым кодинг-агентом перед началом этапа.
Игровые правила и числа — в [00-functional-spec.md](00-functional-spec.md). UI — в [01-ui-spec.md](01-ui-spec.md).

---

## 1. Главный принцип: симуляция отделена от презентации

Проект делится на три слоя с жёсткими границами:

```
┌─ UI (res://ui) ────────────────────────────────────────────┐
│ слушает Events, вызывает Game.cmd_*                        │
└──────────────▲─────────────────────────┬───────────────────┘
        Events (сигналы)          Game.cmd_* (команды)
┌──────────────┴─────────────────────────▼───────────────────┐
│ ПРЕЗЕНТАЦИЯ И ОРКЕСТРАЦИЯ (res://game, res://autoload)     │
│ Game тикает SimWorld, транслирует events_out в Events;     │
│ View-ноды рисуют состояние sim по id                       │
└──────────────▲─────────────────────────┬───────────────────┘
     world.events_out (Array)      world.apply(cmd)
┌──────────────┴─────────────────────────▼───────────────────┐
│ SIM CORE (res://sim) — чистый GDScript, БЕЗ нод            │
│ RefCounted-классы; фиксированный тик; сидированный RNG     │
└────────────────────────────────────────────────────────────┘
```

**Запреты (проверяются на каждом ревью):**
- В `res://sim/` нет: `Node`, `get_tree()`, `get_node()`, автолоадов, `await`, `Timer`, физики, `randi()/randf()` без `SimRNG`, обращения к `Time.*` (время — только номер тика).
- UI никогда не читает и не пишет sim напрямую: только `Game.cmd_*` вниз и `Events` вверх.
- View-ноды не содержат игровой логики: только отображение и проброс ввода.

Зачем так строго: headless-тесты симуляции без сцены, детерминизм (реплеи, отладка по сиду), свобода переделывать UI/арт без риска для логики.

---

## 2. Структура папок

```
res://
  project.godot
  autoload/
    events.gd          # Шина сигналов (singleton Events)
    game.gd            # Оркестратор: владеет SimWorld, тикает, cmd_* (singleton Game)
    meta.gd            # Мета-профиль: Журнал, разблокировки (singleton Meta)
    save_service.gd    # Сейвы JSON (singleton SaveService)
    audio_service.gd   # Аудио-шина (singleton AudioService)
    settings.gd        # Настройки игрока (singleton Settings)
  sim/                 # ЯДРО. Только RefCounted/чистые классы
    balance.gd         # ВСЕ игровые константы (class_name Balance, только const)
    sim_world.gd       # class_name SimWorld — владелец всего состояния, tick()
    sim_clock.gd       # фазы, циклы, календарь кризисов
    tide.gd            # уровень воды, кривые
    terrain.gd         # ярусы, площадки, лестницы, граф, депозиты
    sim_agent.gd       # данные одного агента + FSM
    agent_system.gd    # апдейт агентов, скоринг работ
    job_system.gd      # генерация и раздача задач
    storage_system.gd  # склады, стаки, порча, намокание
    building_system.gd # постройки, стройка, износ, затопление
    production_system.gd # станции и рецепты
    crisis_system.gd   # сизигия, шторм, приход, существа
    policy_set.gd      # 6 политик
    run_state.gd       # цикл, очки, драфт, конец забега
    sim_rng.gd         # обёртка RandomNumberGenerator с сидом
    sim_event.gd       # структура события для events_out
    sim_types.gd       # enum'ы: Phase, AgentState, JobClass, FloodRule...
  data/                # .tres ресурсы (данные) + их class_name скрипты
    defs/              # item_def.gd, building_def.gd, recipe_def.gd,
                       # trait_def.gd, card_def.gd, unlock_def.gd, cliff_def.gd
    items/*.tres  buildings/*.tres  recipes/*.tres
    traits/*.tres cards/*.tres     unlocks/*.tres
    cliffs/cliff_01.tres
    db.gd              # class_name DB: статический доступ ко всем дефам по id
  game/                # презентация мира
    main.tscn/gd       # главная сцена: SubViewportContainer + CanvasLayer-слои (этап 00)
    world.tscn/gd      # корень мира: тайлмапы, вода, контейнеры View
    build_ghost.gd     # призрак размещения постройки (этап 07)
    beacon_view.tscn   # маркер маяка (этап 14)
    agent_view.tscn/gd # спрайт агента, привязан к sim id
    building_view.tscn/gd
    creature_view.tscn/gd
    water_view.tscn/gd # прямоугольник воды + шейдер
    camera_rig.tscn/gd # камера, зум, панорама, снап
  ui/                  # см. 01-ui-spec.md
    input_service.gd   # жесты поверх мира (этап 12)
    theme/  components/  hud/  panels/  screens/
  assets/
    sprites/  fonts/  sfx/  music/  shaders/
  tests/
    run_all.gd         # headless-раннер: godot --headless -s res://tests/run_all.gd
    test_*.gd          # по файлу на систему
  debug/
    debug_panel.tscn/gd
    debug_overlay.gd   # отладочная отрисовка графа/зон (этап 03)
```

---

## 3. Контракты

### 3.1 Enum'ы (sim/sim_types.gd)
```gdscript
class_name SimTypes
enum Phase { EBB, LOW, SIGNAL, HIGH }
enum AgentState { IDLE, GOTO, WORK, HAUL, GATHER, RETURN, REST, EAT, PANIC, DROWNING, DEAD }
enum JobClass { GATHER, HAUL, BUILD, REPAIR, STATION, REST, EAT }
enum Policy { GREED, CAUTION, REPAIR, BUILD, SUPPLY, REST }
enum FloodRule { OK, WET, LOSE_HALF, DESTROY, DISABLED }
enum CrisisType { SPRING_TIDE, STORM, VISIT }   # сизигия, шторм, приход
enum RunEnd { SHIP, WIPE, EARLY }
```

### 3.2 Шина Events (autoload/events.gd) — полный список сигналов
```gdscript
# от симуляции (эмитит ТОЛЬКО Game после world.tick())
signal sim_ticked(tick: int)
signal phase_changed(phase: int, cycle: int)
signal water_level_changed(level: float)          # раз в 3 тика достаточно
signal cycle_started(cycle: int)
signal cycle_ended(report: Dictionary)
signal run_started(seed_value: int)
signal run_ended(report: Dictionary)
signal agent_spawned(id: int)
signal agent_updated(id: int)                     # смена состояния/яруса, не каждый тик
signal agent_died(id: int, cause: String)
signal agent_drowning(id: int)
signal building_placed(id: int)
signal building_state_changed(id: int)            # затоплено/повреждено/починено
signal building_removed(id: int)
signal deposit_changed(id: int)
signal storage_changed(id: int)
signal resources_changed(totals: Dictionary)      # {item_id: int} агрегат
signal crisis_announced(type: int, cycle: int)
signal crisis_started(type: int)
signal crisis_ended(type: int)
signal creature_spawned(id: int)
signal creature_left(id: int)
signal ship_arrived()                             # судно прибыло (начало HIGH последнего цикла)
signal draft_ready(card_ids: Array[String])
signal card_picked(card_id: String)
signal beacon_moved(cell: Vector2i)
signal policy_changed(policy: int, value: int)
signal recall_issued(hard: bool)
signal unlock_gained(unlock_id: String)
# от UI/оркестрации (не из sim)
signal speed_changed(mult: int)                   # 0 = пауза
signal ui_panel_opened(panel_name: String)
signal ui_panel_closed(panel_name: String)
```

#### Отчёт забега `run_ended(report)` — контракт, а не свободный словарь

Отчёт собирает `RunState._final_report`. Его читают экран итогов, Журнал
(`Meta.record_run`), soak-CSV и — после этапа 20 — таблица достижений Steam:
предикаты достижений обязаны быть чистыми функциями от этого словаря
(research/27 §2.3), поэтому Steam не протекает ни в `sim/`, ни в UI.

| Ключ | Тип | Что значит |
|---|---|---|
| `end` | int | `SimTypes.RunEnd` |
| `early` | bool | ушли досрочно (`end` при этом всё равно `SHIP`) |
| `cycles` | int | прожито циклов |
| `seed` | int | сид забега |
| `score` / `raw_score` | int | итог с множителем исхода и без него |
| `breakdown` | Dictionary | строки разбивки; их сумма и есть `raw_score` |
| `deaths` | Array[Dictionary] | эпитафии: имя, причина, био, черты, цикл |
| `dead` / `drowned` | int | погибших всего и утонувших (`RunState.CAUSE_DROWN`) |
| `alive` | int | живых **на момент снимка очков**, а не на конец забега |
| `relics` | int | реликвий вывезено |
| `produced` | Dictionary[String, int] | произведено станциями за забег |
| `cards_picked` | Array[String] | карты вылазки в порядке выбора |
| `deepest_mark` | int | самая низкая отметка, где побывал агент |
| `crises_survived` | Array[int] | типы кризисов, дожитых до конца цикла |
| `storms_survived` | int | из них штормов |
| `buildings_built` / `buildings_lost` | int | достроено колонией / сорвано штормом |

⚠️ **Новое поле заводится здесь и сразу.** После релиза добавление поля —
это правка `sim`, сейва и миграции сейвов одновременно (REL-09): счётчики
живут в `RunState` и попадают в `run_state.to_dict()`. Обратная совместимость
держится на `d.get(ключ, значение_по_умолчанию)` в `from_dict`, а не на смене
`save_version`: смена мажора отвергает сейв целиком.

### 3.3 Команды игрока (autoload/game.gd) — единственный вход в sim
```gdscript
func cmd_new_run(seed_value: int = 0) -> void
func cmd_recall(hard: bool = false) -> void
func cmd_set_policy(policy: int, value: int) -> void
func cmd_place_building(def_id: String, cell: Vector2i) -> bool  # false = невалидно
func cmd_demolish(building_id: int) -> void
func cmd_repair(building_id: int) -> void   # приказ «починить сейчас»: ремонт вне очереди
func cmd_set_beacon(cell: Vector2i) -> void
func cmd_pick_card(card_id: String) -> void
func cmd_set_speed(mult: int) -> void            # 0,1,2,3
func cmd_leave_early() -> void
func cmd_surrender() -> void                     # немедленный run_ended(WIPE) по решению игрока
func cmd_save() -> void / cmd_load() -> bool     # тонкие обёртки над SaveService
# НЕ-командные методы Game (вне sim):
func has_save() -> bool
func rebroadcast_state() -> void                 # после load: повторная эмиссия agent_spawned и т.п. для UI
func resume_prev_speed() -> void                 # снятие автопаузы Итога цикла/драфта: вернуть скорость, бывшую до паузы
func push_pause() -> void / pop_pause() -> void  # автопауза СЧЁТЧИКОМ: два окна подряд не снимут паузу раньше времени
func note_banner(type: int) -> bool              # банер этого кризиса ещё не показывали за забег (ui-секция сейва)
# Карточки-уроки живут НЕ здесь: «показано один раз» относится к игроку, а не
# к забегу, поэтому их помечает Meta.note_hint(id) в профиле (docs/03 §6).
```

**Синхронные запросы (`query_*`) — единственный разрешённый «pull» из sim.**
Только чтение, только через `Game`, только по месту, где поток событий не годится
(срез данных для окна, валидация клетки под курсором). Sim об UI по-прежнему не знает.
```gdscript
func query_agent(id: int) -> Dictionary          # срез агента для AgentCard и AgentView
func query_agent_pos(id: int) -> Vector2         # мировая позиция агента (каждый кадр)
func query_creature_pos(id: int) -> Vector2      # то же для существа
func query_building(id: int) -> Dictionary       # состояние постройки для HUD и панелей
func query_can_place(def_id: String, cell: Vector2i) -> bool     # призрак размещения
func query_place_error(def_id: String, cell: Vector2i) -> String # причина отказа ключом локализации
func query_clock() -> Dictionary                 # фаза, цикл, тики до конца фазы, плато, объявленные кризисы
func query_totals() -> Dictionary                # остатки складов (стартовый запас приходит без события)
func query_dry_totals() -> Dictionary            # сухие остатки: «топливо-сухое» ≠ «плавник вообще»
```
Внутри sim команды применяются как `world.apply(SimCommand)` — очередь, разбирается в начале тика (детерминизм).

### 3.4 События наружу (sim/sim_event.gd)
`SimWorld.tick()` наполняет `events_out: Array[SimEvent]` (`{type: String, data: Dictionary}`). `Game` после тика: перебирает, эмитит соответствующие сигналы Events, очищает.

#### Промотка времени (дебаг, этап 19)

`Game.debug_fast_forward(ticks)` прогоняет тики внутри ОДНОГО кадра, поэтому во время промотки частые события (`Game.NOISY_EVENTS`: тик, уровень воды, апдейт агента, склад, ресурсы, депозит, состояние постройки) до интерфейса не доходят, а в конце промотки зовётся `rebroadcast_state()`. Отбрасывать можно только то, что восстанавливается из состояния мира: отчёты цикла и забега существуют один раз, и в этот список им нельзя (проверяется тестом `test_signals`). Без этого правила промотка целого забега разгоняла процесс до 2 ГБ и занимала минуты; с ним — 189 МБ и десять секунд.

### 3.5 Звук (autoload/audio_service.gd) — этап 17

Направление одно: **AudioService подписывается на Events сам**. Ни sim, ни HUD, ни панели не зовут `play_sfx` для событий мира — иначе один и тот же звук оказывается и в двух местах сразу, и нигде.

Два исключения, оба осознанные, и оба — про то, чего в шине сигналов нет:

```gdscript
AudioService.play_ui(id: String, volume_db: float = 0.0)  # щелчок виджета: тап, ОК, отмена, отказ размещения
AudioService.set_camera_mark(mark: float)                  # CameraRig -> вертикальный кроссфейд эмбиента
```

- У `PixelButton` звук нажатия задаётся полем `sound_id` (пустая строка — молчит: у «ОК» и «Отмены» свои звуки, и два щелчка на одно нажатие слышны как дефект).
- Троттлинг `set_camera_mark` (4 Гц) живёт внутри AudioService: камера не обязана знать про частоту.
- Громкости шин — только через `Settings` (`master/music/sfx/ui/ambient_db`). Раскладка шин собирается `tools/gen_bus_layout.gd`, стартовый баланс продублирован умолчаниями `Settings` — они обязаны совпадать, потому что `Settings.apply()` перезаписывает громкости шин.
- Разовые звуки молчат на перемотке (`Game.fast_forwarding`), лупы эмбиента — играют всегда.

### 3.6 Слои мира и время шейдеров (этап 18)

Порядок слоёв внутри `WorldViewport` — контракт: `CanvasLayer.layer` перебивает `z_index`, поэтому «поднять повыше» через z_index не выйдет.

```
WorldViewport (SubViewport 640×360)
└── World (Node2D, layer 0)      — параллакс (Parallax2D ×3), тайлмапы, депозиты,
    │                              постройки, существа, агенты, свет, частицы
    ├── FogLayer  (CanvasLayer 1)  — DepthFog
    ├── RainLayer (CanvasLayer 5)  — Rain
    └── WaterLayer (CanvasLayer 10) — WaterView (ЕДИНСТВЕННЫЙ screen-read шейдер)
Main
└── WeatherLayer (CanvasLayer 15) — Vignette (снаружи вьюпорта, нативное разрешение)
```

- Туман **под** водой: вода читает уже затуманенный мир и преломляет его.
- `Parallax2D` — прямые потомки `World`, НЕ на CanvasLayer: у слоя `follow_viewport_enabled = false`, и параллакс перестал бы получать движение камеры.
- Второй screen-read шейдер добавлять нельзя: каждый — ещё одна копия бэкбуфера.

**Время в шейдерах — только `global uniform float sim_time`.** Встроенный `TIME` не останавливается на паузе (док 4.7), а пауза — главная механика управления. Значение пишет `Game._push_shader_time()` каждый кадр как `тики / 10 + остаток аккумулятора`: на паузе стоит, на ×3 идёт втрое быстрее, после загрузки сейва продолжается с сохранённого тика. То же правило действует и на всё остальное в мире, что движется само: дрейф параллакса и кадр анимации агента считаются от `Game.sim_seconds()`, а не от реального времени. UI-анимации — наоборот, по реальному времени: на паузе интерфейс работает.

---

## 4. Цикл тика

```gdscript
# game.gd (упрощённо)
const TICKS_PER_SEC := 10
var _accum := 0.0
func _physics_process(delta: float) -> void:
    if speed == 0 or world == null: return
    _accum += delta * speed
    var step := 1.0 / TICKS_PER_SEC
    while _accum >= step:
        _accum -= step
        world.tick()                # 1 тик sim
        _flush_events()             # events_out -> Events.*
```
- `Engine.physics_ticks_per_second` остаётся 60 (физика не используется, но кадр стабилен); сим-тик — свой аккумулятор.
- Порядок систем внутри `SimWorld.tick()` ФИКСИРОВАН: `clock → tide → crisis → buildings → production → jobs → agents → storage(порча) → run_state`. Менять порядок нельзя (детерминизм).
- Интерполяция: View-ноды сглаживают позиции агентов между `agent_updated`/тиками локально (lerp по последним двум позициям); sim об этом не знает.

### 4.1 Моменты времени — такой же контракт, как порядок систем

Порядка систем мало: половина решений принимается не «в такой-то системе», а «в такой-то момент». Три из пяти главных находок ревью были именно про момент, а не про формулу (`review/03` ARCH-01). Поэтому моменты названы и зафиксированы здесь.

**Именованные моменты фазы**

| Момент | Где определён | Кто читает |
|---|---|---|
| **пик Высокой воды** — тик, на котором вода встаёт на плато HIGH | `SimClock.high_peak_tick()`, `at_high_peak()` | кривая `Tide._level_for`, прибытие судна и снимок очков `RunState.tick` |
| **конец Низкой воды** — момент, когда испаритель отдаёт соль | `production.on_phase_ended(LOW)` | `ProductionSystem._run_passive("low_phase")` |
| **конец Высокой воды = конец цикла** | `SimClock.tick()` | итог цикла, завершение забега |

⚠️ Число `Balance.HIGH_RISE_TICKS` больше нигде не считается вручную: два независимых определения «пика» и были дефектом SIM-01 (очки снимались, когда вода ещё стояла на уровне Сигнала).

**Порядок обработчиков границ** (`SimWorld.tick`, ветки `clock_events`). Он не произволен — вот от чего зависит каждая строка:

| # | Вызов | Обязан идти до/после | Почему |
|---|---|---|---|
| 1 | `storage/agents/jobs/production/crisis.on_cycle_ended` | до `run_state.end_cycle` | порча и сушка обязаны попасть в отчёт цикла, иначе итог показывает вчерашние числа |
| 2 | `run_state.end_cycle` | до `run_state.start_draft` (следующая ветка) | сбрасывает `cycle_modifiers`; иначе только что выбранная карта затирается |
| 3 | `run_state.auto_pick_if_needed` | на границе конца Спада | страховка от цикла без карты |
| 4 | `production.on_phase_ended(prev)` | **до** `buildings.on_phase_started(phase)` | испаритель читает `flooded_in_phase` за всю прошедшую фазу, а `on_phase_started` этот флаг сбрасывает |
| 5 | `tide.reset_cycle_high()` | до `crisis.on_cycle_started` | иначе сизигия увидит максимум вчерашнего цикла |

**Момент внутри тика.** `run_state.tick` зовётся **после** `tide.update`: снимок очков считается по уровню воды этого тика, а не прошлого. Обработчики `phase_changed`, наоборот, идут **до** `tide.update` — они видят уровень предыдущего тика, и рассчитывать на «свежую» воду в них нельзя.

⚠️ На конце HIGH часы **уже** перевели счётчик цикла: в `on_phase_ended(HIGH)` закончился цикл `clock.cycle − 1`.

## 5. Данные (.tres)

- Каждый деф — `Resource` с `class_name` (`ItemDef`, `BuildingDef`, `RecipeDef`, `TraitDef`, `CardDef`, `UnlockDef`, `CliffDef`), поля — `@export`.
- `DB` (data/db.gd): при старте грузит все дефы из папок сканированием папки через `DirAccess` (files ending .tres); доступ `DB.item(id)`, `DB.building(id)`…
- Дефы **иммутабельны в рантайме** (это shared-инстансы!). Всё изменяемое живёт в sim-состоянии, никогда в Resource. `resource_local_to_scene` не используем.
- Баланс-числа, не привязанные к конкретному дефу, — в `Balance` (const). Никаких магических чисел в коде систем.

## 6. Сейвы

- JSON (`JSON.stringify/parse`), файл `user://save_run.json` + `user://profile.json`.
- Каждый sim-класс реализует `to_dict() -> Dictionary` / `from_dict(d) -> void`. `SimWorld.to_dict()` собирает всё + `save_version` + состояние RNG (`rng.state`).
- НЕ использовать `var_to_bytes`/`store_var` с объектами и `ResourceLoader` для сейвов (риск инъекции кода и хрупкость). Только словари примитивов.
- Загрузка: проверка `save_version`; несовпадение мажора → отказ с сообщением.

## 7. Тесты

- Без сторонних аддонов: свой мини-раннер `tests/run_all.gd` (extends SceneTree): создаёт `SimWorld` с фиксированным сидом, гоняет сценарии, `assert`-хелперы, выход с кодом 0/1.
- Запуск: `tools/run_tests.sh` (агент обязан прогонять в конце этапа). Фильтр по имени сьюта — аргументом: `tools/run_tests.sh production`.
- Обязательный смоук: 1 полный забег на автопилоте (дефолтные политики, без ввода) не крашится и завершается судном/вайпом; хеш состояния на тике N стабилен между двумя прогонами с одним сидом (детерминизм).

### 7.1 Рантайм-ошибки валят прогон

⚠️ `check()` — не единственный источник провала. `tests/error_guard.gd` (наследник `Logger`, регистрируется через `OS.add_logger` до первого сьюта) считает ошибки движка и **валит прогон при любой `SCRIPT ERROR`**.

Почему это обязательная часть раннера: `buffer_take` падал на каждом вызове одиннадцать этапов подряд — **365 `SCRIPT ERROR` за прогон при полностью зелёном отчёте**, потому что раннер проверял только свои `check()`, а stderr для него невидим (`docs/BUG-salt-chain.md`).

Разделение по типам намеренное:

| Тип | Источник | Валит прогон |
|---|---|---|
| `ERROR_TYPE_SCRIPT`, `ERROR_TYPE_SHADER` | рантайм GDScript, шейдеры | **да** |
| `ERROR_TYPE_ERROR` | `push_error` — мягкие отказы кода, `TestCtx.check` при провале, тесты этих отказов | нет (провал `check` виден и так) |
| `ERROR_TYPE_WARNING` | `push_warning` | нет |

`tools/run_tests.sh` дублирует проверку грепом по stderr — вторым рубежом на случай, когда `Logger` недоступен (движок старше 4.5) или ошибка возникла до регистрации логгера.

## 8. Код-стайл

- GDScript, **статическая типизация везде**: переменные, аргументы, возвраты, типизированные массивы `Array[int]` и словари `Dictionary[String, int]` (4.4+).
- Файлы snake_case; `class_name` PascalCase; сигналы — прошедшее время (`cycle_ended`); приватное — `_prefix`.
- Отступы — табы (стандарт Godot). Комментарии по-русски, краткие, только «почему», не «что».
- Ноды в сценах — PascalCase (`TideGauge`, `RecallButton`).
- Никаких абсолютных путей нод в коде UI-компонентов (`$"/root/..."` запрещён, кроме автолоадов).
- Строки UI — только через `tr()` и ключи `res://assets/i18n/` (CSV), с первого этапа UI.

## 9. Пиксель-арт настройки проекта (фиксируются на этапе 00)

- `rendering/textures/canvas_textures/default_texture_filter = Nearest`
- Разрешение и stretch — по [01-ui-spec.md] (§ «Разрешение»): мир в SubViewport 640×360, UI нативный.
- `rendering/2d/snap/snap_2d_transforms_to_pixel = true` для мирового вьюпорта.
- Импорт текстур: filter off, mipmaps off.
- Renderer: **Mobile** (Forward+ не нужен для 2D, Mobile легче на всех целях) — если 2D-света работают корректно; иначе gl_compatibility. Решение на этапе 00, зафиксировать в README проекта.

---

## 10. Находки ресерча, обязательные к учёту (август 2026)

- **Версия движка: Godot 4.7.x stable** (4.7 — 18.06.2026, патчи 4.7.1/4.7.2). Ветку 4.8-dev не использовать. Полезное из недавних версий: типизированные словари (4.4), chunked tilemap physics (4.5), `@abstract` классы (4.5), Scene Paint Mode и one-way collision на шейпе (4.7).
- **Сигналы «теряются молча»:** несовместимая сигнатура обработчика не вызывается, warning только в debug-сборке. Поэтому: сигнатуры обработчиков всегда типизированы и совпадают с декларацией в Events; смоук-тест подписок обязателен.
- **Resource шарится по ссылке.** `load()` возвращает закэшированный инстанс; мутация «загруженного» дефа мутирует его для всех. Дефы — read-only; `duplicate(true)` в 4.5+ переписан (`duplicate_deep`, известные регрессии) — глубокое копирование ресурсов не использовать вовсе (не нужно при read-only дефах).
- **`preload()` держит ресурс в памяти навсегда** — для дефов это ок (они маленькие), для тяжёлых сцен использовать `load()`.
- **Сейвы — безопасность:** никогда не грузить пользовательские файлы через `ResourceLoader`/`ConfigFile`/`get_var(true)` (исполнение встроенного кода). Только `JSON.parse` словарей примитивов; Godot-типы (Vector2i) сериализуем вручную (`[x, y]`).
- **Против Godot-3-измов:** в Project Settings включить `debug/gdscript/warnings/untyped_declaration = Error` и treat-warnings-as-errors по списку; полный список переименований 3→4 — в prompts/CONVENTIONS.md.
- **Физика движка не используется и недетерминирована** — навигация и «коллизии» только своей логикой по графу (это уже наше правило, ресерч подтвердил).
- **Тесты:** самописный headless-раннер (см. §7) — осознанный выбор вместо GUT/GdUnit4: нулевые зависимости, достаточно для sim-ядра. Если позже захочется полноценный фреймворк — GdUnit4 v6.2+ (живой, официальный GitHub Action). Перед headless-прогоном в CI обязателен `godot --headless --import --quit` (иначе тесты падают на кэше импорта).
- **`_ready/_process` в 4.x не зовут родительские неявно** — при наследовании сцен вызывать `super()`.
