# 18 — Сейвы: JSON, точность, атомарная запись, восстановление UI

**Для этапов:** 11 (весь), 15 (Continue), 19 (битый сейв, краевые случаи), 16 (сохранение при сворачивании на мобилке).
**Дата ресерча:** 2026-08-21. **Движок:** Godot 4.7.x stable.

Промпт 11 — про аккуратность. Ниже — четыре вещи, каждая из которых по отдельности заваливает приёмку «round-trip идентичен», и все четыре неочевидны.

---

## 1. Ловушка №1: `JSON.parse` возвращает все числа как float

Это причина №1 провала теста «`to_dict → from_dict → to_dict` — идентичные словари».

```gdscript
var d := {"cycle": 12}
var s := JSON.stringify(d)                 # '{"cycle":12}'
var back: Dictionary = JSON.parse_string(s)
print(typeof(back["cycle"]) == TYPE_FLOAT) # true! Было int, стало 12.0
print(JSON.stringify(back))                # '{"cycle":12.0}'  -> строки не совпали
```

**Правило: каждый `from_dict` явно приводит тип.**
```gdscript
cycle = int(d.get("cycle", 1))
level = float(d.get("level", 0.0))
name  = String(d.get("name", ""))
flag  = bool(d.get("flag", false))
```
Никогда `cycle = d["cycle"]`. Никогда. Это правило стоит вписать в CONVENTIONS отдельной строкой на этапе 11.

**Массивы и словари — тоже:**
```gdscript
# Array[int] из JSON приходит как Array (нетипизированный) c float внутри
var ids: Array[int] = []
for v: Variant in d.get("ids", []):
	ids.append(int(v))
```
⚠️ `ids.assign(d["ids"])` на типизированном массиве **упадёт в рантайме**, если внутри float — `assign` проверяет типы. Это даже хорошо (громкая ошибка вместо тихой), но писать надо цикл.

**Ключи словарей всегда String.** `Dictionary[int, X]` (агенты по id) после round-trip станет `Dictionary` со строковыми ключами `"1"`, `"2"`. Два варианта:
- сериализовать как **массив объектов** с полем `id` внутри (рекомендуется — заодно фиксирует порядок обхода);
- или конвертировать ключи обратно: `out[int(k)] = ...`.

**Рекомендация: все коллекции сущностей — массивы, отсортированные по id.** Это решает и типы ключей, и детерминизм порядка (research/11 §1), и читаемость диффа сейва.

---

## 2. Ловушка №2: `full_precision = false` по умолчанию

Сигнатура (проверено по class reference 4.7):
```gdscript
static String stringify(data: Variant, indent: String = "", sort_keys: bool = true, full_precision: bool = false)
```

`full_precision = false` печатает float с усечением. Для *сравнения хешей* это плюс (гасит шум), для *сейва* — потеря данных: `satiety = 47.238194` вернётся как `47.238`, и продолженная симуляция разойдётся с непрерывной. Приёмка этапа 11 требует именно совпадения хешей после save→load — **тест упадёт.**

**Правило: два разных вызова для двух разных задач.**
```gdscript
## Для файла сейва — полная точность.
static func to_json(d: Dictionary) -> String:
	return JSON.stringify(d, "", true, true)      # sort_keys=true, full_precision=true

## Для хеша состояния в тестах — усечённая (гасит незначимый шум).
static func state_hash(d: Dictionary) -> String:
	return JSON.stringify(d).sha256_text()
```

⚠️ Полная точность делает файл больше и «уродливее» (`0.10000000000000001`). Это нормально: сейв не для чтения человеком. `indent = ""` — компактный однострочник, тоже правильно для файла.

⚠️ **Альтернатива, снимающая проблему в принципе:** целочисленные потребности (research/11 §1.3). Тогда во всём сейве float остаётся только у `tide.level` и `agent.x` — и `full_precision` уже неважен. **Если этап 05 сделан целочисленно, здесь можно расслабиться.**

---

## 3. Ловушка №3: `NAN`/`INF` не сериализуются

Док JSON: *«non-finite numbers are not supported in JSON»*. `NAN` уходит как `null`, обратно приходит как `null`, `float(null)` = `0.0`.

Прямо касается `tide.level_override: float = NAN` (промпт 03). Решение — в doc 13 §7: **не сериализовать дебажный override вообще**. Для любого другого NAN — пара хелперов из research/11 §8.

⚠️ Также: деление на ноль в GDScript даёт `INF` без ошибки, а `0.0/0.0` — `NAN`. Формула скоринга `/ (1 + 0.1*dist)` безопасна, но любая новая формула с делением обязана иметь защиту. **`is_finite(x)` в `to_dict` на этапе 19 — дешёвая страховка:**
```gdscript
# tests/test_save.gd
static func assert_all_finite(d: Variant, path: String, t: TestCtx) -> void:
	match typeof(d):
		TYPE_FLOAT: t.check(is_finite(d), "не-финитное число в %s" % path)
		TYPE_DICTIONARY:
			for k: Variant in d: assert_all_finite(d[k], path + "/" + str(k), t)
		TYPE_ARRAY:
			for i: int in d.size(): assert_all_finite(d[i], path + "[%d]" % i, t)
```

---

## 4. Ловушка №4: неатомарная запись

Игрок закрывает игру / у телефона садится батарея в момент `store_string` → файл обрезан → следующий запуск падает или теряет забег.

**Атомарная запись через временный файл + переименование:**
```gdscript
const RUN_PATH: String = "user://save_run.json"
const TMP_SUFFIX: String = ".tmp"

static func write_json_atomic(path: String, text: String) -> Error:
	var tmp: String = path + TMP_SUFFIX
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("сейв: не открыт %s (%d)" % [tmp, FileAccess.get_open_error()])
		return FileAccess.get_open_error()
	f.store_string(text)
	f.flush()
	f.close()                                   # ОБЯЗАТЕЛЬНО до rename
	var err: Error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(tmp),
		ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("сейв: rename не удался (%d)" % err)
	return err
```

**Технические детали:**
- `FileAccess` закрывается сам при выходе объекта из области видимости (RefCounted), но **порядок сборки мусора не гарантирован относительно `rename`** — `close()` явно.
- `DirAccess.rename_absolute` требует **абсолютных путей ОС**, поэтому `globalize_path`. Есть также `DirAccess.rename(from, to)` у открытого экземпляра — работает с `user://`-путями, но требует `DirAccess.open("user://")`.
- Переименование поверх существующего файла на Windows может не сработать атомарно. ⚠️ **НЕ ПОДТВЕРЖДЕНО** для 4.7; если на Windows будут проблемы — фолбэк: писать `.tmp`, удалять старый, переименовывать. Менее безопасно, но работает.
- **`FileAccess.get_open_error()`** — статический, вызывается **после** неудачного `open()`. `FileAccess.open` возвращает `null`, а не ошибку.

---

## 5. Безопасность: чего нельзя делать никогда

docs/02 §6 и §10 запрещают, и это не паранойя, а известный класс уязвимостей Godot:

| Нельзя | Почему |
|---|---|
| `ResourceLoader.load("user://save.tres")` | `.tres` может содержать встроенный GDScript → выполнение произвольного кода из чужого сейва |
| `ConfigFile.load` на пользовательском файле | то же: значения могут быть Object |
| `FileAccess.get_var(allow_objects = true)` | явное разрешение инстанцировать объекты из файла |
| `store_var` с объектами | симметрично |
| `str_to_var` на пользовательской строке | парсит `Object(...)` |

**Разрешено ровно одно:** `JSON.parse` → словарь примитивов → ручное восстановление.

Это же значит, что **`Vector2i` в сейве — `[x, y]`**, а не `"Vector2i(3, 4)"`: строковая форма потребовала бы `str_to_var` для чтения.

---

## 6. Чтение: валидация версии и мягкий отказ

```gdscript
func load_run() -> bool:
	if not FileAccess.file_exists(RUN_PATH):
		return false
	var f := FileAccess.open(RUN_PATH, FileAccess.READ)
	if f == null:
		push_warning("сейв не читается: %d" % FileAccess.get_open_error())
		return false
	var text: String = f.get_as_text()
	f.close()

	var parser := JSON.new()
	var err: Error = parser.parse(text)
	if err != OK:
		# Мягкий отказ (приёмка этапа 19 п.5): не крашимся, сообщаем, переименовываем
		push_warning("битый сейв, строка %d: %s" % [parser.get_error_line(), parser.get_error_message()])
		_quarantine(RUN_PATH)
		return false
	var d: Variant = parser.data
	if typeof(d) != TYPE_DICTIONARY:
		_quarantine(RUN_PATH); return false
	var save_version: int = int((d as Dictionary).get("save_version", 0))
	if save_version != SAVE_VERSION:
		push_warning("несовместимая версия сейва: %d != %d" % [save_version, SAVE_VERSION])
		return false                             # каркас миграций — здесь
	...
```

**`_quarantine` вместо удаления:** переименовать битый файл в `save_run.corrupt.json`. Это спасает игрока (можно попросить прислать файл) и делает баг воспроизводимым.

⚠️ **`JSON.parse` (инстанс-метод) vs `JSON.parse_string` (статический).** `parse_string` возвращает `null` при ошибке и **не даёт номера строки**. Для пользовательских файлов использовать инстанс-версию — она даёт `get_error_line()`/`get_error_message()`. Для внутренних данных `parse_string` короче.

---

## 7. `rebroadcast_state`: почему без него UI пуст после загрузки

Промпт 11 требует «повторная эмиссия стартовых событий для UI». Технически: View-ноды создаются **только** по событиям `agent_spawned`/`building_placed`. После `from_dict` состояние есть, а событий не было — мир будет пустым.

```gdscript
## Game
func rebroadcast_state() -> void:
	Events.run_started.emit(world.seed_value)
	Events.phase_changed.emit(int(world.clock.phase), world.clock.cycle)
	Events.water_level_changed.emit(world.tide.level)
	for id: int in world.agents.ids_sorted():
		Events.agent_spawned.emit(id)
		Events.agent_updated.emit(id)
	for id: int in world.buildings.ids_sorted():
		Events.building_placed.emit(id)
		Events.building_state_changed.emit(id)
	for id: int in world.storages.ids_sorted():
		Events.storage_changed.emit(id)
	for id: int in world.creatures.ids_sorted():
		Events.creature_spawned.emit(id)
	Events.resources_changed.emit(world.storage.totals())
	for p: int in SimTypes.Policy.values():
		Events.policy_changed.emit(p, world.policies.get(p))
	if world.beacon_cell != Vector2i(-1, -1):
		Events.beacon_moved.emit(world.beacon_cell)
```

**Правило: любая View-нода, создающаяся по событию, обязана быть покрыта `rebroadcast_state`.** Каждый новый тип сущности (существа на 09, маяк на 06) добавляет строку сюда. **Проверить это можно автоматически:** тест сравнивает список сигналов, которые слушают View-ноды, со списком эмитируемых в `rebroadcast_state`.

⚠️ **Порядок: сначала «мир», потом «сущности», потом агрегаты.** `resources_changed` в конце — иначе HUD посчитает тренд от пустоты.

⚠️ **Перед `rebroadcast` — полная очистка View.** Иначе после `Continue` из меню в мире окажутся дубли. `World.clear_all_views()` — обязательный метод.

---

## 8. Когда сохранять

Промпт: «конец каждого цикла (после `cycle_ended`), выход из игры».

```gdscript
## autoload/save_service.gd
func _ready() -> void:
	get_tree().set_auto_accept_quit(false)          # перехватываем закрытие окна
	Events.cycle_ended.connect(_on_cycle_ended.unbind(1))
	Events.run_ended.connect(_on_run_ended.unbind(1))

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			save_run()
			save_profile()
			get_tree().quit()
		NOTIFICATION_WM_GO_BACK_REQUEST:            # Android «назад»
			save_run()
			get_tree().quit()
		NOTIFICATION_APPLICATION_PAUSED:            # сворачивание на мобилке
			save_run()                              # ⚠️ на iOS ~5 секунд на всё
```

**Факты (док «Handling quit requests»):**
- `set_auto_accept_quit(false)` нужен, иначе окно закроется **до** нашего обработчика.
- `NOTIFICATION_APPLICATION_PAUSED` — сворачивание приложения. Док прямо: *«On iOS, you only have approximately 5 seconds to finish a task started by this signal»*. Значит сохранение должно быть **быстрым и синхронным**, без Tween'ов и `await`.
- На Android процесс может быть убит без `CLOSE_REQUEST` — `APPLICATION_PAUSED` это единственный шанс. **Для мобильных билдов (этап 16) это критично.**

⚠️ **Автолоад с `_notification` должен иметь `process_mode = PROCESS_MODE_ALWAYS`**, если где-то в игре появится `get_tree().paused = true`. У нас паузы дерева нет, но поставить — бесплатная страховка.

⚠️ **Debounce профиля.** Промпт требует «автосейв при изменении Meta». Если писать файл на каждое изменение очков, за экран итогов будет 20 записей. Отложить на кадр:
```gdscript
var _profile_dirty: bool = false
func mark_profile_dirty() -> void: _profile_dirty = true
func _process(_d: float) -> void:
	if _profile_dirty:
		_profile_dirty = false
		save_profile()
```

---

## 9. Подсчёт очков: две технические ловушки

Промпт 11: «Σ ship_points стаков со складов с mark ≥ +1 (**затопленные в момент прибытия склады не считаются**)».

1. **«В момент прибытия» — это конкретный тик**, начало HIGH 12-го цикла. Считать надо **тогда**, а не в конце HIGH, когда вода уже поднялась и утопила всё. Значит `run_state` обязан сделать снапшот очков на `ship_arrived` и хранить его до `run_ended`. Иначе приёмка «затопленный склад в момент судна не даёт очков» пройдёт случайно или не пройдёт вовсе.
2. **Разбивка обязана сходиться с суммой.** Считать сумму отдельно от разбивки — гарантированное расхождение на округлениях. **Правильно: считать только разбивку, сумму получать как `values().reduce(...)`:**
```gdscript
var breakdown: Dictionary[String, int] = {
	"cargo": _cargo_points(w), "survivors": alive * 5, "relics": relics * 10,
}
var total: int = 0
for k: String in breakdown: total += breakdown[k]
if early_leave:
	# множитель применяется к ИТОГУ, и это меняет разбивку -> сохранить обе величины
	breakdown["early_penalty"] = total - int(float(total) * 0.75)
	total = int(float(total) * 0.75)
```
⚠️ Множитель 0.75 к целому — округление. `int()` отбрасывает дробь (к нулю). Для очков это ок, но **зафиксировать явно**, а не полагаться на неявное приведение.

---

## 10. Чек-лист приёмки этапа 11

- [ ] `to_dict → JSON → parse → from_dict → to_dict` даёт **идентичную строку** при `full_precision=true`.
- [ ] save на цикле 5 → load → продолжение 2 цикла даёт тот же хеш, что непрерывный прогон.
- [ ] Все типы после `from_dict` правильные: тест проверяет `typeof` ключевых полей (`cycle` — int, не float).
- [ ] Нет `NAN`/`INF` нигде в сейве (рекурсивная проверка §3).
- [ ] Битый сейв (обрезать файл на середине) → мягкий отказ + карантин, без краша.
- [ ] Сейв другой `save_version` → отказ с сообщением.
- [ ] `rebroadcast_state` восстанавливает **все** типы View (агенты, постройки, склады, существа, маяк, политики, ресурсы).
- [ ] `Continue` из меню даёт визуально то же состояние (скриншот до/после).
- [ ] Профиль переживает перезапуск процесса (реальная запись→чтение файла, не in-memory).
- [ ] `buy_unlock` списывает очки; повторная покупка возвращает `false`.
- [ ] Сейв удаляется при `run_ended`.
- [ ] Полный автопилотный забег 12 циклов headless → `run_ended(SHIP)`, разбивка == сумме.

---

## Источники

- [JSON (Godot 4.7)](https://docs.godotengine.org/en/stable/classes/class_json.html) — `stringify(data, indent, sort_keys=true, full_precision=false)`, non-finite numbers, `parse`/`get_error_line`
- [FileAccess](https://docs.godotengine.org/en/stable/classes/class_fileaccess.html) — `open`, `get_open_error`, `flush`
- [DirAccess](https://docs.godotengine.org/en/stable/classes/class_diraccess.html) — `rename_absolute`
- [Handling quit requests](https://docs.godotengine.org/en/stable/tutorials/inputs/handling_quit_requests.html) — `set_auto_accept_quit`, `NOTIFICATION_WM_CLOSE_REQUEST`, `NOTIFICATION_APPLICATION_PAUSED` («~5 секунд на iOS»)
- [Saving games (Godot docs)](https://docs.godotengine.org/en/stable/tutorials/io/saving_games.html) — официальный паттерн JSON-сейва
- docs/02 §6, §10 — запрет ResourceLoader/ConfigFile/get_var для пользовательских файлов
