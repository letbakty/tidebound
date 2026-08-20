# Этап 00 — Каркас проекта Godot

**Модель:** Sonnet 5 достаточно (механический этап; главное — точно перенести настройки).
**Зависит от:** ничего. **Читать:** docs/02-architecture.md §2, §8, §9; docs/01-ui-spec.md §1.1.
**Результат:** пустой, но правильно настроенный проект: папки, автолоады-заглушки, гибридный вьюпорт, input map, i18n, git.
**Ресерч:** [research/10-project-setup-viewport-scaling.md](../research/10-project-setup-viewport-scaling.md) — точные ключи ProjectSettings, дерево главной сцены, Input Map из кода, i18n, headless. Дополнительно: [research/24](../research/24-testing-headless-hardening.md) §1–4 (раннер и `check()` вместо `assert`).
**Готовый код:** `research/code/run_all.gd` → `tests/run_all.gd`; `research/code/test_ctx.gd` → `tests/test_ctx.gd` — переноси, а не пиши с нуля (черновики под контракты docs/02, но не компилировались: сверь имена полей с тем, что реально сделали прошлые этапы).

## Задача
1. Создай проект Godot 4.7.x в `godot/` (рядом с docs/ и prompts/). Renderer: **Mobile**.
2. Структура папок — дословно из docs/02 §2 (пустые `.gitkeep` где нужно).
3. **Project Settings** — точные пути ключей и пояснения в [research/10](../research/10-project-setup-viewport-scaling.md) §2 (скопируй оттуда блок целиком). Сверх списка ниже обязательно: `physics/common/physics_jitter_fix = 0.0` (иначе движок подкручивает дельту и портит наш аккумулятор тика) и `input_devices/pointing/emulate_touch_from_mouse = true` (для отладки жестов на этапах 12/16). Ключевое:
   - `display/window/size/viewport_width = 1280`, `viewport_height = 720` (окно); мир получит своё разрешение через SubViewport.
   - `display/window/stretch/mode = canvas_items`, `aspect = expand`.
   - `rendering/textures/canvas_textures/default_texture_filter = Nearest`.
   - `debug/gdscript/warnings/untyped_declaration = 2` (Error); также `unsafe_method_access`, `unsafe_property_access` = Warn.
   - `physics/common/physics_ticks_per_second = 60` (не трогаем, физику не используем).
4. **Главная сцена** `game/main.tscn`:
   ```
   Main (Control, Full Rect)
   ├── WorldContainer (SubViewportContainer, Full Rect, stretch=true, stretch_shrink=2)
   │   └── WorldViewport (SubViewport, size 640x360, snap_2d_transforms_to_pixel=true,
   │       snap_2d_vertices_to_pixel=true)  ← сюда этап 02 положит world.tscn
   ├── HUDLayer (CanvasLayer, layer=10)     ← тема назначается явно (каскад рвётся на CanvasLayer)
   ├── PanelLayer (CanvasLayer, layer=20)
   ├── BannerLayer (CanvasLayer, layer=30)
   └── DebugLayer (CanvasLayer, layer=100)
   ```
   Скрипт `main.gd`: хранит ссылки на слои; `set_world_zoom(factor: int)`.
   ⚠️ **Решение из ресерча ([10](../research/10-project-setup-viewport-scaling.md) §1):** `stretch_shrink` держать константой **2**, а зум делать камерой (этап 02). Причина: 1280/3 = 426.67 — на shrink=3 контейнер не делится нацело и появляется полупиксельный шов. `set_world_zoom` на этом этапе — заглушка-прокси, на этапе 02 станет вызовом `CameraRig.set_zoom_step()`.
   ⚠️ При `stretch = true` размер SubViewport **переустанавливается контейнером автоматически** — задавать `size` в инспекторе бессмысленно.
5. **Автолоады** (порядок регистрации важен): `Events`, `Settings`, `Meta`, `SaveService`, `Game`, `AudioService`. Пока заглушки: Events — пустой (сигналы добавит этап 01), остальные — `extends Node` с комментарием этапа, который их наполнит. ⚠️ **Не давать автолоадам `class_name`** — имя синглтона и так глобально, `class_name Game` + автолоад `Game` даёт конфликт парсера ([research/10](../research/10-project-setup-viewport-scaling.md) §3).
6. **Input Map** — прописать одноразовым `EditorScript` (готовый скрипт с полной таблицей действий — в [research/10](../research/10-project-setup-viewport-scaling.md) §5), а не кликами в редакторе. ⚠️ **Обязательно `physical_keycode`, а не `keycode`** — иначе WASD не работает на кириллической раскладке. Не забыть ключ `deadzone` в словаре действия. Состав (из docs/00 §13): `pan_left/right/up/down` (WASD+стрелки), `recall` (Space), `policies` (P), `build_radial` (B), `beacon` (M), `speed_1/2/3` (1/2/3), `pause_menu` (Esc), `debug_panel` (F1), `overlay_marks` (F2), `overlay_flood` (F3), `overlay_jobs` (F4). Геймпад — по той же таблице.
7. **i18n:** `assets/i18n/strings.csv` (key,ru,en; первая строка-пример `APP_NAME,Отлив,Tidebound`), подключи в Project Settings → Localization.
8. `git init` в корне tidebound/ (если ещё нет), `.gitignore` для Godot (`.godot/`, `*.tmp`), первый коммит.
9. `tests/run_all.gd` + `tests/test_ctx.gd` — **перенеси готовые из `research/code/`**, не пиши с нуля. ⚠️ **`assert()` вырезается в release-сборках** — все проверки в тестах только через свой `check(cond, msg)` ([research/24](../research/24-testing-headless-hardening.md) §1). Раннер обязан пропускать ещё не существующие сьюты, иначе сломается до этапа 01. Проверка: `godot --headless --import --quit`, затем `godot --headless -s res://tests/run_all.gd`.

## Приёмка
- [ ] Проект открывается в 4.7.x без ошибок; главная сцена запускается (пустой экран).
- [ ] `stretch_shrink=2` даёт мир 640×360 в окне 1280×720; ресайз окна не ломает пропорции (expand).
- [ ] Headless-раннер выходит с кодом 0.
- [ ] Все автолоады зарегистрированы, input map полон.

## Не делать
Никакой игровой логики, UI-компонентов, тем, ассетов.
