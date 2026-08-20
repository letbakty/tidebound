# Этап 04 — Предметы, склады, порча, намокание

**Модель:** Fable 5 или Sonnet 5 (данные + одна система, спека полная).
**Зависит от:** 01, 02. **Читать:** docs/00 §7; docs/02 §5.
**Результат:** все 13 предметов как данные; система складов и предметов на земле; порча и flood-правила работают.
**Ресерч:** [research/14-data-resources-tres.md](../research/14-data-resources-tres.md) — **генерация ~70 `.tres` скриптом** вместо кликов, `DB`, стаки как словари. Дополнительно: [research/12](../research/12-terrain-tilemap-camera.md) §5 (затопление).

## Задача
1. `data/defs/item_def.gd` — `class_name ItemDef extends Resource`: `@export id: String, display_key: String, stack_size: int, spoil_cycles: int` (0 = не портится), `@export flood_rule: SimTypes.FloodRule`, `@export ship_points: int`, `@export icon: Texture2D` (пока пусто).
2. `data/items/*.tres` — **генерировать скриптом `tools/gen_items.gd` (EditorScript, File → Run), а не набивать в инспекторе.** Готовый шаблон генератора — [research/14](../research/14-data-resources-tres.md) §3; это самый крупный выигрыш по времени во всём проекте (~70 `.tres` за все этапы), плюс обход issue 104581 (ключ типизированного словаря нельзя править в инспекторе). Источник правды — таблица docs/00 §7, генератор идемпотентен. Все 13 предметов (id дословно: scrap, catch, driftwood, kelp, freshwater, salt, ingot, fiber, rations, part, rope, gear, relic). Плавник/волокно: flood_rule=WET; соль: DESTROY; catch/rations: LOSE_HALF; остальные OK.
3. `data/db.gd` — `class_name DB`: статические словари дефов, загрузка всех .tres из data/items (и задел под buildings/recipes/traits/cards/unlocks). Готовый загрузчик с валидатором ссылок и обходом **ловушки `.remap`** (в экспортированной сборке файлы называются иначе) — [research/14](../research/14-data-resources-tres.md) §4. Доступ `DB.item(id) -> ItemDef`.
4. `sim/storage_system.gd` — `class_name StorageSystem`:
   - Стак: `{item_id: String, count: int, wet: bool, spoil_left: int}` (Dictionary — сериализуемо).
   - Склады: `add_storage(cell, capacity_slots=12) -> id`; `store(storage_id, stack) -> остаток`, `take(storage_id, item_id, n, prefer_dry=true) -> Array[stack]`, `totals() -> Dictionary[String,int]` (агрегат по всем складам, эмитит `resources_changed` при изменении).
   - Предметы на земле: `drop(cell, stack)`, `pickup_at(cell)`; земля не защищает: при затоплении клетки — предмет уносится водой (событие в итог цикла).
   - Порча: на `cycle_ended` у стаков с spoil_left>0 декремент; 0 → стак исчезает (событие).
   - Затопление склада: на каждое пересечение уровнем воды отметки склада — применить flood_rule к каждому стаку (§7): WET → wet=true; LOSE_HALF → count/2 (окр. вниз); DESTROY → удалить. Применять один раз на затопление, не каждый тик (флаг «уже затоплен»).
   - Сушка: стак wet на складе с mark ≥ +2 → через 2 полных цикла wet=false (Сушила ускорят на этапе 08).
5. Хук плавника из этапа 02: после HIGH спавнить 3–6 стаков driftwood(wet=false) на земле вдоль отметки 0..+1 (сидированный RNG, свободные клетки).
6. Стартовый склад и стартовые ресурсы забега (docs/00 §11.1) — класть при `new_run`.
7. Подключить в SimWorld (порядок систем — docs/02 §4), to_dict/from_dict, события: storage_changed, resources_changed.

## Приёмка (tests/test_storage.gd)
- [ ] store/take с переполнением и нехваткой; prefer_dry берёт сухой плавник раньше мокрого.
- [ ] catch исчезает через 3 цикла; rations — через 12.
- [ ] Затопление склада: соль исчезла, catch −50%, плавник стал wet, слитки целы; повторного применения при том же затоплении нет.
- [ ] Предмет на земле исчезает при затоплении клетки.
- [ ] После HIGH на берегу появляются 3–6 driftwood; при одном сиде — одинаковые позиции.

## Не делать
Агентов-переносчиков, станции, UI складов, лимиты станций.
