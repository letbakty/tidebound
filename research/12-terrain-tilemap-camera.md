# 12 — Мир: TileMapLayer, граф площадок, конверсии координат, камера

**Для этапов:** 02 (весь), 03 (оверлеи), 07 (призрак размещения), 18 (спрайты, параллакс).
**Дата ресерча:** 2026-08-21. **Движок:** Godot 4.7.x stable.

---

## 1. TileMapLayer в 4.7: точный API

Нода `TileMap` **удалена как рабочая** (deprecated с 4.3, в 4.7 её использовать нельзя — CONVENTIONS это фиксирует). Каждый слой — отдельный `TileMapLayer`, у каждого свой `tile_set`.

**Сигнатуры, проверенные по class reference 4.7:**
```gdscript
void      set_cell(coords: Vector2i, source_id: int = -1,
                   atlas_coords: Vector2i = Vector2i(-1, -1),
                   alternative_tile: int = 0)
int       get_cell_source_id(coords: Vector2i) const
Vector2i  get_cell_atlas_coords(coords: Vector2i) const
TileData  get_cell_tile_data(coords: Vector2i) const
Vector2i  local_to_map(local_position: Vector2) const
Vector2   map_to_local(map_position: Vector2i) const
Array[Vector2i] get_used_cells() const
Array[Vector2i] get_surrounding_cells(coords: Vector2i)
```
Свойства: `tile_set`, `enabled = true`, `y_sort_origin = 0`, `navigation_enabled = true`, `rendering_quadrant_size = 16`, `collision_enabled = true`.

**Ловушки:**

1. **`set_cell` БЕЗ номера слоя.** В 3.x/раннем 4.x было `set_cell(layer, coords, ...)`. Сейчас первый аргумент — координаты. Это самая частая галлюцинация модели на этом этапе.
2. **`source_id = -1` стирает клетку.** `set_cell(c)` с одним аргументом = erase. Отдельного `erase_cell` нет.
3. **`local_to_map` работает в ЛОКАЛЬНЫХ координатах ноды, не в глобальных.** Если `TileMapLayer` смещён или отмасштабирован, `local_to_map(get_global_mouse_position())` даст мусор. Правильно: `layer.local_to_map(layer.to_local(global_pos))`.
4. **`map_to_local` возвращает ЦЕНТР клетки**, а не левый-верхний угол. Для отрисовки прямоугольника-подсветки надо вычитать `tile_size / 2`. ⚠️ Забыть — значит получить призрак постройки, смещённый на пол-тайла (промпт 07).
5. **`navigation_enabled = true` и `collision_enabled = true` по умолчанию.** Мы физику и навигацию движка не используем (docs/02 §1) — **выключить оба на всех слоях**: это экономит построение навмешей и коллизий при каждом `set_cell` на карте 48×45.
6. `get_surrounding_cells` учитывает форму тайлов (квадрат/гекс/изометрия). У нас square — вернёт 4 соседа. Для 8-связности использовать нельзя.
7. **`y_sort_enabled` — свойство `CanvasItem`, а не TileMapLayer-специфичное**; `y_sort_origin` (int) сдвигает точку сортировки. Для утёса в разрезе Y-sort нужен только контейнеру агентов/построек, тайлам — нет.

---

## 2. TileSet программно: быстрый путь к заглушкам

Промпт 02 требует «заглушечный тайлсет: 3 цвета». Рисовать PNG и настраивать источники в редакторе — 40 минут кликов. **Быстрее — сгенерировать текстуру и TileSet скриптом один раз.**

```gdscript
@tool
extends EditorScript
## tools/gen_placeholder_tileset.gd — File → Run. Создаёт атлас 3×1 и tileset.tres.

const TILE: int = 32
const COLORS: Array[Color] = [
	Color("6b6257"),  # 0 камень утёса
	Color("d8c08a"),  # 1 песок отмели
	Color("4a5b63"),  # 2 руины
]

func _run() -> void:
	var img := Image.create(TILE * COLORS.size(), TILE, false, Image.FORMAT_RGBA8)
	for i: int in COLORS.size():
		img.fill_rect(Rect2i(i * TILE, 0, TILE, TILE), COLORS[i])
		# тёмная кромка сверху — читаемость ярусов без арта
		img.fill_rect(Rect2i(i * TILE, 0, TILE, 2), COLORS[i].darkened(0.35))
	img.save_png("res://assets/sprites/placeholder_tiles.png")

	var tex := ImageTexture.create_from_image(img)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(TILE, TILE)
	for i: int in COLORS.size():
		src.create_tile(Vector2i(i, 0))

	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_source(src, 0)                       # source_id = 0
	ResourceSaver.save(ts, "res://data/tilesets/placeholder.tres")
	print("tileset готов")
```

Дальше в коде мира: `ground.set_cell(cell, 0, Vector2i(kind, 0))`.

⚠️ **Порядок операций важен:** `src.texture` должен быть присвоен **до** `create_tile`, иначе источник не знает своей сетки и `create_tile` молча ничего не сделает.

⚠️ **`ImageTexture` из сгенерированного `Image` не сохранится в `.tres` как ссылка на PNG** — она встроится бинарно. Поэтому сначала `save_png`, потом при желании перезагрузить `load("res://assets/sprites/placeholder_tiles.png")` и присвоить — тогда `.tres` будет ссылаться на файл, и художник просто перерисует PNG.

**Custom data layers** — не использовать. Соблазн положить `mark`/`walkable` в TileData и читать оттуда велик, но это протащит презентационную ноду в логику: `Terrain` в `sim/` не имеет права трогать `TileMapLayer`. **Единственный источник правды о ярусах — `CliffDef` + `Terrain`; тайлмап только рисует.**

---

## 3. Конверсии координат: одно место, три функции

Самый частый источник багов этапов 02/03/07/14 — «то же самое, посчитанное по-разному в четырёх файлах». Промпт 02 п.9 требует статических функций в `game/world.gd`. Вот что там должно быть — и почему именно это:

```gdscript
class_name WorldGeo
extends RefCounted
## Единственное место, где мировые координаты связаны с сеткой и отметками.
## Всё остальное (WaterView, DebugOverlay, BuildGhost, CameraRig) зовёт отсюда.

const TILE: int = 32
const TOP_MARK: int = 6          # верхняя отметка карты
const TILES_PER_MARK: int = 3    # 1 ярус = 3 тайла по вертикали
const PX_PER_MARK: int = TILES_PER_MARK * TILE   # 96

static func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE, cell.y * TILE)

static func world_to_cell(p: Vector2) -> Vector2i:
	# floori, а не int(): при отрицательных координатах int() округляет к нулю
	return Vector2i(floori(p.x / float(TILE)), floori(p.y / float(TILE)))

static func mark_to_world_y(mark: float) -> float:
	return (float(TOP_MARK) - mark) * float(PX_PER_MARK)

static func world_y_to_mark(y: float) -> float:
	return float(TOP_MARK) - y / float(PX_PER_MARK)

static func cell_to_mark(cell: Vector2i) -> int:
	return TOP_MARK - floori(float(cell.y) / float(TILES_PER_MARK))
```

**Технические обоснования:**
- **`floori`, а не `int()`.** `int(-0.5)` = 0, `floori(-0.5)` = -1. Ниже отметки 0 у нас вся вторая половина карты — с `int()` там будет ошибка на клетку, которая проявится как «агент проваливается сквозь площадку».
- **`mark_to_world_y` принимает `float`, а не `int`** — потому что уровень воды дробный (−8.0…+2.0), и `WaterView` считает Y по нему же. Одна функция для целых отметок и для воды гарантирует, что кромка воды всегда совпадает с сеткой ярусов.
- **Константы `TOP_MARK` и `PX_PER_MARK` — здесь, а не в `Balance`.** Спорно: research/README рекомендует держать их «в одном месте (Balance или world.gd)». ⚠️ **Решение: `Balance` — источник правды (sim их тоже использует для `is_flooded`), `WorldGeo` их импортирует.** Иначе получится два числа, и на этапе 18 вода уедет на 96 пикселей.

---

## 4. Граф площадок: AStar2D вместо ручного BFS

Промпт 02 говорит «BFS по графу — граф маленький, хватит». Это правда. Но **`AStar2D` — это `RefCounted`, его можно использовать прямо в `sim/`**, и он даёт больше за меньший код:

```gdscript
class_name Terrain
extends RefCounted

var _astar: AStar2D = AStar2D.new()
var graph_version: int = 0

func _rebuild_graph() -> void:
	_astar.clear()
	for p: Dictionary in platforms:
		# позиция узла — центр площадки в мировых координатах:
		# _astar сам посчитает эвристику расстояния, ручной _estimate_cost не нужен
		_astar.add_point(p["id"], Vector2(
			(p["x0"] + p["x1"]) * 0.5 * WorldGeo.TILE,
			WorldGeo.mark_to_world_y(float(p["mark"]))))
	for e: Dictionary in edges:              # лестницы и смежность площадок
		_astar.connect_points(e["a"], e["b"], true)
	graph_version += 1

func find_path(from_id: int, to_id: int) -> Array[int]:
	var raw: PackedInt64Array = _astar.get_id_path(from_id, to_id)
	var out: Array[int] = []
	for v: int in raw:
		out.append(int(v))
	return out

func add_ladder(cell: Vector2i) -> int:
	# ... регистрация ребра ...
	_rebuild_graph()     # граф из ~30 узлов: полная перестройка дешевле инкремента
	return ladder_id
```

**Почему это выгоднее ручного BFS:**
- `get_id_path` возвращает `PackedInt64Array` — **готовый путь по id**, без ручного восстановления предков.
- `set_point_disabled(id, true)` — одна строка, чтобы «выключить» затопленную площадку, не трогая рёбра. Прямо нужно этапу 09 (существа ходят **только** по затопленным узлам — им нужен инвертированный набор).
- `weight_scale` у точки — бесплатный способ сделать лестницы «дороже» (агент на лестнице медленнее): `add_point(id, pos, 1.0)` для площадок, `1.7` для узлов-лестниц.
- Док подтверждает детерминизм тай-брейка `get_closest_point`: *«the one with the smallest ID will be returned, ensuring a deterministic result»*.

⚠️ **Что проверить самим (док молчит): детерминирован ли сам `get_id_path` при двух путях равной стоимости.** Внутри — бинарная куча, порядок зависит от порядка `connect_points`. Раз мы всегда перестраиваем граф целиком и в одном и том же порядке (по возрастанию id площадок и рёбер), результат будет стабильным. **Обязательно закрыть тестом:**
```gdscript
t.check(terrain.find_path(0, 9) == terrain.find_path(0, 9), "путь нестабилен")
# и после save/load:
t.check(restored.find_path(0, 9) == live.find_path(0, 9), "путь разошёлся после загрузки")
```
Если тест когда-нибудь покраснеет — откатиться на собственный BFS с обходом соседей в порядке возрастания id (тогда детерминизм гарантирован конструкцией). **`AStar2D` не сериализуется и не должен: это производное состояние, восстанавливается из `platforms`/`edges` в `from_dict`.**

**Два графа, а не один.** Агенты ходят по сухим узлам, существа — по затопленным. Держать два `AStar2D` и пересобирать «мокрый» при пересечении уровнем воды отметки (а не каждый тик!) дешевле, чем фильтровать путь после поиска.

---

## 5. `is_flooded`: формула и троттлинг

```gdscript
func is_flooded(cell: Vector2i, water_level: float) -> bool:
	# Клетка затоплена, если её отметка НИЖЕ уровня воды.
	# Строгое сравнение: на ровно равном уровне клетка ещё сухая —
	# иначе на плато LOW=-8.0 нижняя ступень будет мигать от float-шума.
	return float(WorldGeo.cell_to_mark(cell)) < water_level - 0.001
```
⚠️ **Эпсилон обязателен.** Уровень воды считается по smoothstep и на плато даёт `-7.9999999`, а не `-8.0`. Без эпсилона `is_flooded` для отметки −8 будет отдавать то `true`, то `false` — и склад на −8 будет «затапливаться» по нескольку раз за цикл, ломая приёмку этапа 04 («повторного применения при том же затоплении нет»).

**Правильный паттерн «событие пересечения», а не «состояние»:**
```gdscript
# В системе, которую волнует затопление (storage/building):
var _last_level: float = 0.0
func on_tick(level: float) -> void:
	for obj in objects:
		var m: float = float(obj.mark)
		var was: bool = m < _last_level
		var now: bool = m < level
		if now and not was:
			_on_flooded(obj)        # ровно один раз на пересечение
		elif was and not now:
			_on_dried(obj)
	_last_level = level
```
Это устраняет и флаг «уже затоплен», и его сериализацию: пересечение выводится из двух уровней, а `_last_level` — одно число в сейве.

---

## 6. Камера: лимиты, зум ступенями, панорама, пиксель

### 6.1 Свойства Camera2D 4.7 (проверено)
`position_smoothing_enabled` (false), `position_smoothing_speed` (5.0), `drag_*_enabled`, `drag_*_margin` (0.2), `limit_left/right/top/bottom`, `limit_enabled` (true), `limit_smoothed` (false), `zoom` (Vector2(1,1)), `anchor_mode`, `ignore_rotation` (true), `process_callback`.
Методы: `align()`, `force_update_scroll()`, `get_screen_center_position()`, `reset_smoothing()`, `make_current()`.
Док: *«`limit_smoothed` has no effect if `position_smoothing_enabled` is false»*.

### 6.2 Лимиты считаются от карты и от зума
```gdscript
func _apply_limits() -> void:
	var map_px := Vector2(cliff.width * WorldGeo.TILE, cliff.height * WorldGeo.TILE)
	limit_left = 0
	limit_top = 0
	limit_right = int(map_px.x)
	limit_bottom = int(map_px.y)
```
⚠️ **Лимиты — в мировых координатах и НЕ зависят от zoom**, но видимая область зависит. Если карта уже вьюпорта при zoom<1, камера упрётся в лимиты и «застрянет» в углу. Для карты 48×45 тайлов = 1536×1440 px против вьюпорта 640×360 запаса хватает, но при зуме 4 (мир 320×180) — тоже. Всё ок, но **проверить на самом дальнем зуме**.

⚠️ **Открытый баг #116838: pixel jitter у края карты (регресс 4.6)** — уже отмечен в research/00. Проявляется именно при упоре в `limit_*`. Проверять панораму до края обязательно.

### 6.3 Зум ступенями без дробного пикселя
```gdscript
const ZOOM_STEPS: Array[float] = [1.0, 2.0, 4.0]   # только степени двойки!
var _zoom_idx: int = 0

func set_zoom_step(idx: int) -> void:
	_zoom_idx = clampi(idx, 0, ZOOM_STEPS.size() - 1)
	var target := Vector2.ONE * ZOOM_STEPS[_zoom_idx]
	# Плавный визуальный переход с «приземлением» на целое (docs/01 §1.1)
	var tw := create_tween()
	tw.tween_property(self, "zoom", target, 0.15)\
	  .set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
```
**Только целые (лучше — степени двойки) значения зума.** `zoom = 1.5` в пиксель-арте даёт неравномерные пиксели (одни тайлы 48px, другие 47) — это выглядит как грязь и не лечится фильтром. Промежуточные значения допустимы **только во время анимации перехода**, конечное состояние всегда целое.

### 6.4 Панорама и дрожь
Промпт требует ПКМ-драг + WASD. Ключевая техника — **не двигать камеру напрямую мышью**, а вести «виртуальную» дробную позицию и снапить настоящую:

```gdscript
var _virtual_pos: Vector2 = Vector2.ZERO

func _process(delta: float) -> void:
	var dir := Input.get_vector("pan_left", "pan_right", "pan_up", "pan_down")
	_virtual_pos += dir * PAN_SPEED * delta / zoom.x
	_virtual_pos = _virtual_pos.clamp(_limit_min, _limit_max)
	global_position = _virtual_pos.round()   # камера всегда на целом пикселе
```
Это ровно приём из демо `voithos/godot-smooth-pixel-camera-demo`: *«We keep track of a precise "virtual" position that the camera is currently at, but snap the actual `global_position` to whole integer pixels.»*

**Апгрейд (для этапа 18, не для 02):** демо идёт дальше — считает `pixel_snap_delta = virtual_pos - snapped_pos` и сдвигает на него **отображающий спрайт** вьюпорта, получая субпиксельно-плавное движение при пиксельно-чётком мире. У нас вместо `Sprite2D` стоит `SubViewportContainer`, поэтому сдвигать надо `WorldContainer.position` на `delta * stretch_shrink` (в наших экранных пикселях это будет целое число при shrink=2 и полупиксель — при нечётном сдвиге). ⚠️ Требует +1 px запаса в SubViewport (641×361), иначе на краю появится незакрашенная полоса. **Не делать на этапе 02** — записать в research/07-stage-18-plan как опцию полировки.

### 6.5 `position_smoothing` включать или нет?
Промпт 13 требует «плавный центр камеры на агенте». Два способа:
- `position_smoothing_enabled = true` + менять цель — просто, но постоянно даёт дробную позицию → см. §6.4, надо снапить, а снапить смуженное значение движок не даст.
- **Tween по `_virtual_pos`** — управляемо, снап сохраняется, легко прервать пользовательской панорамой.

**Рекомендация: `position_smoothing_enabled = false`, вся плавность — через Tween по `_virtual_pos`.** Заодно решается требование промпта 13 «никакого похищения камеры при событиях»: Tween можно `kill()` при первом же вводе игрока.

---

## 7. `WaterView` на этапе 02: как положить так, чтобы этап 18 не переделывал

Из research/README (раздел «Что стоит учесть на этапах ДО 18-го») — здесь техническая расшифровка:

```
WorldViewport
└── World (Node2D)
    ├── Ground (TileMapLayer)
    ├── Ladders (TileMapLayer)
    ├── Deposits (Node2D)
    ├── Agents (Node2D, y_sort_enabled = true)
    └── FxLayer (CanvasLayer, layer = 10, follow_viewport_enabled = true)
        └── WaterRect (ColorRect, Full Rect 640×360)   ← на 18-м сюда встанет шейдер
```

**Три технических требования:**
1. **`WaterRect` — статичный, Full Rect, НЕ двигается.** Позиция кромки воды передаётся числом (`water_screen_y: float`) в материал/скрипт. Двигающийся ColorRect даёт субпиксельный джиттер относительно мира (research/06 §4).
2. **`CanvasLayer.follow_viewport_enabled = true`** — иначе слой не будет двигаться вместе с камерой и «мировая» привязка сломается. ⚠️ Свойство именно `follow_viewport_enabled` (+ `follow_viewport_scale`), не `follow_viewport`.
3. Конверсия «уровень воды → экранный Y» пишется **один раз** в `water_view.gd` и использует `WorldGeo.mark_to_world_y` + текущую трансформацию камеры:
```gdscript
func _refresh(level: float) -> void:
	var world_y: float = WorldGeo.mark_to_world_y(level)
	var cam: Camera2D = get_viewport().get_camera_2d()
	var screen_y: float = (world_y - cam.get_screen_center_position().y) * cam.zoom.y \
		+ get_viewport_rect().size.y * 0.5
	# На этапе 02 — просто двигаем anchor/размер ColorRect'а вниз от screen_y.
	# На этапе 18 — material.set_shader_parameter("water_y", screen_y).
```
Заложив `screen_y` уже сейчас, на 18-м останется только надеть материал.

---

## 8. Чек-лист приёмки этапа 02

- [ ] `WorldGeo.cell_to_mark` даёт правильные значения на 5 контрольных клетках, включая отрицательные Y.
- [ ] `find_path` между площадками +6 и −8 существует и содержит узел лестницы.
- [ ] `find_path(a,b)` возвращает одинаковый массив при двух вызовах подряд (детерминизм графа).
- [ ] `is_flooded` для клетки на отметке −8 не мигает при плато LOW (прогнать 500 тиков, посчитать переключения — должно быть ровно 2 за цикл).
- [ ] Камера доезжает до всех четырёх краёв карты, на краю нет дрожания (баг #116838).
- [ ] `WaterRect` не смещается относительно тайлов при панораме на любом зуме.
- [ ] Тест детерминизма этапа 01 всё ещё зелёный (Terrain добавил состояние в `to_dict`).

---

## Источники

- [TileMapLayer (Godot 4.7)](https://docs.godotengine.org/en/stable/classes/class_tilemaplayer.html) — сигнатуры set_cell/local_to_map/map_to_local, свойства
- [Camera2D (Godot 4.7)](https://docs.godotengine.org/en/stable/classes/class_camera2d.html) — limits, smoothing, zoom
- [AStar2D (Godot 4.7)](https://docs.godotengine.org/en/stable/classes/class_astar2d.html) — API и детерминизм
- [voithos/godot-smooth-pixel-camera-demo](https://github.com/voithos/godot-smooth-pixel-camera-demo) — виртуальная позиция + snap + nudge
- [godot#116838](https://github.com/godotengine/godot/issues/116838) — jitter у края карты (регресс 4.6)
- [godot#93048](https://github.com/godotengine/godot/issues/93048) — Camera2D в масштабированном SubViewport
