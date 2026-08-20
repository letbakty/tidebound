# 01 — Шейдер воды: главный визуальный элемент игры

Промпт: `prompts/18-visual-polish.md` п.3 («вода — половина экрана, это главный шейдер игры, 2–3 дня»).
Готовый код: [`code/water.gdshader`](code/water.gdshader), [`code/water_view.gd`](code/water_view.gd).

Требования из промпта дословно: вертикальный градиент прозрачности · синусоидальное искажение того, что под водой (screen texture) · белая кромка‑пена 2px по верхней границе · лёгкая рябь. Плюс п.4 — отражения у кромки. Приёмка: «кромка+искажение+пена видны; на паузе шейдер останавливается (TIME → свой uniform от sim‑тика!)».

---

## 1. Главная архитектурная проблема: в 2D нет depth-буфера

В 2D бэкбуфер — плоский снимок всего, что нарисовано **до** прямоугольника воды. Никакой информации о том, что «за» водой, а что «перед» ней, нет. `hint_depth_texture` в `canvas_item` недоступен (и `hint_normal_roughness_texture` — Forward+ only, а у нас Mobile).

Симптомы наивной реализации:
- волна с амплитудой 3 px у самой кромки подсасывает небо и скалу сверху → кромка «размазывается» и мерцает;
- агент, стоящий по пояс в воде, дублируется по вертикали.

Три приёма, которые это лечат (все три реализованы в `water.gdshader`):

**A. Однонаправленное смещение.** По вертикали сэмплим только вниз:
```glsl
float dy = -abs(sin(px_x * 0.05 + sim_time * 1.3)) * ramp * 0.5;  // всегда <= 0
```

**B. Жёсткий клэмп ниже линии воды.**
```glsl
suv.y = max(suv.y, surf_uv_y + texel.y);
suv   = clamp(suv, vec2(0.0), vec2(1.0) - texel);
```

**C. Гашение амплитуды у кромки.** На глубине 0 искажение = 0, полная сила — на `u_refract_fade_px` (40 px ≈ полярусa):
```glsl
float fade = smoothstep(0.0, 1.0, clamp(depth / u_refract_fade_px, 0.0, 1.0));
```

Плюс к этому — **порядок отрисовки**: всё, что должно преломляться (тайлмапы, агенты, постройки, существа), рисуется до воды. У нас это гарантировано архитектурой (вода на CanvasLayer выше мира, см. §3).

## 2. Одна функция поверхности для всего

Ключевое решение: пена, градиент прозрачности, рефракция и отражение считаются от **одной** функции высоты. Если у пены своя синусоида, а у альфы своя — они разъезжаются на пиксель и кромка мерцает.

```glsl
float wave_height(float x, float amp) {
	float k = TAU_ / u_wave_len_px;
	float t = sim_time * u_wave_speed * k;
	float w = sin(x * k + t);
	w += 0.5  * sin(x * k * 2.17 - t * 1.6 + 1.3);
	w += 0.25 * sin(x * k * 0.41 + t * 0.7 + 2.7);
	return w * (amp / 1.75);
}
```

Множители 2.17 и 0.41 — несоизмеримые, скорости разного знака: получается интерференция, а не читаемая синусоида. `1.75 = 1 + 0.5 + 0.25` — нормировка, чтобы `u_wave_amp_px` означал реальную амплитуду в пикселях.

Дальше всё меряется от `depth`:
```glsl
float surf_y = floor(u_surface_y + wave_height(qx, amp) + 0.5);
float depth  = px_y - surf_y;      // >0 = под водой
```
- пена: `step` по `depth` в диапазоне 0..`u_foam_px`;
- прозрачность: `mix(u_shallow, u_deep, depth / u_depth_range_px)`;
- рефракция: амплитуда × `smoothstep(depth / u_refract_fade_px)`;
- всё, что выше волны (`depth < 0`): `COLOR = vec4(0.0)`.

Последнее важно: **прямоугольник воды не двигается**, он всегда во весь вьюпорт, а шейдер сам вырезает всё над кромкой. Так ColorRect не ползает субпиксельно каждый кадр.

## 3. Где физически живёт нода воды

```
WorldViewport (SubViewport 640×360)
├── World (Node2D, слой 0)            ← тайлмапы, агенты, постройки, существа
│   ├── Ground (TileMapLayer)
│   ├── Ladders (TileMapLayer)
│   ├── Deposits / Agents / Buildings / Creatures
│   └── DepthFog (см. 02-light-fog-atmosphere.md — можно и здесь)
└── WaterLayer (CanvasLayer, layer = 1, follow_viewport_enabled = false)
    └── WaterView (ColorRect, anchors Full Rect, material = water.tres)
```

Почему так, а не «ColorRect в мировых координатах» (как на этапе 02):

| | ColorRect в мире | ColorRect на CanvasLayer |
|---|---|---|
| Позиция кромки | двигается нода → субпиксельный джиттер при зуме/панораме | число в uniform, округлено в GDScript |
| Ширина | надо тянуть на всю карту (48×32 = 1536 px), часть за экраном | ровно 640×360, ни пикселя лишнего |
| `SCREEN_UV` | совпадает с экраном, но UV прямоугольника — нет | UV = экран 1:1, вся математика в пикселях вьюпорта |
| Fillrate | рисуется по всей ширине карты | ровно экран |

Перевод «мировой Y кромки → экранный Y» делает GDScript один раз за кадр:
```gdscript
var world_y: float = (TOP_MARK - _level_shown) * PX_PER_MARK   # +6 сверху, 96 px на ярус
var screen_y: float = (get_viewport().get_canvas_transform() * Vector2(0.0, world_y)).y
_mat.set_shader_parameter(&"u_surface_y", floorf(screen_y))
```
`get_canvas_transform()` уже включает позицию и зум Camera2D. `floorf` — обязательный снап.

**Порядок отрисовки:** мир на layer 0 нарисован → авто‑копия в бэкбуфер срабатывает на WaterView → вода читает мир. `BackBufferCopy` НЕ нужен: screen‑read шейдер в проекте один.

## 4. Плавность кромки: сим тикает 10 Гц, экран 60 Гц

`Events.water_level_changed` по контракту (docs/02 §3.2) приходит «раз в 3 тика достаточно» — то есть ~3.3 раза в секунду. В фазе `HIGH` вода идёт «стеной» от −6 до 0 за 20 с, это 6 ярусов × 96 px = 576 px за 20 с ≈ 29 px/с. Без сглаживания кромка прыгала бы ступеньками по ~9 px.

Решение в `water_view.gd`: сим‑уровень — цель, показываемый — лерп к ней (`LEVEL_LERP = 18.0`). Задержка ~55 мс, глазом не видна, а движение непрерывное.

То же и с `sim_time`: он берётся как `tick/10.0 + _accum`, то есть с дробной частью тика — волна двигается на 60 fps, а не 10.

## 5. Отражения (промпт 18 п.4) — три подхода, берём третий

| Подход | Стоимость | Плюсы | Минусы |
|---|---|---|---|
| A. Второй Camera2D в SubViewport с `scale.y = -1` | **полный второй проход сцены** | геометрически честно, отражает то, что за кадром | ×2 draw calls: утёс + все агенты рисуются дважды |
| B. Дубли‑спрайты `scale.y = -1`, `modulate.a = 0.2` | дёшево, точечно | контроль (отражаем 5 ближних агентов) | ручная синхронизация из GDScript; тайлмап утёса не отразить без дубля тайлмапа |
| C. **Шейдер зеркалит тот же бэкбуфер** | **≈ бесплатно** | ноль лишних draw calls, бэкбуфер уже скопирован ради рефракции | отражается только то, что попало в кадр и нарисовано до воды |

**Берём C.** Ограничение («верхушка утёса за кадром не отразится») для вертикального среза несущественно: интересна только зона у самой кромки, а `u_reflect_fade_px = 48` гасит отражение через полярусa.

Обязательная защита от рекурсии:
```glsl
if (ruv.y > 0.0 && ruv.y < surf_uv_y) { ... }
```
Без неё отражение сэмплит уже нарисованную воду.

Если позже понадобится отражать конкретный объект «честно» (судно на 12‑м цикле) — добавить B точечно поверх C, они не конфликтуют.

## 6. Пиксель-арт: три независимых квантования

`filter_nearest` **сам по себе не спасает** — сэмпл всё равно скачет между соседними текселями неравномерно. Нужны все три:

1. **Смещение UV → целые пиксели источника:**
   `vec2 off = floor(vec2(dx, dy) + 0.5); vec2 suv = SCREEN_UV + off * texel;`
2. **Волна → целые пиксели по Y** (`floor(... + 0.5)`) **и ступенька по X** (`u_quant_x_px = 2.0`). Ступенька по X даёт классический вид Celeste/Owlboy: волна ползёт «лесенкой», а не гладко.
3. **`filter_nearest` + `repeat_disable`** на `screen_tex`. Популярный [2D Water distortion effect (Godot 4)](https://godotshaders.com/shader/2d-water-distortion-effect-godot-4/) стоит на `filter_linear_mipmap` — для нас это противопоказано, менять при копировании.

Плюс на уровне вьюпорта: `snap_2d_transforms_to_pixel` и `snap_2d_vertices_to_pixel = true` на WorldViewport (уже сделано на этапе 00), камера с `round()` позиции и **без** position smoothing (docs/01 §1.1 — задокументированный джиттер).

## 7. Таблица uniform'ов и стартовые значения

| Uniform | Старт | Смысл | Кто пишет в рантайме |
|---|---|---|---|
| `sim_time` (global) | — | секунды симуляции | `Game._push_shader_time()` каждый кадр |
| `u_view_size` | `(640, 360)` | размер вьюпорта в px | `WaterView._ready()` |
| `u_surface_y` | — | экранный Y кромки, округлён | `WaterView._process()` |
| `u_shallow` | `#2d6b7a`, a=0.40 | цвет мелководья (палитра docs/01 §4) | — |
| `u_deep` | `#1a3a4a`, a=0.90 | цвет глубины | — |
| `u_foam` | `#e8eff0` | пена (= цвет текста UI, единая палитра) | — |
| `u_depth_range_px` | `160` | глубина выхода на `u_deep` (≈1.7 яруса) | — |
| `u_wave_amp_px` | `3.0` | амплитуда волны | — |
| `u_wave_len_px` | `96.0` | длина волны = один ярус | — |
| `u_wave_speed` | `10.0` | дрейф, px/с | — |
| `u_quant_x_px` | `2.0` | ступенька волны по X | — |
| `u_foam_px` | `2.0` | толщина пены (промпт: 2px) | — |
| `u_refract_px` | `3.0` | амплитуда искажения | — |
| `u_refract_fade_px` | `40.0` | глубина выхода искажения на полную | — |
| `u_reflect_alpha` | `0.20` | промпт 18 п.4 дословно | — |
| `u_reflect_fade_px` | `48.0` | глубина затухания отражения | — |
| `u_caustics` | `0.08` | сила ряби | — |
| `u_storm` | `0.0` | 0..1, шторм усиливает волну и искажение | `WaterView` по `crisis_started/ended` |

Все эти числа — **визуальные, не игровые**. По CONVENTIONS игровые числа живут в `Balance`; эти остаются в `.tres` материала (`assets/shaders/water_material.tres`), потому что их правит художник в инспекторе, а не геймдизайнер в балансе. Зафиксировать это решение комментарием `# РЕШЕНИЕ:` в `water_view.gd`.

## 8. Производительность

Три статьи затрат, все три для нас малы:

1. **Копия в бэкбуфер.** 640×360 = 230k пикселей ≈ 0.9 MB RGBA8. Копия происходит **внутри SubViewport, до апскейла** — не 1280×800. Форумный консенсус: [размер копии не значим на фоне остального рендера](https://forum.godotengine.org/t/backbuffercopy-rect-mode-does-not-improve-performance/51415).
2. **Фрагментный шейдер.** 2 текстурные выборки (рефракция + отражение) на ~115k фрагментов нижней половины. Тривиально. `sin()` дёшев — 3 синуса не проблема, заменять на текстуру шума ради скорости не надо.
3. **Fillrate после апскейла** от шейдера воды не зависит вообще — рисуется один растянутый прямоугольник SubViewportContainer'а.

Оценка (⚠️ **НЕ ПОДТВЕРЖДЕНО**, порядок величины): Steam Deck < 0.3 мс на весь эффект, средний Android < 1.5 мс. Бюджет по docs/00 §16 — 60 fps на Deck, ≥30 fps на Redmi Note 11; запас есть.

Реальные риски не в шейдере, а в: лишних `BackBufferCopy` (каждый = ещё одна полная копия — не добавлять ни одного), отключённом `snap_2d_*`, и в количестве `PointLight2D` (см. [02](02-light-fog-atmosphere.md)).

## 9. Порядок работы на этапе 18

1. Перенести `code/water.gdshader` → `godot/assets/shaders/water.gdshader`.
2. Создать `assets/shaders/water_material.tres` (ShaderMaterial) со значениями из таблицы §7.
3. Добавить `shader_globals/sim_time` (float) в Project Settings; врезать `_push_shader_time()` в `game.gd` ([`code/shader_time.gd`](code/shader_time.gd)).
4. Пересобрать `world.tscn`: WaterLayer (CanvasLayer, layer 1) → WaterView (ColorRect Full Rect). Старый мировой ColorRect этапа 02 удалить.
5. Перенести `code/water_view.gd`, проверить, что `SimTypes.CrisisType.STORM` существует (этап 09).
6. Настройка по шагам, в этом порядке (иначе не видно, что чинишь): сначала альфа‑градиент → потом волна+пена → потом рефракция → потом отражение → потом рябь.
7. Проверка паузы: пауза на подъёме в `HIGH` — всё замирает.
8. Проверка сизигии: `Debug`‑слайдер override уровня (этап 03) на +2 и на −12; кромка не выходит за экран, артефактов на границах нет.

---

**Источники:** [screen-reading shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html) · [canvas_item shader reference](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/canvas_item_shader.html) · [2D water surface with wave and noise](https://godotshaders.com/shader/2d-water-surface-with-wave-and-noise/) · [Water 2D + reflection 4.x](https://godotshaders.com/shader/water-2d-reflection-4-x/) · [2D Pixel Art Water](https://godotshaders.com/shader/2d-pixel-art-water/) · [Pixel Quantization](https://godotshaders.com/shader/pixel-quantization/) · [форум: water shader distorts objects in front](https://forum.godotengine.org/t/water-shader-distorts-objects-in-front-depth-issue-godot-4-6/136367)
