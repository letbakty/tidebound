# Этап 02 — Мир: ярусы, граф навигации, депозиты, отрисовка утёса и воды

**Модель:** Opus 5 или Fable 5 (структуры данных + первый визуальный слой).
**Зависит от:** 01. **Читать:** docs/00 §3, §5; docs/02 §2, §5.
**Результат:** утёс №1 виден на экране, вода ходит по фазам, есть граф площадок/лестниц и депозиты с данными.
**Ресерч:** [research/12-terrain-tilemap-camera.md](../research/12-terrain-tilemap-camera.md) — TileMapLayer 4.7, генерация тайлсета скриптом, `WorldGeo`, `AStar2D`, `is_flooded`, камера. Дополнительно: [research/01](../research/01-water-shader.md) §7 и [research/06](../research/06-pixel-art-pitfalls.md) (куда класть воду, чтобы этап 18 не переделывал).
**Готовый код:** `research/code/world_geo.gd` → `game/world_geo.gd`; `research/code/water_view.gd` → `game/water_view.gd` (заготовка) — переноси, а не пиши с нуля (черновики под контракты docs/02, но не компилировались: сверь имена полей с тем, что реально сделали прошлые этапы).

## Задача — sim-часть
1. `data/defs/cliff_def.gd` — `class_name CliffDef extends Resource`: `@export width: int, height: int`, `@export platforms: Array[Dictionary]` (`{mark:int, x0:int, x1:int}` — площадки по отметкам), `@export start_ladders: Array[Dictionary]`, `@export deposit_slots: Array[Dictionary]` (`{kind:String, mark:int, x:int}`), `@export spawn_cell: Vector2i`.
2. `data/cliffs/cliff_01.tres` — карта утёса №1 по docs/00 §3.1: 48×45, жилые площадки +1..+6 слева, ступени дна −1..−8 вправо; слоты депозитов по таблице §3.2 (руины ближние ×3, глубокие ×3, отмель ×2, водоросли ×2); стартовая деревянная лестница до −2. Расставь осмысленно: чем глубже, тем дальше от лестниц.
3. `sim/terrain.gd` — `class_name Terrain`: строится из CliffDef. Хранит: площадки (id, mark, x-диапазон), рёбра (лестницы; добавляются/удаляются в рантайме — API `add_ladder(cell)/remove_ladder(id)`), депозиты (id, kind, cell, amount, refill). Функции: `mark_of_cell(cell) -> int`, `platform_at(cell)`, `find_path(from_platform, to_platform) -> Array[int]` — **`AStar2D` вместо ручного BFS** ([research/12](../research/12-terrain-tilemap-camera.md) §4: он `RefCounted`, значит законен в `sim/`, и даёт детерминированный тай-брейк бесплатно), `is_flooded(cell, water_level) -> bool`, `nearest_ladder_dist(cell) -> float`.
4. Депозиты: `take(deposit_id, n) -> int` (сколько реально взято), восполнение по правилам §3.2 — вызывается на `cycle_started`. Плавник: спавн 3–6 предметов «на земле» вдоль отметки 0..+1 после HIGH (пока — просто депозит-одноразка kind=driftwood, полноценные предметы на земле — этап 04; оставь TODO-хук).
5. Подключи Terrain в `SimWorld` (создание из CliffDef при `new_run`, `to_dict/from_dict` — только изменяемое: депозиты, добавленные лестницы).

## Задача — презентация
6. `game/world.tscn` — корень мира (кладётся в мировой SubViewport из этапа 00): `TileMapLayer` Ground (тайлсет-заглушку **генерировать скриптом**, готовый `tools/gen_placeholder_tileset.gd` — в [research/12](../research/12-terrain-tilemap-camera.md) §2; 3 цвета — камень утёса, песок отмели, руины), `TileMapLayer` Ladders, `Node2D` Deposits (по спрайту-заглушке 32×32 с буквой ресурса), `WaterView`.
7. `game/water_view.gd` — **заготовка из `research/code/water_view.gd`**. ⚠️ Класть сразу правильно, чтобы этап 18 ничего не переделывал ([research/12](../research/12-terrain-tilemap-camera.md) §7): `ColorRect` на **`CanvasLayer` внутри WorldViewport** (`layer = 10`, `follow_viewport_enabled = true`), Full Rect, позиция кромки передаётся **числом в uniform**, а не размером ноды. Полупрозрачный синий; слушает `Events.water_level_changed`. Шейдер — этап 18, здесь только материал-заглушка.
8. `game/camera_rig.gd` — Camera2D: панорама (ПКМ-драг + стрелки/WASD), **зум ступенями ×2/×3/×4 камерой** (сюда переезжает `set_world_zoom` из этапа 00), лимиты по краям карты, старт на spawn_cell. ⚠️ Не включать `position_smoothing` вместе с pixel snap (issue 93048: дрожь в масштабированном SubViewport) — плавность через виртуальную позицию с округлением, рецепт в [research/12](../research/12-terrain-tilemap-camera.md) §6.4.
9. Конверсии cell↔world — **перенеси готовый `research/code/world_geo.gd` в `game/world_geo.gd`**: единственное место в проекте, где мировые координаты связаны с сеткой и отметками. Всё остальное (WaterView, DebugOverlay, BuildGhost, CameraRig) зовёт оттуда. `TOP_MARK`/`PX_PER_MARK` — в `Balance`, не дублировать.
10. `World.pick_at(pos)` — один хит-тест без физики на все будущие этапы (05, 07, 09, 14). Реализация — [research/15](../research/15-agents-fsm-views.md) §7.

## Приёмка
- [ ] Запуск: виден срез утёса, вода опускается и поднимается по фазам, камера управляется.
- [ ] tests/test_terrain.gd: mark_of_cell по 5 контрольным клеткам; путь между двумя площадками существует и проходит через лестницу; is_flooded меняется при изменении уровня; депозит.take не уходит в минус; восполнение отмели работает.
- [ ] Детерминизм-тест этапа 01 всё ещё зелёный.

## Не делать
Агентов, предметы на земле (кроме TODO-хука), стройку, шейдеры, свет, финальный арт (только заглушки-тайлы), UI поверх мира.
