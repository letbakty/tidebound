# 16 — Работы: утилитарный скоринг, резервирование, маяк, существа

**Для этапов:** 06 (весь), 08 (STATION-задачи поверх той же машины), 09 (существа как «анти-агенты» на графе), 10 (cycle_modifiers).
**Дата ресерча:** 2026-08-21. **Движок:** Godot 4.7.x stable.

Это поведенческое ядро игры. Промпт 06 даёт формулу, но не даёт архитектуру. Здесь — архитектура, проверенная на аналогах из других движков и игр, и её перенос в наши ограничения (детерминизм, без нод, 10 Гц).

---

## 1. Какая модель ИИ у нас на самом деле

Три классические школы:

| Модель | Кто использует | Суть | Наш случай |
|---|---|---|---|
| **Behavior Tree** | Unreal, Unity (NodeCanvas), Godot-аддоны LimboAI/Beehave | дерево узлов, обход сверху вниз | ❌ не сериализуется, нужен per-agent объект |
| **ThinkTree / приоритетный список** | RimWorld | иерархия `JobGiver`-ов, первый валидный выигрывает | ⚠️ частично |
| **Utility AI («реклама»)** | The Sims, Game AI Pro гл. 9 | объекты **рекламируют** полезность, агент взвешивает по своим нуждам | ✅ **это мы** |

Формула из docs/00 §6.5 — `score = policy_weight × base × urgency ÷ (1 + 0.1 × dist)` — это буквально утилитарный скоринг: `base` = «реклама» задачи, `urgency` = множитель от текущей нужды, `dist` = штраф расстояния. В The Sims ровно та же структура: *«the Sim takes the advertised number and weighs it based on its current needs by applying a multiplier»*.

**Что из этого следует практически:**

1. **Задачи порождает мир, а не агент.** Депозит с ресурсом «рекламирует» GATHER; предмет на земле — HAUL; голодный желудок — EAT. `JobSystem` собирает пул объявлений; агент только выбирает. Это принципиально дешевле, чем каждый агент сканирует мир (O(агенты × мир) → O(мир) + O(агенты × задачи)).
2. **`policy_weight = 0` — не «низкий приоритет», а фильтр.** Как в The Sims «certain objects can be locked entirely». Отбрасывать до расчёта скоринга, а не после — экономит и время, и делает приёмку «Заготовка=0 — никто не добывает» строго проверяемой.
3. **RimWorld добавляет то, чего нет в The Sims и что нам нужно: резервирование.** Без него все шесть агентов пойдут к одной куче утиля.

---

## 2. Пул задач: перестройка по событиям, выбор — каждый тик

```gdscript
class_name JobSystem
extends RefCounted

# id -> {class, target_kind, target_id, cell, platform_id, base, item_id, n, taken_by}
var _jobs: Dictionary[int, Dictionary] = {}
var _order: Array[int] = []          # детерминированный порядок обхода
var _next_id: int = 1
var _dirty: bool = true              # пул нужно пересобрать

func mark_dirty() -> void:
	_dirty = true

func tick(w: SimWorld) -> void:
	if _dirty:
		_rebuild(w)                  # НЕ каждый тик: только после изменения мира
		_dirty = false
	_assign(w)                       # каждый тик: свободные агенты берут задачи
```

**Что ставит `_dirty`:** депозит изменился, предмет упал/подобран, постройка размещена/сломалась/починена, склад заполнился, политика изменилась, маяк передвинут, начался цикл. Всё это уже эмитится как `SimEvent` — **но подписываться на `Events` из `sim/` нельзя.** Значит `mark_dirty()` вызывают сами системы напрямую, внутри тика. Это ещё один аргумент за фиксированный порядок систем (docs/02 §4).

⚠️ **Перестройка не должна терять назначения.** Агент несёт утиль на склад; пул пересобрался — задача исчезла, агент завис. **Решение: задачи, у которых `taken_by != -1`, переносятся в новый пул как есть**, а пересобираются только свободные:
```gdscript
func _rebuild(w: SimWorld) -> void:
	var kept: Dictionary[int, Dictionary] = {}
	for id: int in _order:
		var j: Dictionary = _jobs[id]
		if j["taken_by"] != -1 and _still_valid(j, w):
			kept[id] = j
	_jobs = kept
	_regenerate_free_jobs(w)          # GATHER/HAUL/BUILD/REPAIR/STATION
	_order = _jobs.keys()
	_order.sort()                     # детерминизм обхода (research/11 §1)
```

---

## 3. Резервирование: как в RimWorld, но на 20 строк

RimWorld держит `ReservationManager`: пешка «резервирует» цель, другие её не берут; резервация снимается при завершении, отмене или смерти. У нас достаточно поля `taken_by: int` в задаче + обратной ссылки `job_id` в агенте.

**Инварианты, которые надо держать (и проверить тестом):**
1. `job.taken_by == a.id` ⟺ `a.job_id == job.id` — двусторонняя связь всегда согласована.
2. Смерть агента → задача освобождается **в тот же тик**.
3. Задача стала невалидной (депозит опустел, склад затоплен, лестница сломана) → агент освобождается и переходит в IDLE, а не идёт в пустоту.
4. Один агент = максимум одна задача.

```gdscript
func _release(a: SimAgent) -> void:
	if a.job_id == -1: return
	var j: Dictionary = _jobs.get(a.job_id, {})
	if not j.is_empty(): j["taken_by"] = -1
	a.job_id = -1

func _claim(a: SimAgent, job_id: int) -> void:
	_release(a)
	_jobs[job_id]["taken_by"] = a.id
	a.job_id = job_id
```

**Тест-инвариант (стоит прогонять каждые 100 тиков в soak-тесте этапа 19):**
```gdscript
for id: int in _order:
	var owner: int = _jobs[id]["taken_by"]
	if owner != -1:
		t.check(w.agents.get(owner).job_id == id, "рассинхрон резервации задачи %d" % id)
```

⚠️ **Резервация обязана сериализоваться.** И `taken_by`, и `a.job_id`, и сам пул задач. Иначе после загрузки (этап 11) все агенты окажутся с `job_id`, указывающим в пустоту. Альтернатива — **не сериализовать пул вообще, а на загрузке сбросить всех в IDLE и пересобрать**. ⚠️ Это проще и надёжнее, но агенты «забудут» полпути. **Рекомендация: сериализовать пул** — приёмка этапа 11 требует «симуляция продолжается детерминированно», а сброс задач это нарушит.

---

## 4. Скоринг: формула, порядок, детерминизм

```gdscript
func _score(a: SimAgent, j: Dictionary, w: SimWorld) -> int:
	var pol: int = w.policies.value_for_class(j["class"])       # 0..3
	if pol == 0:
		return -1                                              # класс запрещён
	var weight: float = Balance.POLICY_WEIGHT[pol]             # напр. [0, 0.5, 1.0, 2.0]
	var base: float = float(j["base"])
	var urg: float = _urgency(a, j, w)
	var dist: float = _dist_tiles(a, j, w)
	var s: float = weight * base * urg / (1.0 + 0.1 * dist)
	if _in_beacon_radius(j, w):
		s *= Balance.BEACON_BONUS                              # 1.3
	s *= a.modifier(_mult_key_for(j["class"]))                 # черты
	# Квантование: снимает float-дрожь и делает сортировку тотальной (research/11 §1.1)
	return int(round(s * 100.0))
```

**Порядок множителей фиксирован и задокументирован в коде.** `weight × base × urgency / dist`, затем маяк, затем черты. Любая перестановка — другой float — другой выбор при близких скорах — расхождение детерминизма.

**Выбор задачи:**
```gdscript
func _best_job_for(a: SimAgent, w: SimWorld) -> int:
	var best_id: int = -1
	var best_s: int = 0
	for id: int in _order:                    # _order отсортирован => детерминизм
		var j: Dictionary = _jobs[id]
		if j["taken_by"] != -1: continue
		if not _reachable(a, j, w): continue
		if not _greed_allows(a, j, w): continue
		var s: int = _score(a, j, w)
		if s > best_s:                        # СТРОГО больше => при ничьей выигрывает
			best_s = s                        # меньший id. Тай-брейк бесплатный.
			best_id = id
	return best_id
```
**Линейный проход вместо сортировки** — и быстрее (нет аллокации), и детерминированнее (никакого `sort_custom`, см. research/11 §1.1). При ~50 задачах × 6 агентов = 300 сравнений за тик — ничто.

⚠️ **Порядок агентов тоже важен.** Кто выбирает первым, тот забирает лучшую задачу. Обход агентов — **строго по возрастанию `id`**, всегда. Не по словарю, не по «кто раньше освободился».

### 4.1 Стоит ли «выбирать случайно из топ-N», как The Sims?
В The Sims агент берёт **случайную из лучших**, чтобы не выглядеть роботом. У нас это:
- ✅ выглядит живее, снимает «все шестеро в колонну по одному»;
- ❌ добавляет вызов RNG в горячий путь → усложняет отладку детерминизма (хотя `SimRNG` детерминирован, лишний расход RNG-состояния делает любой рефактор скоринга источником расхождений).

**Рекомендация: не делать на этапе 06.** Резервирование уже разводит агентов по разным задачам. Если после плейтестов поведение покажется механическим — добавить тогда, отдельным решением, и **обязательно из выделенного потока RNG** (`w.rng_ai`, отдельный от `w.rng_world`), чтобы изменения в ИИ не сдвигали генерацию мира.

**Раздельные потоки RNG — вообще хорошая практика, дешёвая на этапе 01 и дорогая позже.** Минимум два: `rng_world` (карта, плавник, драфт, реликвии) и `rng_ai` (тай-брейки поведения). Тогда правка ИИ не меняет карту при том же сиде — это экономит часы при балансировке.

---

## 5. Расстояние: не Евклид и не пересчёт каждый раз

`dist` в формуле — **длина пути по графу в тайлах**, а не воздушная линия: агент на +6 и депозит на −8 могут быть рядом по X, но в 40 тайлах по лестницам.

```gdscript
func _dist_tiles(a: SimAgent, j: Dictionary, w: SimWorld) -> float:
	var key: int = a.platform_id * 1000 + int(j["platform_id"])
	var cached: float = _dist_cache.get(key, -1.0)
	if cached >= 0.0:
		return cached
	var path: Array[int] = w.terrain.find_path(a.platform_id, j["platform_id"])
	var d: float = w.terrain.path_length_tiles(path)
	_dist_cache[key] = d
	return d
```
**Кэш инвалидируется по `graph_version`**, а не по времени. Площадок ~30 → максимум 900 пар, реально десятки. Это единственный кэш, который стоит завести на этапе 06.

⚠️ **`AStar2D` уже даёт длину пути**, если позиции точек заданы в мировых координатах (doc 12 §4): сумма расстояний между точками пути. Не считать заново по клеткам.

---

## 6. Жадность и Осторожность — два фильтра, а не два скоринга

**Жадность (GREED)** — фильтр по расстоянию цели от ближайшей лестницы:
```gdscript
func _greed_allows(a: SimAgent, j: Dictionary, w: SimWorld) -> bool:
	var limit: int = Balance.GREED_LADDER_LIMIT[w.policies.get(SimTypes.Policy.GREED)]
	if limit < 0:
		return true                              # Жадность 3 — без лимита
	return w.terrain.nearest_ladder_dist(j["cell"]) <= float(limit)
```
Фильтр, а не штраф — потому что приёмка требует бинарного «никто не берёт дальше 4 тайлов».

**Осторожность (CAUTION)** — не фильтр задач, а **таймер авто-отзыва**:
```gdscript
func _check_auto_recall(w: SimWorld) -> void:
	if w.clock.phase != SimTypes.Phase.SIGNAL:
		return
	var lead: int = Balance.CAUTION_LEAD_SEC[w.policies.get(SimTypes.Policy.CAUTION)]  # [0,20,40,60]
	if lead == 0:
		return
	var left_ticks: int = w.clock.ticks_left_in_phase()
	for a: SimAgent in w.agents_sorted():
		var personal: int = lead
		if a.mood < 30.0:
			personal += 20                        # паника: возвращается раньше
		if left_ticks <= personal * Balance.TICKS_PER_SEC and _mark_of(a) < 0:
			_set_return(a, w)
```
⚠️ **Только для агентов ниже отметки 0** (промпт 06 п.4). Иначе Осторожность 3 загонит домой всю колонию, включая тех, кто и так наверху, и приёмка «Осторожность 3: к началу HIGH никто не ниже −1» пройдёт, а игра сломается.

⚠️ **`ticks_left_in_phase()` должен учитывать `phase_scale`** (шторм укорачивает LOW на 30%, промпт 09). Если этот метод написать на этапе 01 сразу с учётом масштаба (research/11 §11 п.5), этап 09 не потребует правок здесь.

---

## 7. Маяк

```gdscript
func _in_beacon_radius(j: Dictionary, w: SimWorld) -> bool:
	if w.beacon_cell == Vector2i(-1, -1):
		return false
	# Радиус 12 тайлов — по прямой, а не по графу: это игроцкая метка «сюда»,
	# и она должна быть предсказуемой на глаз.
	return Vector2(j["cell"] - w.beacon_cell).length() <= float(Balance.BEACON_RADIUS)
```
**Именно евклидово расстояние, в отличие от `dist` в скоринге.** Причина не техническая, а UX: игрок видит на экране круг радиусом 12 и ожидает, что бонус — внутри круга. Расстояние по графу дало бы «дырявый» круг. Записать комментарием, иначе следующий агент «унифицирует».

⚠️ `Vector2i` не имеет `.length()` — нужен явный каст в `Vector2`. Частая ошибка компиляции.

---

## 8. Существа (этап 09) — та же машина, но на инвертированном графе

Существа — это агенты с другими правилами прохода. Не писать вторую систему движения: **переиспользовать `find_path`, подменив граф**.

```gdscript
# Terrain держит ДВА графа (doc 12 §4):
#   _astar_dry  — узлы выше уровня воды (агенты)
#   _astar_wet  — узлы НИЖЕ уровня воды (существа)
# Пересборка «мокрого» — только при пересечении уровнем воды отметки, не каждый тик.

func creature_path(from_id: int, to_id: int, w: SimWorld) -> Array[int]:
	return _wet_path(from_id, to_id)
```

**Блокировки — через `set_point_disabled`, а не через фильтрацию пути:**
```gdscript
func _apply_creature_blocks(w: SimWorld) -> void:
	for pid: int in _platform_ids:
		var blocked: bool = false
		# Узел в радиусе работающего фонаря — запрещён (радиус 3, 🔒5)
		for b: Dictionary in w.buildings.active_with_special("lantern"):
			if _dist_tiles_direct(pid, b["cell"]) <= float(b["radius"]):
				blocked = true
				break
		_astar_wet.set_point_disabled(pid, blocked)
	# Шлюз блокирует РЕБРО, а не узел:
	for e: Dictionary in _edges:
		if w.buildings.active_sluice_on_edge(e["id"]):
			_astar_wet.disconnect_points(e["a"], e["b"])
```
⚠️ **Шлюз — это ребро, фонарь — это узел.** Смешать их значит либо запереть существ намертво, либо пропустить сквозь шлюз. Разные API: `disconnect_points` vs `set_point_disabled`.

⚠️ **`get_id_path` при полностью отрезанной цели вернёт пустой массив** (не `null`). Ветка «целей нет → бродит у спавна» — это `path.is_empty()`, и она обязана быть, иначе существо застынет с `path_idx = 0` и приёмка «при полном перекрытии — бродит у спавна» провалится.

**Выбор цели существа** — тот же скоринг, но одноклассовый: ближайшая постройка/склад с `mark < water_level`. Достаточно линейного прохода с тай-брейком по id.

---

## 9. Классы задач и порядок их появления по этапам

| Класс | Этап, где реализуется | Порождается | Заглушка до этого |
|---|---|---|---|
| GATHER | 06 | непустой достижимый депозит | — |
| HAUL | 06 | предмет на земле; вход станции; топливо | `request_haul(from,to,item,n)` |
| EAT / REST | 06 (перенос из 05) | потребность ниже порога | в 05 — прямой переход FSM |
| BUILD | 07 | постройка в PLANNED | интерфейс-заглушка в 06 |
| REPAIR | 07 | постройка damaged | то же |
| STATION | 08 | станция ACTIVE + входы в буфере | то же |

**`request_haul(from, to, item, n) -> int` — ключевой интерфейс.** Промпт 06 требует его как заглушку, промпты 07 и 08 на него опираются. Спроектировать сразу:
- возвращает `job_id` (чтобы вызывающая система могла отследить/отменить);
- `from` — `{"kind": "storage"|"ground"|"station", "id": int, "cell": Vector2i}`;
- задача **не создаётся дважды** для той же пары (иначе стройка нагенерит по задаче на тик);
- отмена: `cancel_haul(job_id)` при сносе постройки.

⚠️ **Дедупликация — самая частая ошибка этапа 07.** `BuildingSystem` каждый тик видит «на месте стройки не хватает 4 утиля» и просит HAUL. За 10 тиков — 10 задач. Лечение: постройка хранит `pending_haul_jobs: Array[int]` и просит только недостающее.

---

## 10. Чек-лист приёмки этапов 06 и 09

**06:**
- [ ] За цикл при дефолтных политиках 6 агентов приносят ≥8 утиля и ≥4 catch.
- [ ] Жадность 0: ни одной взятой задачи дальше 4 тайлов от лестниц; Жадность 3: есть дальние.
- [ ] Осторожность 3: к началу HIGH никто не ниже −1. Осторожность 0 + Жадность 3: у кого-то `submerged_ticks > 0`.
- [ ] Заготовка=0 → ноль GATHER-задач взято. Отдых=3 → на HIGH все в EAT/REST.
- [ ] Маяк: при двух равных депозитах выбран тот, что в радиусе.
- [ ] **Инвариант резервации** держится на всех 20 000 тиках (проверка каждые 100).
- [ ] Ни одного `sort_custom` в горячем пути; детерминизм-прогон зелёный.

**09:**
- [ ] Существо не проходит ACTIVE-шлюз (проверить `disconnect_points`, а не постфактум).
- [ ] Существо не входит в радиус фонаря.
- [ ] При полном перекрытии `path.is_empty()` → бродит у спавна, не зависает.
- [ ] Кража: стак исчез со склада, существо ушло к спавну, отчёт цикла содержит запись.
- [ ] Агент в 4 тайлах: mood −10 **ровно один раз за цикл** на агента.

---

## Источники и аналоги

- [An Introduction to Utility Theory — Game AI Pro, гл. 9 (PDF)](https://www.gameaipro.com/GameAIPro/GameAIPro_Chapter09_An_Introduction_to_Utility_Theory.pdf) — каноническое описание утилитарного скоринга: кривые отклика, нормализация, выбор из топа
- [The Genius AI Behind The Sims — GMTK](https://gmtk.substack.com/p/the-genius-ai-behind-the-sims) — модель «рекламы» и выбор случайной из лучших
- [RimWorld AI Tutorial — ThinkTree/JobGiver](https://github.com/CBornholdt/RimWorld-AI-Tutorial/wiki/Part-1---Introduction) и [How Pawns Think](https://github.com/roxxploxx/RimWorldModGuide/wiki/SHORTTUTORIAL:-How-Pawns-Think) — иерархия приоритетов, `Job`/`JobDriver`/`Toil`, резервирование
- [JobGiver_Work.cs (декомпиляция RimWorld)](https://github.com/josh-m/RW-Decompile/blob/master/RimWorld/JobGiver_Work.cs) — как выглядит реальный перебор WorkGiver-ов с ранним выходом
- [Oxygen Not Included — Errand / Priority](https://oxygennotincluded.fandom.com/wiki/Errand) — двухуровневый приоритет (класс работы + суб-приоритет объекта); наш аналог — политика × base
- [AStar2D](https://docs.godotengine.org/en/stable/classes/class_astar2d.html) — `set_point_disabled`, `disconnect_points`, детерминизм
- [Deterministic Lockstep — Gaffer On Games](https://gafferongames.com/post/deterministic_lockstep/) — стабильный порядок обхода как условие воспроизводимости
