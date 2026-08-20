# 25 — Приёмы из других движков и игр, которые ложатся на TIDEBOUND

**Для этапов:** сквозной документ; конкретные привязки — в колонке «Куда».
**Дата ресерча:** 2026-08-21.

Здесь только то, что **переносится дёшево** и не противоречит docs/02. Приёмы, требующие переписать архитектуру (ECS, многопоточность, behavior trees на нодах), включены отдельным разделом «Что НЕ брать» — чтобы агент не потратил на них время, наткнувшись в интернете.

---

## 1. Сводная таблица

| # | Приём | Откуда | Как ложится к нам | Куда |
|---|---|---|---|---|
| 1 | Fixed timestep + аккумулятор + интерполяция вида | Gaffer On Games, любой сетевой движок | уже в docs/02 §4; добавить защиту от спирали смерти | 01, 05 |
| 2 | Deterministic lockstep: команды в очередь, состояние из тика | Age of Empires, Factorio, StarCraft | `apply_command` → очередь → разбор в начале тика | 01, 11, 19 |
| 3 | Хеш состояния каждые N тиков + лог расхождений | Factorio (десинк-репорты) | `state_hash` каждые 500 тиков в тесте | 01, 19 |
| 4 | Data-driven дефы: `ScriptableObject` | Unity | 1:1 = `Resource` + `class_name` + `.tres` | 04, 07, 08, 10, 11 |
| 5 | Прототипы + генерация данных скриптом | Factorio (Lua-прототипы), Paradox (script-файлы) | `EditorScript`-генератор `.tres` из таблицы в коде | 04, 07, 08, 10, 11 |
| 6 | Утилитарный ИИ: объекты «рекламируют» полезность | The Sims | `JobSystem` порождает задачи из мира; агент только выбирает | 06 |
| 7 | Резервирование цели | RimWorld (`ReservationManager`) | `job.taken_by` ⟺ `agent.job_id` | 06, 07, 08 |
| 8 | Двухуровневый приоритет: класс работы × важность объекта | Oxygen Not Included (priority + sub-priority) | `policy_weight × base` | 06 |
| 9 | Unidirectional data flow: команды вниз, события вверх | Flux/Redux (веб), MVU | `Game.cmd_*` / `Events` — уже в docs/02 §1 | всё UI |
| 10 | View-model проекция вместо прямой модели | MVVM (WPF/Unity UI Toolkit) | `to_view_dict()` ≠ `to_dict()` | 11, 14 |
| 11 | Snapshot/golden-master тестирование | Approvals, Jest snapshots | сравнение `to_dict` с эталоном по сиду | 01, 11, 19 |
| 12 | Версионированная схема сейва + миграции | Stardew Valley, Factorio | `save_version` + отказ при мажорном расхождении | 11 |
| 13 | Атомарная запись сейва (tmp + rename) | все, кто терял сейвы игроков | `write_json_atomic` | 11 |
| 14 | Подсказки-линии от призрака к источникам ресурсов | Against the Storm | `Line2D` от призрака к складам | 14 |
| 15 | Вертикальный слоёный эмбиент, равномощностный кроссфейд | Wwise/FMOD, Inside, Hollow Knight | два лупа, микс по Y камеры через `cos/sin` | 17 |
| 16 | «Тик — единственные часы мира» | Dwarf Fortress, Factorio | запрет `Time.*` в `sim/` — уже в CONVENTIONS | 01–11 |
| 17 | Пул задач, перестраиваемый по событиям, а не по таймеру | ONI, RimWorld | `_dirty`-флаг `JobSystem` | 06 |
| 18 | Blackboard: общий изменяемый контекст цикла | Unreal BT, Unity NodeCanvas | `SimWorld.cycle_modifiers` (уже требуется промптом 10) | 10 |
| 19 | Feature-флаг скина одной константой | дизайн-системы (Figma tokens → CSS vars) | `USE_ATLAS` в `theme_builder` | 12, 18 |
| 20 | «Страница стилей» / Storybook | веб (Storybook), Unity UI Toolkit samples | `_gallery.tscn` | 12 |

---

## 2. Пять приёмов, которые стоит расписать подробнее

### 2.1 Команды как данные (lockstep)

**Откуда:** RTS-сети. Классика — «1500 Archers on a 28.8» (Age of Empires): по сети гоняются не позиции юнитов, а команды игрока; состояние воспроизводится из тика + команд.

**Что даёт нам (сети у нас нет):**
- **Реплей и баг-репорт бесплатно.** Сид + список команд с номерами тиков = полное воспроизведение забега. Файл на килобайты вместо сейва.
- **Автотест игрового сценария.** Приёмки вида «полный цикл: place → принесли → построили» пишутся как список команд, а не как императивный код.

**Как заложить дёшево (этап 01, ~20 строк):**
```gdscript
## SimWorld
var command_log: Array[Dictionary] = []          # только в debug

func apply_command(cmd: Dictionary) -> void:
	if OS.is_debug_build():
		command_log.append({"t": clock.total_ticks(), "cmd": cmd.duplicate()})
	_commands.append(cmd)
```
и воспроизведение:
```gdscript
static func replay(seed_value: int, log: Array[Dictionary], until_tick: int) -> SimWorld:
	var w := SimWorld.new(); w.new_run(seed_value)
	var i: int = 0
	while w.clock.total_ticks() < until_tick:
		while i < log.size() and int(log[i]["t"]) == w.clock.total_ticks():
			w.apply_command(log[i]["cmd"]); i += 1
		w.tick(); w.events_out.clear()
	return w
```
⚠️ `OS.is_debug_build()` в `sim/` формально нарушает «чистоту» ядра. Обходится передачей флага в конструктор `SimWorld.new(record: bool)`. **Так и сделать.**

### 2.2 Golden-master тестирование

**Откуда:** снапшот-тесты в вебе (Jest), Approvals в .NET.

**Идея:** вместо десятков ассертов «на 3000-м тике у агента должно быть satiety 47» сохранить эталонный `to_dict()` в файл и сравнивать целиком. Любое непреднамеренное изменение поведения подсвечивается сразу.

```gdscript
# tests/test_golden.gd
const GOLDEN: String = "res://tests/golden/run_42_t5000.json"

static func test_golden(t: TestCtx) -> void:
	var w := t.fixture_world(42)
	t.run_ticks(w, 5000)
	var now: String = JSON.stringify(w.to_dict(), "\t")   # с отступами: читаемый дифф
	if not FileAccess.file_exists(GOLDEN):
		# первый прогон записывает эталон — но ГРОМКО, чтобы не пропустить
		FileAccess.open(GOLDEN, FileAccess.WRITE).store_string(now)
		push_warning("golden создан заново — проверить глазами и закоммитить!")
		return
	var was: String = FileAccess.open(GOLDEN, FileAccess.READ).get_as_text()
	t.check(was == now, "поведение изменилось — см. дифф golden-файла в git")
```
**Плюс:** эталон лежит в git, и `git diff` показывает **что именно** изменилось в поведении после правки.
**Минус:** ложные срабатывания при легитимных изменениях баланса. **Правило: обновление golden-файла — отдельный коммит с объяснением в сообщении.**

⚠️ Использовать `indent = "\t"` (а не компактный) именно ради читаемого диффа — это тестовый артефакт, не сейв.

### 2.3 View-model проекция (MVVM)

**Откуда:** WPF/MVVM, Unity UI Toolkit, веб-фронтенд.

**Проблема, которую решает:** UI, читающий модель напрямую, «прирастает» к её внутренностям. Через два этапа рефакторинг sim ломает три панели.

**Решение:** у sim-сущности две проекции — `to_dict()` (для сейва, полная) и `to_view_dict()` (для UI, стабильная и урезанная). Они меняются независимо.

Промпт 14 фактически требует именно этого (`Game.query_agent`). Стоит распространить на постройки и склады: `query_building(id)`, `query_storage(id)`. **Три функции на этапе 11–14 — и этапы 13–15 перестают зависеть от внутренностей sim.**

### 2.4 Blackboard для модификаторов цикла

**Откуда:** Unreal Behavior Tree Blackboard, Unity NodeCanvas.

`SimWorld.cycle_modifiers: Dictionary[String, float]` — общий «доска объявлений» на цикл: карты вылазки (этап 10), сизигия, шторм пишут туда, системы читают. Ключевые правила:
- **читают через геттер с дефолтом:** `w.cycle_modifiers.get("gather_speed_mult", 1.0)`;
- **сбрасывается ровно в одном месте** — конец цикла в `run_state`;
- **ключи — в `const`-массиве** и валидируются тестом (тот же приём, что для `TraitKeys`, doc 14 §1.1).

Без доски эффекты карт расползутся по пяти системам и будут забываться при сбросе.

### 2.5 Против «пересчитывать всё каждый кадр»

**Откуда:** ONI/RimWorld — обе игры считают работы «по событию», а не «по таймеру»; веб-фронтенд — тот же приём под именем dirty-checking.

Три места, где это критично именно у нас:
1. `JobSystem._dirty` (doc 16 §2);
2. `DebugOverlay._dirty` (doc 13 §2.1);
3. `BuildGhost` — только при смене клетки (doc 17 §3).

Общий шаблон: **флаг + пересчёт в начале следующего тика/кадра**, а не немедленный пересчёт в обработчике. Немедленный пересчёт внутри обработчика события — это скрытый рекурсивный вызов и источник неопределённого порядка.

---

## 3. Что НЕ брать (и почему), хотя интернет советует

| Приём | Кто советует | Почему нам нельзя |
|---|---|---|
| **ECS** (Unity DOTS, bevy, godot-ecs аддоны) | «правильная» архитектура симуляций | наш масштаб — 6 агентов; ECS даёт выигрыш от тысяч сущностей, а стоит полной переделки sim и усложнения сериализации |
| **Behavior Trees на нодах** (LimboAI, Beehave) | стандартный совет для ИИ в Godot | ноды в `sim/` запрещены (docs/02 §1); дерево не сериализуется в JSON; тик привязан к `_process` |
| **Физика/навигация движка** (`NavigationAgent2D`, `Area2D`) | стандартный совет для движения | физика недетерминирована (docs/02 §10); граф из 30 узлов не нуждается в навмеше |
| **Многопоточность** (`WorkerThreadPool`) | «ускорить симуляцию» | бюджет тика 2 мс при нагрузке ~0.1 мс; потоки ломают детерминизм порядка |
| **`ResourceLoader` для сейвов** | множество туториалов «save with Resource» | исполнение произвольного кода из чужого файла (docs/02 §6) |
| **Глобальный `Engine.time_scale` для ускорения ×2/×3** | очевидное решение | ломает Tween'ы, звук и UI; скорость у нас = число тиков за кадр |
| **`get_tree().paused` для тактической паузы** | очевидное решение | остановит UI и анимации; пауза у нас = `speed = 0` |
| **Аддоны на UI-тему/инспектор** | ускорить вёрстку | лишняя зависимость; `theme_builder` из кода (doc 19 §2) решает ту же задачу и версионируется в git |
| **GUT/GdUnit4 на старте** | «нормальный тест-фреймворк» | docs/02 §7 выбрал свой раннер (ноль зависимостей); переход возможен позже, если понадобится |

---

## 4. Три идеи «для вкуса», дешёвые и заметные

Не механики (промпты запрещают новые фичи), а **техническая реализация уже запланированного**, подсмотренная у других:

1. **Кадр-задержка на важных событиях (hit-stop).** При смерти агента / прорыве воды — 3–4 кадра `Engine.time_scale`… нет, у нас запрещён. **Аналог: пропуск отрисовки интерполяции View на 3 кадра** — визуально читается как «удар», стоит 5 строк в `agent_view.gd`. Приём из фехтовальных игр (Hollow Knight, Celeste).
2. **Диегетический прогресс работы** — не прогресс-бар над головой, а изменение самой картинки (стройка «растёт» снизу вверх маской). У нас уже есть прогресс стройки; отрисовать его через `draw_rect` с клипом — та же стоимость, что бар, но выглядит на порядок дороже. Приём из Against the Storm / Timberborn.
3. **Единая «валюта внимания»: тосты, банеры и подсказки не спорят.** У Frostpunk и Against the Storm это решено приоритетной очередью: одновременно на экране максимум одно «важное» сообщение. У нас три независимых канала (тост/банер/HintCard) — **стоит завести один `NotificationQueue` с приоритетами** на этапе 13, иначе на 15-м они начнут накладываться. Дёшево сейчас, дорого потом.

---

## Источники

- [Fix Your Timestep! — Gaffer On Games](https://gafferongames.com/post/fix_your_timestep/)
- [Deterministic Lockstep — Gaffer On Games](https://gafferongames.com/post/deterministic_lockstep/)
- [Factorio Friday Facts #340 «Deep desyncs»](https://forums.factorio.com/viewtopic.php?t=82891) — как ловят рассинхрон хешами
- [The Genius AI Behind The Sims — GMTK](https://gmtk.substack.com/p/the-genius-ai-behind-the-sims)
- [An Introduction to Utility Theory — Game AI Pro гл. 9 (PDF)](https://www.gameaipro.com/GameAIPro/GameAIPro_Chapter09_An_Introduction_to_Utility_Theory.pdf)
- [RimWorld AI: ThinkTree/JobGiver](https://github.com/CBornholdt/RimWorld-AI-Tutorial/wiki/Part-1---Introduction), [How Pawns Think](https://github.com/roxxploxx/RimWorldModGuide/wiki/SHORTTUTORIAL:-How-Pawns-Think)
- [Oxygen Not Included — Errand / Priority](https://oxygennotincluded.fandom.com/wiki/Errand)
- [Utility system — Wikipedia](https://en.wikipedia.org/wiki/Utility_system)
- [LimboAI](https://github.com/limbonaut/limboai), [Beehave](https://github.com/bitbrain/beehave) — что не берём и почему
- [awesome-godot](https://github.com/godotengine/awesome-godot) — каталог аддонов, если понадобится искать точечно
