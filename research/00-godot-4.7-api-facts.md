# 00 — Проверенные факты Godot 4.7 по рендеру и шейдерам

Всё ниже проверено по `docs.godotengine.org/en/stable` (баннер = «Godot Engine 4.7 documentation»), migration guides 4.5→4.6 и 4.6→4.7, class reference и трекеру issues. Дата ресерча: 2026‑08‑21.

Помеченное `⚠️ НЕ ПОДТВЕРЖДЕНО` — вывод из кода/логики, а не из документации. Такое нельзя вписывать в CONVENTIONS как факт.

---

## 1. Screen texture: единственный правильный синтаксис

`SCREEN_TEXTURE` **удалён** в Godot 4. В документации 4.7 строка про него оставлена только как указатель на миграцию: *«Removed in Godot 4. Use a `sampler2D` with `hint_screen_texture` instead.»*

```glsl
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;

void fragment() {
	COLOR = textureLod(screen_tex, SCREEN_UV, 0.0);
}
```

- `repeat_disable` **обязателен**: при смещённом UV края экрана иначе завернутся, и слева/справа появится полоса «чужой» картинки.
- `filter_nearest` **обязателен** для пиксель‑арта. Популярные шейдеры с godotshaders.com стоят на `filter_linear_mipmap` — это надо менять.
- `textureLod(..., 0.0)` — рекомендация документации. LOD > 0 всё равно не даст блюра без `mipmap` в имени фильтра.
- `source_color` на цветовых uniform'ах — ставить всегда: при включённом HDR 2D (Mobile/Forward+) без него цвета поедут.

Грамматика квалификаторов: `filter[_nearest|_linear][_mipmap][_anisotropic]`, `repeat[_enable|_disable]`.

Другие хинты: `hint_depth_texture`, `hint_normal_roughness_texture` — последний **только Forward+**, у нас Mobile → недоступен. Depth‑буфера в 2D нет вообще (см. §1 файла [01-water-shader.md](01-water-shader.md), проблема «искажение затягивает то, что над водой»).

## 2. Built-ins canvas_item, которые нам нужны

**Глобальные:** `TIME`, `PI`, `TAU`, `E`.

**vertex():** `MODEL_MATRIX`, `CANVAS_MATRIX`, `SCREEN_MATRIX`, `VERTEX` (inout), `UV` (inout), `COLOR` (inout), `TEXTURE_PIXEL_SIZE`, `INSTANCE_CUSTOM`, `VERTEX_ID`, `CUSTOM0/1`.

**fragment():** `FRAGCOORD` (vec4), `SCREEN_UV`, `SCREEN_PIXEL_SIZE` (vec2), `UV`, `COLOR` (inout), `TEXTURE`, `TEXTURE_PIXEL_SIZE`, `REGION_RECT`, `POINT_COORD`, `NORMAL`, `NORMAL_MAP` (out), `LIGHT_VERTEX`, `SHADOW_VERTEX`, `SPECULAR_SHININESS`.

**light():** `void light()` без параметров. `LIGHT` (inout vec4, выход), `LIGHT_COLOR`, `LIGHT_ENERGY`, `LIGHT_POSITION`, `LIGHT_DIRECTION`, `LIGHT_IS_DIRECTIONAL`, `SHADOW_MODULATE` (out).

Три частые ошибки:
1. **`CANVAS_MATRIX` / `SCREEN_MATRIX` доступны ТОЛЬКО в `vertex()`**, не в `fragment()`. Нужную мировую координату во фрагменте получают через `varying`, посчитанный в vertex.
2. **`AT_LIGHT_PASS` не удалён, но всегда `false`.** Это legacy из Godot 3. Использовать нельзя — молча даст неверную ветку.
3. `SCREEN_PIXEL_SIZE` = `1.0 / размер_вьюпорта`. Внутри нашего SubViewport это `vec2(1/640, 1/360)` — то есть смещения задаются в пикселях **мира**, а не окна. Это ровно то, что нужно: настройка не зависит от апскейла ×2/×3/×4.

## 3. Screen-read внутри SubViewport — работает, но с оговорками

Документация («Behind the scenes»): *«In 2D, when `hint_screen_texture` is first found in a node that is about to be drawn, Godot does a full-screen copy to a back-buffer. Subsequent nodes that use it in shaders will not have the screen copied for them.»*

Следствия для нас:

1. **Бэкбуфер — per‑viewport.** Внутри `WorldViewport` (640×360) шейдер читает содержимое самого SubViewport'а, а не окна. Это именно то, что нужно: вода искажает мир в его нативном пиксельном разрешении, до апскейла.
2. **Копия делается автоматически при первом screen‑read узле.** `BackBufferCopy` нужен ТОЛЬКО если два и более screen‑read шейдера перекрываются (второй увидит устаревшую копию). У нас такой шейдер один — вода. Виньетка шторма живёт на UI‑слое и screen texture НЕ читает (см. [04](04-weather-particles-vignette.md)).
3. Если `BackBufferCopy` всё же понадобится — ставить `copy_mode = COPY_MODE_VIEWPORT` (2), а не дефолтный `COPY_MODE_RECT`. Дефолтный `rect` = `Rect2(-100,-100,200,200)`, про него забывают, и эффект отваливается. Плюс баг **#84987** «BackBufferCopy in rect mode behaves erroneously on mobile renderer» — **всё ещё open**, а у нас как раз Mobile.
4. **Не включать `transparent_bg` на WorldViewport.** Баг **#78207** (open с 2023): альфа screen texture у прозрачного вьюпорта всегда 1.0. У нас фон непрозрачный по дизайну — просто не трогать эту настройку.
5. `render_target_update_mode` по умолчанию `UPDATE_WHEN_VISIBLE` — нам подходит. Если WorldContainer может оказаться частично перекрыт панелью и вода замрёт — переключить на `UPDATE_ALWAYS`.
6. `BackBufferCopy` наследуется от `Node2D` → anchors у дочерних `Control` не работают. Control‑ы класть соседом, не ребёнком.

## 4. Mobile renderer и 2D-свет

Таблица `tutorials/rendering/renderers.rst` (4.7): «2D rendering features» — Compatibility ✔️ / Mobile ✔️ / Forward+ ✔️. Оговорок по `PointLight2D`, `DirectionalLight2D`, `LightOccluder2D`, normal maps, `CanvasModulate` для Mobile нет. **Решение этапа 00 (Mobile) корректно, менять не надо.**

Что реально теряем на Mobile против Forward+: `hint_normal_roughness_texture` и compute‑шейдеры. Нам не нужны.
Что имеем на Mobile против Compatibility: MSAA 2D, HDR 2D (`use_hdr_2d`), debanding, RGB10A2/RGBA16F вместо RGBA8.

**Лимиты света:** в документации не задокументированы. Из исходников: `MAX_LIGHTS_PER_ITEM = 16`, `MAX_LIGHTS_PER_RENDER = 256`. ⚠️ **НЕ ПОДТВЕРЖДЕНО** по докам 4.7 (извлечено из ветки master). Наш проектный лимит `Balance.MAX_LIGHTS = 8` — из docs/00 §16, он строже движка и продиктован производительностью, а не API.

`rendering/2d/shadow_atlas/size` — подтверждено, default `2048`, читается **только при старте проекта**; в рантайме — `RenderingServer.canvas_set_shadow_texture_size`.

Перф‑советы из доки: `shadow_filter = PCF13` — *«the most demanding… should only be used for a few lights at once»*; **для пиксель‑арта shadow filter = None**. Для коротких вспышек дешевле `Sprite2D` с additive‑блендом, чем настоящий свет — это ровно приём «запечённые градиент‑спрайты» из промпта 18 п.2.

`CanvasModulate`: *«Only one can be used to tint a canvas»*. SubViewport = отдельный canvas → у мира может быть свой, независимый от UI.

## 5. TIME и пауза — критично для приёмки этапа 18

Дословно из документации 4.7 (global built-ins):

> *«Global time since the engine has started, in seconds. It repeats after every `3,600` seconds… **It's affected by `time_scale` but not by pausing.** If you need a `TIME` variable that is not affected by time scale, add your own global shader uniform and update it each frame.»*

- `get_tree().paused = true` → **`TIME` продолжает идти.** `process_mode` узла тоже не влияет.
- `Engine.time_scale` влияет, но по docs/02 §4 и docs/01 §6 мы `Engine.time_scale` **не используем** — скорость только числом тиков.
- Официального «freeze TIME on pause» нет (issue #27127, не реализован с 2019).
- Rollover: `rendering/limits/time/time_rollover_secs`, default 3600.

**Вывод: `TIME` в шейдерах проекта ЗАПРЕЩЁН.** Всё анимируется от global uniform, привязанного к сим‑тику. Реализация — [05-shader-time-and-pause.md](05-shader-time-and-pause.md).

## 6. Изменения 4.6 и 4.7, которые нас касаются

**4.7:**
- ⚠️ **Breaking: `CanvasItem` больше не добавляет antialiasing feather при рисовании линий (GH‑105122).** Линии в `_draw()` станут тоньше. Прямо касается `TideGauge` (этап 13) — если шкала рисуется `draw_line`, ширину надо задавать явно и проверять на глаз.
- Breaking: `GPUParticles2D`/`CPUParticles2D.request_particles_process()` получил опциональный `process_time_residual` (GH‑109142); `RenderingServer.particles_request_process_time` переименовал `time` → `process_time`.
- Breaking: коррекция angular velocity у частиц — *«Particles using rotation will look subtly different»*.
- Breaking: `ImageTexture`/`PortableCompressedTexture2D.get_format()` уехал в базовый `Texture2D` (GH‑109004).
- Новое и полезное: `GradientTexture2D.FILL_CONIC`; `AtlasTexture` теперь тайлится в `TextureRect` (меньше смен текстур — полезно для атласа UI, этап 18 п.8); inline‑превью шейдеров в редакторе; HDR output.
- ⚠️ НЕ ПОДТВЕРЖДЕНО: сторонние блоги пишут про ограничения препроцессора шейдеров в 4.7. В официальном migration guide такого раздела нет. Вывод: нетривиальные `#define` не использовать, обойдёмся без них.

**4.6:**
- ⚠️ **Glow: дефолтный blend сменился на `Screen`, смешивание теперь до тонмаппинга.** *«…significantly brighter than the previous Soft Light mode.»* Если на этапе 18 захочется 2D glow — картинка будет заметно ярче ожидаемого. Промпт 18 запрещает пост‑процессинг сверх перечисленного, так что glow просто не берём.
- Mobile держит более высокую цветовую точность при HDR 2D.

## 7. Parallax

`ParallaxBackground` имеет официальный баннер **«Deprecated: Use the `Parallax2D` node instead.»** Промпт 18 п.7 уже это учитывает — используем `Parallax2D`. Свойства: `scroll_scale`, `autoscroll`, `scroll_offset`, `screen_offset`, `follow_viewport`, `ignore_camera_scroll`, `limit_begin`/`limit_end`, `repeat_size`, `repeat_times`.

## 8. Открытые баги, релевантные нашему стеку

| # | Заголовок | Статус | Что делать |
|---|---|---|---|
| 78207 | Screen texture alpha of transparent viewport всегда 1.0 | open с 2023 | не включать `transparent_bg` на WorldViewport |
| 84987 | BackBufferCopy rect mode некорректен на Mobile | open с 2023 | если нужен — только `COPY_MODE_VIEWPORT` |
| 116838 | Pixel jitter при движении к краю карты (регресс 4.6) | open | проверить камеру на лимитах карты, этап 02/18 |
| 116700 | Editor oversampling → фризы в больших 2D‑сценах при зуме | open, 4.8 | только редактор, не рантайм |
| 27127 | TIME не останавливается на паузе | не реализован | наш global uniform `sim_time` |

## 9. Чек-лист настроек проекта (сверить на этапе 18)

```
rendering/renderer/rendering_method = mobile
rendering/textures/canvas_textures/default_texture_filter = Nearest
rendering/2d/snap/snap_2d_transforms_to_pixel = true   # на WorldViewport, per-viewport
rendering/2d/snap/snap_2d_vertices_to_pixel = true     # на WorldViewport, per-viewport
rendering/2d/shadow_atlas/size = 512                   # у нас shadow_filter=None, атлас можно урезать
rendering/limits/time/time_rollover_secs = 3600        # не важно: TIME не используем
shader_globals/sim_time = float 0.0                    # см. 05-shader-time-and-pause.md
```

`snap_2d_*` — **per‑viewport**, не глобально (docs/01 §1.1). На UI‑слое снап не нужен и вреден.

---

**Источники:** [canvas_item shader reference](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/canvas_item_shader.html) · [shading language / uniform hints](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html) · [screen-reading shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html) · [BackBufferCopy](https://docs.godotengine.org/en/stable/classes/class_backbuffercopy.html) · [SubViewport](https://docs.godotengine.org/en/stable/classes/class_subviewport.html) · [renderers](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html) · [2D lights and shadows](https://docs.godotengine.org/en/stable/tutorials/2d/2d_lights_and_shadows.html) · [Parallax2D](https://docs.godotengine.org/en/stable/classes/class_parallax2d.html) · [upgrading to 4.7](https://docs.godotengine.org/en/stable/tutorials/migrating/upgrading_to_godot_4.7.html) · [upgrading to 4.6](https://docs.godotengine.org/en/stable/tutorials/migrating/upgrading_to_godot_4.6.html) · godot issues #78207, #84987, #111096, #27127, #105122, #109142
