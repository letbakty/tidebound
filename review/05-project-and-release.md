# 05 — Настройки проекта, сейвы, git, подготовка к релизу

Сверено с `project.godot`, `.gitignore`, `autoload/save_service.gd`, `autoload/meta.gd` и рекомендациями `research/10`, `research/26`, `research/27`.

---

## REL-01 🔴 `use_custom_user_dir` не включён — менять после релиза уже нельзя

**Где:** `project.godot`, секция `[application]`.

Сейчас настройка отсутствует, значит сейвы пишутся в общую папку движка:
```
Windows: %APPDATA%\Godot\app_userdata\Tidebound
macOS:   ~/Library/Application Support/Godot/app_userdata/Tidebound
Linux:   ~/.local/share/godot/app_userdata/Tidebound
```

**Почему это срочно.** Включение позже **осиротит сейвы всех игроков**: путь изменится, старые файлы останутся лежать, игра их не увидит. Лечится только кодом миграции, который придётся тащить вечно. Плюс правило Steam Auto-Cloud получается вида «синкать содержимое общей папки Godot» — хрупко и странно (`research/27 §3.1`).

**Что нужно:**
```
application/config/use_custom_user_dir=true
application/config/custom_user_dir_name="Tidebound"
```
Пока билд не раздавали — это две строки. После первой раздачи — постоянная головная боль.

---

## REL-02 🟠 Профиль молча обнуляется при смене версии

**Где:** `autoload/meta.gd` — `load_profile()`.

При несовпадении `version` функция возвращает `false`, оставляя поля дефолтными. Файл на диске не трогается — но первый же `mark_dirty()` (например, конец первого забега) перезапишет его нулевым профилем. Игрок теряет всю метапрогрессию без предупреждения и без резервной копии.

Для сейва забега аналогичная ситуация решена правильно: `SaveIO.read_json` уводит битый файл в карантин (`.corrupt.json`). Для профиля — нет.

**Что стоит сделать.** При отказе загрузки переименовывать `profile.json` в `profile.v{N}.bak`, как это уже делает `quarantine`.

---

## REL-03 🟠 Профиль не сохраняется при выходе из игры

**Где:** `autoload/save_service.gd` — `_notification` сохраняет только забег; `autoload/meta.gd` полагается на `_process`-дебаунс.

При `NOTIFICATION_WM_CLOSE_REQUEST` вызывается `save_run()`, затем сразу `get_tree().quit()`. `Meta._process` в этом кадре может уже не выполниться. Окно потери — одна покупка разблокировки или один итог забега.

⚠️ Не подтверждено: зависит от порядка `_notification` и `_process` в кадре. Но защита стоит одной строки — `Meta.save_profile()` рядом с `save_run()`.

Побочно: `NOTIFICATION_APPLICATION_PAUSED` (сворачивание на мобилке — единственный шанс сохраниться на Android) тоже не пишет профиль.

---

## REL-04 🟠 Выход во время драфта теряет драфт

**Где:** `autoload/game.gd:101` (`rebroadcast_state`).

`run_state.draft` и `drafted_this_cycle` **сохраняются** корректно. Но `rebroadcast_state` не эмитит `draft_ready` — значит после `Continue` панель драфта не появится, автопауза не встанет, и на границе Отлива сработает `auto_pick_if_needed`, взяв первую карту за игрока.

Это ровно тот краевой случай, который `research/24 §9` называет обязательным к проверке («выход во время драфта»).

**Что нужно:** в `rebroadcast_state` — `if not run_state.draft.is_empty() and not run_state.drafted_this_cycle: Events.draft_ready.emit(...)`.

Заодно проверить: `ship_arrived`, `crisis_announced` и `crisis_started` тоже не переэмитятся после загрузки. Для этапов 13/15 (шкала прилива с прогнозом, банеры) это значит пустой прогноз после `Continue`.

---

## REL-05 🟡 Сгенерированные `.translation` попадают в git

**Где:** `.gitignore` содержит `godot/*.translation`, но файлы лежат в `godot/assets/i18n/`.

```
$ git ls-files | grep translation
godot/assets/i18n/strings.en.translation
godot/assets/i18n/strings.ru.translation
```
Паттерн без `**` не рекурсивен. Файлы генерируются из `strings.csv` при импорте, значит в репозитории они — бинарный шум, который будет конфликтовать при каждой правке переводов.

**Что нужно:** `godot/**/*.translation` (или просто `*.translation`).

---

## REL-06 🟡 Не заданы настройки, которые research рекомендует зафиксировать до релиза

Отсутствуют в `project.godot`:

| Настройка | Зачем | Источник |
|---|---|---|
| `application/run/max_fps` | без ограничения GPU крутит меню на сотнях fps: батарея и шум на ноутбуке/Deck | research/26 §6.2 |
| `display/window/vsync/vsync_mode` | то же | research/26 §6.2 |
| `display/window/stretch/scale_mode` | дробный масштаб на 1366×768 — решение надо принять и записать | research/10 §1 |
| `physics/common/physics_ticks_per_second` | промпт 00 требовал зафиксировать явно (сейчас дефолт 60 — верно, но неявно) | prompts/00 |
| `rendering/anti_aliasing/quality/msaa_2d` | пиксель-арт + MSAA = мыло; дефолт верный, но лучше явно | research/26 §6.2 |
| `input_devices/pointing/android/enable_pan_and_scale_gestures` | понадобится этапу 16 | research/20 §3 |
| `application/config/version` | пригодится в баг-репортах и на страницах магазинов | — |

Ни одна не является дефектом сегодня — но `max_fps` и `use_custom_user_dir` дешевле поставить сейчас.

---

## REL-07 🟡 `print` в релизной сборке

**Где:** `game/main.gd` — три `print` на каждое событие фазы, конец цикла и драфт.

За забег это ~50 строк на цикл × 12 циклов, в консоли релизной сборки. `CONVENTIONS` запрещает `print` в `sim/` (соблюдено), но про `game/` молчит. Логика временная (TODO на этап 15), однако стоит гейтить `OS.is_debug_build()`, чтобы не забыть.

---

## REL-08 🟡 Автостарт забега в `main.gd` и автовыбор карты

**Где:** `game/main.gd` — `Game.cmd_new_run(DEV_SEED)` в `_ready`, `_on_draft_ready` берёт `card_ids[0]`.

Оба помечены `TODO(этап 15)` — это правильно. Отмечаю, чтобы не потерялось: пока автовыбор жив, **механика драфта фактически не играется**, а значит и не тестируется в ручных прогонах. Все эффекты карт проверяются только юнит-тестами.

---

## REL-09 🔵 Заготовки Steam / достижений отсутствуют — и это осознанно рано

`research/27 §2.3` рекомендует расширить `run_ended.report` полями (`drowned`, `alive`, `produced`, `cards_picked`, `buildings_built/lost`) **до** этапа 11, потому что позже это правка sim + сейва + миграции.

Сейчас в отчёте есть: `end`, `cycles`, `seed`, `score`, `raw_score`, `breakdown`, `early`, `deaths`, `relics`. Нет: `alive`, `drowned` отдельно от `deaths`, агрегата произведённого, списка карт.

Этап 11 завершён, так что это уже «позже». Но пока сейвов у игроков нет, расширение отчёта стоит нескольких строк — и закрывает и достижения (research/27), и баланс-CSV (research/30) разом.
