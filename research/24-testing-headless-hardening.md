# 24 — Тесты, headless-раннер, soak, стабилизация

**Для этапов:** 00 п.9 (скелет раннера), каждый этап (обязательный финал), 19 (весь).
**Дата ресерча:** 2026-08-21. **Движок:** Godot 4.7.x stable.

Готовый код раннера — [`code/run_all.gd`](code/run_all.gd) и [`code/test_ctx.gd`](code/test_ctx.gd). Переносить как есть на этапе 00.

---

## 1. Ловушка №1: `assert` вырезается в release-сборке

Документация GDScript про `assert`: *«Ignored in non-debug builds»*.

Следствие: тест, написанный на `assert`, в release-экспорте **пройдёт всегда**, не проверив ничего. Для нашего раннера (запускается debug-бинарём) это не проблема сегодня, но становится ею, как только тесты попадут в CI на экспортированный шаблон.

**Правило: свой `check()`, никакого `assert` в `tests/`.**
```gdscript
func check(cond: bool, msg: String) -> void:
	_total += 1
	if cond: return
	_failed += 1
	_failures.append("%s :: %s" % [_current_test, msg])
	push_error("FAIL %s :: %s" % [_current_test, msg])
```
`assert` остаётся уместным **внутри `sim/`** как контрактная проверка инварианта в разработке — там его вырезание в релизе как раз желательно.

---

## 2. Раннер: `SceneTree`, коды выхода, порядок

```gdscript
extends SceneTree
## tests/run_all.gd — godot --headless -s res://tests/run_all.gd

const SUITES: Array[String] = [
	"res://tests/test_data.gd",       # первым: битые дефы валят всё остальное
	"res://tests/test_clock.gd",
	"res://tests/test_terrain.gd",
	"res://tests/test_storage.gd",
	"res://tests/test_agents.gd",
	"res://tests/test_jobs.gd",
	"res://tests/test_buildings.gd",
	"res://tests/test_production.gd",
	"res://tests/test_crises.gd",
	"res://tests/test_cards.gd",
	"res://tests/test_save.gd",
	"res://tests/test_signals.gd",
]

func _initialize() -> void:
	var ctx := TestCtx.new()
	var t0: int = Time.get_ticks_msec()
	for path: String in SUITES:
		if not ResourceLoader.exists(path):
			print("SKIP (нет файла): ", path)     # этапы добавляют сьюты по мере готовности
			continue
		var script: GDScript = load(path)
		ctx.run_suite(script)
	var ms: int = Time.get_ticks_msec() - t0
	ctx.print_report(ms)
	quit(0 if ctx.failed == 0 else 1)
```

**Технические факты:**
- `-s`/`--script` требует наследника `SceneTree` или `MainLoop`; точка входа — `_initialize()`.
- `quit(code)` не завершает процесс мгновенно — движок доработает кадр. Вызывать **один раз**.
- **`SKIP` вместо падения на отсутствующем файле** — иначе раннер, написанный на этапе 00, сломается до этапа 01. Это делает раннер пригодным с первого дня.
- **Порядок сьютов фиксирован**, `test_data` первым: если `.tres` битые, остальные падения будут вторичными и запутают диагностику.

**Формат вывода — машиночитаемый и человекочитаемый одновременно:**
```
[test_clock] determinism ............ OK   (2143 checks)
[test_save]  round_trip .............. FAIL
   round_trip :: to_dict после from_dict отличается на ключе agents/0/satiety
---
120 checks, 1 failed, 842 ms
TESTS FAILED
```
Строка `TESTS OK` / `TESTS FAILED` в конце — чтобы CI и человек одинаково быстро видели итог.

---

## 3. Обязательный `--import` перед прогоном

```bash
godot --headless --import --quit && godot --headless -s res://tests/run_all.gd
```
docs/02 §10: *«Перед headless-прогоном в CI обязателен `godot --headless --import --quit` (иначе тесты падают на кэше импорта)»*. Это же касается **любой** машины, где `.godot/` не собран — включая свежий клон у другого агента.

**Скрипт, который стоит положить в `tools/test.sh` на этапе 00:**
```bash
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/../godot"
godot --headless --import --quit >/dev/null 2>&1 || true
godot --headless -s res://tests/run_all.gd
```
`|| true` на импорте — импорт печатает предупреждения и иногда возвращает ненулевой код на пустом проекте; настоящая проверка — сам прогон.

---

## 4. Что должен уметь `TestCtx`

Помимо `check`:

```gdscript
func check_eq(a: Variant, b: Variant, msg: String) -> void      # печатает ОБА значения
func check_approx(a: float, b: float, eps: float, msg: String) -> void
func check_hash(w1: SimWorld, w2: SimWorld, msg: String) -> void
func fixture_world(seed_value: int) -> SimWorld                 # общий стартовый мир
func run_ticks(w: SimWorld, n: int) -> void                     # тикает и чистит events_out
```

⚠️ **`run_ticks` обязан чистить `events_out`.** Иначе за 20 000 тиков накопится сотня тысяч `SimEvent`, тест съест память и станет медленным — а причина будет неочевидна.

⚠️ **`check_eq` печатает оба значения.** «FAIL: значения не равны» — бесполезное сообщение; «ожидалось 3000, получено 2999» — диагноз.

**Хелпер «найди тик расхождения» окупается многократно:**
```gdscript
func find_divergence(seed_value: int, max_ticks: int) -> int:
	var a := fixture_world(seed_value)
	var b := fixture_world(seed_value)
	for i: int in max_ticks:
		run_ticks(a, 1); run_ticks(b, 1)
		if state_hash(a) != state_hash(b):
			return i
	return -1
```
Он тяжёлый (хеш на каждом тике), поэтому запускается вручную при расследовании, а не в общем прогоне.

---

## 5. Тесты, измеряющие время — только в тиках

Приёмки говорят «за 5 секунд», «1 ед./2 с», «на 25% быстрее». **Все они переводятся в тики и сравниваются целыми числами.**

```gdscript
# ПЛОХО: зависит от скорости машины и float
t.check(elapsed_sec >= 4.9 and elapsed_sec <= 5.1, "...")
# ХОРОШО: детерминировано
t.check_eq(death_tick - submerge_tick, 50, "утопление ровно 5 с = 50 тиков")
```
`Time.*` в тестах допустим только для измерения **производительности** (мс на тик), не поведения.

---

## 6. Soak-тест (этап 19 п.1)

```gdscript
# tests/soak.gd — godot --headless -s res://tests/soak.gd
extends SceneTree

const RUNS: int = 20

func _initialize() -> void:
	var rows: Array[String] = ["seed,cycles,outcome,points,alive,deaths,drowned,ms"]
	var errors: int = 0
	for i: int in RUNS:
		var seed_value: int = 1000 + i * 7919          # простое: разнообразные сиды
		var t0: int = Time.get_ticks_msec()
		var w := SimWorld.new()
		w.new_run(seed_value)
		var guard: int = 0
		while not w.run_state.is_over() and guard < 60_000:
			w.tick(); w.events_out.clear(); guard += 1
		if guard >= 60_000:
			push_error("забег %d не завершился за 60000 тиков" % seed_value)
			errors += 1
		var r: Dictionary = w.run_state.report()
		rows.append("%d,%d,%s,%d,%d,%d,%d,%d" % [seed_value, r["cycles"], r["outcome"],
			r["points"], r["alive"], r["deaths"], r["drowned"],
			Time.get_ticks_msec() - t0])
	var f := FileAccess.open("res://../docs/soak.csv", FileAccess.WRITE)
	f.store_string("\n".join(rows))
	f.close()
	print("soak: %d забегов, ошибок: %d" % [RUNS, errors])
	quit(0 if errors == 0 else 1)
```

⚠️ **Guard-счётчик обязателен.** Забег, который не заканчивается (баг в `run_state`), иначе повесит CI навсегда.

⚠️ **Ловля `push_error` в тесте.** Штатно `push_error` не роняет прогон. Чтобы soak был честным, нужен счётчик ошибок:
```gdscript
# В Game/SimWorld — счётчик, инкрементируемый везде, где вызывается push_error.
# Проще: в тесте перед прогоном подменить логгер нельзя, поэтому
# ВСЕ push_error в проекте идут через один хелпер:
class_name Log
static var error_count: int = 0
static func err(msg: String) -> void:
	error_count += 1
	push_error(msg)
```
**Ввести `Log.err()` на этапе 01 и использовать везде** — тогда «ни одного краша/ошибки» из приёмки этапа 19 становится проверяемым числом, а не впечатлением.

CSV — это одновременно и заготовка баланс-данных: распределение очков по 20 сидам сразу покажет, слишком ли легко/тяжело.

---

## 7. Память и орфаны (этап 19 п.4)

```gdscript
func memory_snapshot() -> Dictionary:
	return {
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"static_mem": Performance.get_monitor(Performance.MEMORY_STATIC),
	}
```
**Тест «три забега подряд»:**
```gdscript
var base: Dictionary = memory_snapshot()
for i: int in 3:
	Game.cmd_new_run(100 + i)
	# ... промотать забег ...
	await_run_end()
var after: Dictionary = memory_snapshot()
t.check(int(after["nodes"]) - int(base["nodes"]) < 50, "ноды копятся между забегами")
t.check(int(after["orphans"]) == 0, "есть орфан-ноды")
```
⚠️ `print_orphan_nodes()` печатает список, но **работает только в debug-сборке** и ничего не возвращает — для теста нужен именно `Performance.OBJECT_ORPHAN_NODE_COUNT`.

**Три главных источника утечек в нашем проекте:**
1. View-ноды, не удалённые при `run_ended` (research/15 §6.2);
2. тосты, накопившиеся при промотке (`fast_forwarding`-флаг, doc 13 §8);
3. **подписки на `Events` от узлов, которые уже освобождены.** Godot автоматически отключает сигналы при `free`, но **`Callable` от лямбды, захватившей узел, продлевает ему жизнь**. Правило: лямбды в `connect` — только для сигналов, живущих столько же, сколько узел; для остального — методы.

---

## 8. Санитария сигналов (этап 19 п.3)

```gdscript
# tests/test_signals.gd
static func test_all_signals_used(t: TestCtx) -> void:
	var never_listened: Array[String] = []
	for sig: Dictionary in Events.get_signal_list():
		var name: String = sig["name"]
		if Events.get_signal_connection_list(name).is_empty():
			never_listened.append(name)
	# Не FAIL, а предупреждение: часть сигналов законно не слушается до своего этапа
	if not never_listened.is_empty():
		print("WARN: сигналы без слушателей: ", never_listened)

static func test_all_signals_emitted(t: TestCtx) -> void:
	# Прогнать полный забег и собрать множество эмитированных типов SimEvent
	var emitted: Dictionary[String, bool] = {}
	# ... подписка-шпион на все сигналы (doc 13 §6) ...
	t.check(Log.error_count == 0, "в забеге были push_error")
```
⚠️ **«Сигнал без слушателей» — предупреждение, не ошибка.** `Events` объявляет все сигналы сразу (контракт docs/02 §3.2), и до этапа 13 половину действительно никто не слушает. Превратить в ошибку можно только на этапе 19.

**Проверка совпадения сигнатур** делается движком, но молча (docs/02 §10). Единственный надёжный способ — прогон с проверкой, что обработчик реально вызвался. Спай-подписка из doc 13 §6 это и обеспечивает.

---

## 9. Краевые случаи (этап 19 п.5) — как проверять

| Случай | Как воспроизвести в тесте |
|---|---|
| Битый сейв | записать валидный, обрезать файл на 60% длины, `load_run()` → `false`, без краша |
| Сейв в момент смерти агента | промотать до тика смерти (найти в предыдущем прогоне), сохранить ровно там |
| Выход во время драфта | `draft_ready` → `save_run()` → перезапуск → драфт должен восстановиться |
| Пауза во время подъёма воды | `cmd_set_speed(0)` в HIGH, 600 кадров, уровень не изменился |
| Окно 800×600 и 3840×2160 | `DisplayServer.window_set_size` + скриншот, проверка что HUD не наезжает |

⚠️ **Тест «выход во время драфта» ловит реальный баг:** `drafted_this_cycle` и `active_card` должны быть в сейве, иначе после загрузки драфт либо повторится, либо пропадёт.

⚠️ **Окно 800×600 — ниже базового 1280×720.** `content_scale_factor` при `expand` уменьшит UI, но `TOUCH_MIN=48` станет 30 экранными пикселями. Это допустимо на десктопе, но проверить, что текст не сливается.

---

## 10. CI (необязательно, но дёшево)

```yaml
# .github/workflows/tests.yml
name: tests
on: [push, pull_request]
jobs:
  headless:
    runs-on: ubuntu-latest
    container: barichello/godot-ci:4.7.0      # или свой образ с той же версией
    steps:
      - uses: actions/checkout@v4
      - run: godot --headless --import --quit || true
        working-directory: godot
      - run: godot --headless -s res://tests/run_all.gd
        working-directory: godot
```
⚠️ **Версия образа обязана совпадать с версией движка проекта.** Godot 4.8-dev не гарантирует совместимость `.tres` и падает на `@abstract`/типизированных словарях иначе.

---

## 11. Чек-лист приёмки этапа 19

- [ ] 20/20 soak-забегов завершились; `Log.error_count == 0`; CSV в `docs/soak.csv`.
- [ ] Grep-аудит `sim/` (research/11 §10) даёт ноль совпадений.
- [ ] Хеш-тест детерминизма зелёный **после каждой** системы, не только суммарно.
- [ ] Отчёт по сигналам: нет сигналов без слушателей (на этом этапе — уже ошибка).
- [ ] 3 забега подряд: прирост нод < 50, орфанов 0.
- [ ] Все 5 краевых случаев обработаны явно и покрыты тестом.
- [ ] Обе локали прогнаны: нет сырых ключей, нет вылезающего текста.
- [ ] `docs/backlog.md` собран из всех `TODO` проекта с приоритетами.
- [ ] Бюджет тика ≤ 2 мс на 12-м цикле полного забега (график в дебаг-панели).

---

## Источники

- [GDScript reference](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html) — `assert` игнорируется в не-debug сборках
- [SceneTree](https://docs.godotengine.org/en/stable/classes/class_scenetree.html) — `_initialize`, `quit`
- [Command line tutorial](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html) — `--headless`, `--script`, `--import`, `--quit`
- [Performance](https://docs.godotengine.org/en/stable/classes/class_performance.html) — `OBJECT_ORPHAN_NODE_COUNT`, `MEMORY_STATIC`
- docs/02 §7, §10 — самописный раннер как осознанный выбор; обязательный `--import` в CI
- [GdUnit4](https://github.com/MikeSchulze/gdUnit4) — если позже понадобится полноценный фреймворк (docs/02 §10 называет его как запасной вариант)
