# 07 — План выполнения этапа 18 и профилирование

Пошаговый порядок работ по `prompts/18-visual-polish.md` с готовым кодом из [`code/`](code/). Порядок не произвольный: каждый шаг проверяем глазами до того, как поверх него ляжет следующий, иначе непонятно, что чинишь.

---

## 0. Подготовка (30 минут)

1. **Project Settings → Shader Globals:** добавить `sim_time` типа `float`.
2. **`autoload/game.gd`:** врезать `sim_seconds()` и `_push_shader_time()` — [`code/shader_time.gd`](code/shader_time.gd).
   Проверка: `print(Game.sim_seconds())` растёт при ×1, стоит на паузе, растёт втрое быстрее на ×3.
3. **`prompts/CONVENTIONS.md`:** добавить в жёсткие правила строку
   `Встроенный TIME в шейдерах ЗАПРЕЩЁН — только global uniform sim_time (см. research/05).`
4. **Сцена `main.tscn`:** добавить `WeatherLayer` (`CanvasLayer`, `layer = 25`) между `PanelLayer` и `BannerLayer`.
5. **Сцена `world.tscn`:** пересобрать слои:
   ```
   WorldViewport
   ├── World       (Node2D, layer 0)  ← тайлмапы, агенты, постройки, существа, Parallax2D
   ├── FogLayer    (CanvasLayer 1)    ← DepthFog
   ├── RainLayer   (CanvasLayer 5)    ← Rain
   ├── FxLayer     (Node2D в World)   ← пул GPUParticles2D, группа "fx"
   └── WaterLayer  (CanvasLayer 10)   ← WaterView
   ```
   Все CanvasLayer: `follow_viewport_enabled = false` (дефолт). ColorRect'ы: Full Rect, 640×360.
6. Удалить мировой `ColorRect` воды этапа 02.

## 1. Вода (п.3 промпта, 2–3 дня — главная работа этапа)

Файлы: [`code/water.gdshader`](code/water.gdshader) → `assets/shaders/water.gdshader`, [`code/water_view.gd`](code/water_view.gd) → `game/water_view.gd`.
Материал: `assets/shaders/water_material.tres`, значения — таблица в [01](01-water-shader.md) §7.

**Настраивать строго по одному эффекту:**
1. Только альфа-градиент (`u_refract_px = 0`, `u_reflect_alpha = 0`, `u_caustics = 0`, `u_foam_px = 0`). Проверить: кромка на нужной высоте, глубина темнеет.
2. Включить волну и пену. Проверить: кромка ползёт «лесенкой», не мерцает.
3. Включить рефракцию. Проверить: агент на −3 искажается, небо над водой НЕ затягивается вниз.
4. Включить отражение. Проверить: нет горизонтальных полос (защита `ruv.y < surf_uv_y`).
5. Включить рябь.

**Проверки после:**
- Debug-слайдер override уровня (этап 03) от −12 до +3: артефактов на границах нет.
- Пауза на подъёме в `HIGH`: всё замирает.
- Скорость ×3: волна быстрее.

Подробности и объяснение каждого решения — [01-water-shader.md](01-water-shader.md).

## 2. Глубинный туман (п.1, полдня)

[`code/depth_fog.gdshader`](code/depth_fog.gdshader) + `_update_fog_bounds()` из [`code/weather_view.gd`](code/weather_view.gd).
Проверка: панорама камеры вверх/вниз — туман не «плывёт».

## 3. Свет (п.2)

[`code/light_budget.gd`](code/light_budget.gd), [`code/sprite_lit.gdshader`](code/sprite_lit.gdshader).
1. Материал `sprite_lit` на тайлмапы Ground/Ladders и на спрайты агентов/построек.
2. `Balance.MAX_LIGHTS = 8` (константа уже в docs/00 §16 — добавить в `balance.gd`, если её нет).
3. Фонарь / горн / очаг регистрируют свой `PointLight2D` в `LightBudget`.
4. Декоративное свечение (окна, глаза существ) — **фейк-спрайты add-blend**, не Light2D.

Приёмка промпта: спавн 12 фонарей не роняет fps, дальние гаснут. Проверять с профилировщиком (§ниже).

## 4. Мокрые тайлы (п.5)

[`code/wet_tiles.gdshader`](code/wet_tiles.gdshader) материалом на `TileMapLayer` Ground.
Нужен `last_high_level` из sim — см. [03](03-wet-tiles-reflections.md) §1. Если поля нет, это **единственная** правка sim на этапе; отметить в отчёте.

## 5. Погода (п.6)

[`code/rain.gdshader`](code/rain.gdshader) (внутри вьюпорта), [`code/vignette.gdshader`](code/vignette.gdshader) (снаружи, WeatherLayer), [`code/weather_view.gd`](code/weather_view.gd).
Пул брызг: 4 × `GPUParticles2D`, группа `&"fx"`, `one_shot`, `amount = 24`, `explosiveness = 1.0`.
Пар от горна: 1 × `GPUParticles2D`, непрерывный, `amount = 12`, группа `&"fx"`.

**Обязательно:** все эмиттеры в группе `&"fx"`, пауза через `PROCESS_MODE_DISABLED` (не `speed_scale = 0` — issue #77916). Детали — [04](04-weather-particles-vignette.md) §4.

## 6. Параллакс (п.7)

3 × `Parallax2D` прямыми потомками `World` (НЕ на CanvasLayer). Значения — [02](02-light-fog-atmosphere.md) §3.

## 7. Атлас-скин UI (п.8)

`theme_builder.gd` (этап 12) → `USE_ATLAS = true`, перегенерировать `main_theme.tres`, проверить `_gallery.tscn`.
Если рисовать нечем — программные рамки в стиле (однотон + светлая кромка) + TODO художнику.
В 4.7 `AtlasTexture` тайлится в `TextureRect` — использовать.

## 8. Спрайты мира (п.9)

Если арта нет — улучшенные программные заглушки (силуэт + 2 тона + кромка) и TODO-список в `assets/sprites/README.md`.

## 9. Профилирование (п.10)

---

# Профилирование

## Три вкладки Debugger

| Вкладка | Что показывает | Когда смотреть |
|---|---|---|
| **Monitors** | FPS, память, число нод. Данные собираются автоматически — график виден задним числом | первое место, куда смотреть |
| **Profiler** | CPU-время скриптов и физики. **Рендеринг сюда не входит** | замер тика симуляции (≤2 мс по docs/00 §16) |
| **Visual Profiler** | рендеринг: draw calls, освещение. CPU-время рендера слева, GPU справа | «спавн 12 фонарей не роняет fps» |

**Visual Profiler покрывает 2D** — документация приводит в пример именно 2D-сцену с отбрасывающими тени источниками света. Две панели рядом позволяют отличить CPU-bound (много draw calls) от GPU-bound (много перекрашенных пикселей — наш риск с оверлеями и большими лайтами).

## Оверлей для замеров на живом железе

На Steam Deck и телефоне Debugger недоступен — нужен экранный счётчик. Промпт 18 п.10 требует «график времени тика в дебаг-панели» — этот оверлей туда и встраивается.

```gdscript
extends Label
# DebugLayer(100)/PerfHUD — СНАРУЖИ SubViewport, чтобы текст был читаем

var _accum: float = 0.0

func _process(delta: float) -> void:
	_accum += delta
	if _accum < 0.25:
		return
	_accum = 0.0
	text = "FPS %d | proc %.2fms | phys %.2fms\ndraw %d | prim %d | nodes %d\nvram %.1f MB" % [
		Performance.get_monitor(Performance.TIME_FPS),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
	]
```

Обновление раз в 0.25 с, а не каждый кадр: форматирование строки и запись в `Label` сами по себе стоят заметно на слабом Android и исказят замер.

**Точные константы `Performance.Monitor`** (подтверждены, 4.7):
- Время: `TIME_FPS`, `TIME_PROCESS`, `TIME_PHYSICS_PROCESS`, `TIME_NAVIGATION_PROCESS`.
- Рендер: `RENDER_TOTAL_OBJECTS_IN_FRAME`, `RENDER_TOTAL_PRIMITIVES_IN_FRAME`, `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`, `RENDER_VIDEO_MEM_USED`, `RENDER_TEXTURE_MEM_USED`, `RENDER_BUFFER_MEM_USED`.
- Прочее: `MEMORY_STATIC`, `OBJECT_NODE_COUNT`.

`TIME_PROCESS`/`TIME_PHYSICS_PROCESS` возвращают **секунды** — отсюда `* 1000.0`. `TIME_FPS` — это FPS окна, per-viewport монитора нет.

**Время сим-тика** — своей метрикой:
```gdscript
Performance.add_custom_monitor("tidebound/tick_ms", _get_tick_ms)
```
Она встанет в Monitors рядом со встроенными графиками. Это и есть «график времени тика» из промпта.

## Целевые пороги

| Метрика | Steam Deck | Redmi Note 11 | Источник |
|---|---|---|---|
| Кадр | ≤16.6 мс (60 fps) | ≤33.3 мс (30 fps) | docs/00 §16 |
| Тик симуляции | ≤2 мс | ≤2 мс | docs/00 §16 |
| `TIME_PROCESS` | — | ≤6 мс | ⚠️ оценка, не из документации |
| `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` | сотни, не тысячи | то же | ⚠️ оценка |

⚠️ Термотротлинг на телефонах съедает 20–30% через несколько минут игры — замерять не на первой минуте.

Если draw calls уползают за ~1500 — искать разбиение батчей: чаще всего его вызывают чередующиеся материалы, смена `z_index` и каждый отдельный `GPUParticles2D`.

## Порядок диагностики просадки

1. **Monitors → FPS**: когда именно просело (фаза, событие).
2. **Visual Profiler**: CPU-панель или GPU-панель?
   - GPU высоко → fillrate. Подозреваемые по убыванию: `PointLight2D` с большим `texture_scale`, оверлеи без `discard`, `shadow_enabled`.
   - CPU высоко → draw calls / батчинг.
3. **Profiler**: если и то и другое низко, а fps плохой — это симуляция, а не рендер. Смотреть `tidebound/tick_ms`.

**Главный ползунок качества — `shadow_enabled` у 2D-света.** Разница в кадре от него заметнее, чем от любого другого параметра. Сделать настройкой графики: включено на Deck, выключено на Android.

---

# Финальная приёмка этапа 18

Из промпта дословно + добавленное ресерчем:

- [ ] Лимит светов соблюдается автоматически (спавн 12 фонарей не роняет fps, дальние гаснут).
- [ ] Вода: кромка + искажение + пена видны; **на паузе шейдер останавливается**.
- [ ] `grep -rn "\bTIME\b" godot/assets/shaders/` — ни одного вхождения встроенного `TIME`.
- [ ] Скриншот-тест: кадр `LOW` с огнями и кадр `HIGH` со штормом — «продающие».
- [ ] Витрина UI в атласном скине; смена скина обратно на flat — одной константой.
- [ ] 60 fps на целевом железе, тик ≤2 мс, график времени тика в дебаг-панели.
- [ ] Headless-тесты этапов 01–17 всё ещё зелёные (этап 18 не трогает sim; если тронул — объяснить).
- [ ] Быстрый прогон чек-листа симптомов из [06](06-pixel-art-pitfalls.md) §12.
