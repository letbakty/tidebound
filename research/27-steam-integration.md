# 27 — Steam: интеграция, достижения, облако, Deck Verified, демо

**Для этапов:** 11 (Meta/SaveService — решения принимаются СЕЙЧАС), 00 (одна настройка, которую нельзя менять после релиза), 15 (экран Журнала), 16 (геймпад и Deck), 19 (релизная приёмка).
**Дата ресерча:** 2026-08-21. **Движок:** Godot 4.7.x stable.

**Почему это Группа 1.** Три решения из этого документа нельзя отложить:
1. `use_custom_user_dir` — включается **до первого релиза**, иначе сейвы игроков осиротеют (§3.1).
2. Достижения должны выводиться из `cycle_ended`/`run_ended`-отчётов — значит отчёт этапа 11 обязан содержать нужные поля (§2.3).
3. Шрифт ≥9 px на 1280×800 — иначе Deck Verified не пройти, а `FONT_S = 8` из промпта 12 это нарушает (§4.2).

---

## 1. Чем интегрироваться: GodotSteam

**Встроенной поддержки Steam в Godot 4.7 нет и не планируется.** Steamworks — проприетарный SDK, в ядро движка он попасть не может. Единственный живой вариант — **GodotSteam**.

| Что | Значение |
|---|---|
| Форма поставки | **GDExtension** (не пересборка движка!) |
| Совместимость | Godot **4.4+**, актуальные сборки заявляют 4.7.1 |
| Основа | GodotSteam 4.21 + Steamworks SDK 1.65 |
| Платформы | Windows 32/64, Linux 64/ARM64, macOS universal, Android ARM64 |
| Установка | распаковать zip в корень проекта |
| Дом | [godotsteam.com](https://godotsteam.com), исходники на [Codeberg](https://codeberg.org/godotsteam/godotsteam) |
| Лицензия | MIT (обёртка); Steamworks SDK — по соглашению Valve |

**Ключевой факт: GDExtension, а не модуль.** Это значит:
- **не надо пересобирать шаблоны экспорта** — совместимо с обычными официальными шаблонами;
- ⚠️ **но несовместимо с кастомным шаблоном из research/26 §5**, если тот собран без `GDExtension`-поддержки. Если пойдёте на уровень 2 оптимизации размера — GDExtension должен остаться включён;
- ⚠️ **не работает в Web-экспорте** без отдельной сборки под web (а Steam в браузере всё равно не нужен).

**Альтернативы, которые не берём:** `godot-steam-api` (samsface) — заброшенная ветка; ручной биндинг через GDNative — не существует в 4.x. GodotSteam — де-факто стандарт, других живых вариантов нет.

---

## 2. Архитектура: как не протащить Steam в `sim/`

### 2.1 Слой

docs/02 §1 запрещает `sim/` знать про что угодно снаружи. Steam — не исключение, и это не формальность: без этого правила headless-тесты перестанут запускаться (Steam API требует запущенного клиента).

```
┌─ UI ────────────────────────────────────────────────┐
└──────────▲──────────────────────┬───────────────────┘
     Events (сигналы)       Game.cmd_*
┌──────────┴──────────────────────▼───────────────────┐
│ АВТОЛОАДЫ                                           │
│  Game · Meta · SaveService · AudioService · Settings │
│  ┌──────────────────────────────────────────────┐   │
│  │ Platform (НОВЫЙ автолоад)                    │   │
│  │  слушает Events → выдаёт достижения          │   │
│  │  инкапсулирует ВСЕ вызовы Steam              │   │
│  │  без Steam работает как заглушка             │   │
│  └──────────────────────────────────────────────┘   │
└──────────▲──────────────────────┬───────────────────┘
┌──────────┴──────────────────────▼───────────────────┐
│ SIM CORE — про Steam не знает вообще                │
└─────────────────────────────────────────────────────┘
```

**`Platform` — единственное место в проекте, где встречается слово `Steam`.** Grep `Steam` по проекту должен давать совпадения ровно в одном файле. Это же правило делает возможными сборки для itch и Android, где Steam нет.

### 2.2 Скелет `autoload/platform.gd`

```gdscript
extends Node
## Единственная точка контакта со Steam. Регистрируется ПОСЛЕ Meta,
## но ДО Game (ему нужны Events, которые объявлены в Events).
## Без Steam (itch, Android, headless) работает как заглушка: все методы — no-op.

const APP_ID: int = 480              # ⚠️ 480 = Spacewar, тестовый. Заменить на свой.

var available: bool = false

func _ready() -> void:
	available = _try_init()
	if not available:
		return
	Events.run_ended.connect(_on_run_ended)
	Events.cycle_ended.connect(_on_cycle_ended)
	Events.unlock_gained.connect(_on_unlock_gained)
	Events.agent_died.connect(_on_agent_died)

func _try_init() -> bool:
	# GDExtension может отсутствовать в сборке — проверяем классом, а не preload'ом
	if not ClassDB.class_exists("Steam"):
		return false
	if OS.has_feature("headless") or OS.has_feature("web"):
		return false
	var res: Dictionary = Steam.steamInitEx(APP_ID, true)
	if int(res.get("status", 1)) != 0:
		push_warning("Steam недоступен: %s" % res.get("verbal", ""))
		return false
	return true

func _process(_d: float) -> void:
	if available:
		Steam.run_callbacks()        # ⚠️ обязательно каждый кадр, иначе колбэки не придут

func unlock(id: StringName) -> void:
	if not available:
		return
	Steam.setAchievement(String(id))
	Steam.storeStats()               # ⚠️ без storeStats достижение не улетит на сервер
```

**Технические моменты:**
- ⚠️ **`ClassDB.class_exists("Steam")`, а не `preload`/`Engine.has_singleton`.** GDExtension регистрирует классы; при её отсутствии `preload` сломает компиляцию всего файла, а проверка класса — нет. Это делает один и тот же код рабочим и в Steam-билде, и в itch-билде, и в headless-тестах.
- ⚠️ **`run_callbacks()` каждый кадр.** Забыть — и достижения «выдаются», но оверлей молчит, а `storeStats` не подтверждается. Самая частая ошибка интеграции.
- ⚠️ **`steamInitEx` возвращает словарь со `status`/`verbal`**, а не bool. Старые туториалы показывают `steamInit()` — сигнатура другая.
- ⚠️ **APP ID 480 (Spacewar) — только для отладки.** С ним достижения не существуют; вызовы проходят, но ничего не происходит. Свой App ID появляется после оплаты Steam Direct ($100) и заполнения страницы.

### 2.3 Достижения: выводить из отчётов, а не расставлять по коду

**Плохо:** `Platform.unlock("FIRST_RELIC")` разбросано по десяти системам. Тогда Steam протекает в UI и sim, а достижение нельзя проверить тестом.

**Хорошо:** достижения — **чистая функция от отчёта забега/цикла**.

```gdscript
## Таблица достижений: id -> предикат по отчёту.
## Чистые функции => покрываются headless-тестом БЕЗ Steam.
const RUN_ACHIEVEMENTS: Dictionary[String, Callable] = {
	"ACH_FIRST_SHIP":   func(r: Dictionary) -> bool: return r["outcome"] == "SHIP",
	"ACH_NO_DEATHS":    func(r: Dictionary) -> bool: return int(r["deaths"]) == 0 and r["outcome"] == "SHIP",
	"ACH_RELIC_HUNTER": func(r: Dictionary) -> bool: return int(r["relics"]) >= 3,
	"ACH_DRY_RUN":      func(r: Dictionary) -> bool: return int(r["drowned"]) == 0,
	"ACH_SCORE_500":    func(r: Dictionary) -> bool: return int(r["points"]) >= 500,
	"ACH_EARLY_BIRD":   func(r: Dictionary) -> bool: return r["outcome"] == "EARLY" and int(r["points"]) >= 300,
}

func _on_run_ended(report: Dictionary) -> void:
	for id: String in RUN_ACHIEVEMENTS:
		if (RUN_ACHIEVEMENTS[id] as Callable).call(report):
			unlock(id)
```

**Что из этого следует для этапа 11 — и это надо заложить сейчас:**

Отчёт `run_ended` обязан содержать (сверх того, что уже требует промпт 11):
```gdscript
{
	"outcome": "SHIP"|"WIPE"|"EARLY",
	"points": int, "breakdown": {...},
	"cycles": int,
	"alive": int, "deaths": int, "drowned": int,   # drowned отдельно от deaths
	"relics": int,
	"buildings_built": int, "buildings_lost": int,
	"produced": {item_id: int},                     # агрегат за забег
	"cards_picked": Array[String],
	"crises_survived": Array[int],
	"seed": int,
}
```
⚠️ **Ничего из этого не является «фичей ради Steam».** Всё это и так нужно экрану итогов (промпт 15 п.5) и soak-CSV (research/24 §6, research/30). Достижения просто читают тот же отчёт. **Если поле забыть — добавлять позже придётся в sim, в сейв и в миграцию сейвов.**

⚠️ **Достижения — не в `Meta`.** Соблазн хранить «выдано/не выдано» в профиле велик. Не надо: Steam сам это хранит, дублирование = рассинхрон. `Meta.unlocked` (разблокировки Журнала) и Steam-достижения — **разные сущности**, не смешивать.

**Тест без Steam** (обязателен, покрывает главный риск — «достижение никогда не выдаётся»):
```gdscript
# tests/test_achievements.gd
static func test_all_reachable(t: TestCtx) -> void:
	# soak-прогон 20 забегов (research/30) собирает отчёты
	var reports: Array[Dictionary] = _soak_reports(20)
	var fired: Dictionary[String, bool] = {}
	for r: Dictionary in reports:
		for id: String in Platform.RUN_ACHIEVEMENTS:
			if (Platform.RUN_ACHIEVEMENTS[id] as Callable).call(r):
				fired[id] = true
	for id: String in Platform.RUN_ACHIEVEMENTS:
		if not fired.has(id):
			print("WARN: достижение %s не выдалось ни в одном из 20 забегов" % id)
```
Это ловит и опечатки в ключах отчёта, и недостижимые условия — до отправки билда в Valve.

---

## 3. Steam Cloud

### 3.1 Решение, которое нельзя откладывать: `use_custom_user_dir`

По умолчанию Godot пишет `user://` сюда (док data_paths, 4.7):

| ОС | Без `use_custom_user_dir` | С ним |
|---|---|---|
| Windows | `%APPDATA%\Godot\app_userdata\[project_name]` | `%APPDATA%\[project_name]` |
| macOS | `~/Library/Application Support/Godot/app_userdata/[project_name]` | `~/Library/Application Support/[project_name]` |
| Linux | `~/.local/share/godot/app_userdata/[project_name]` | `~/.local/share/[project_name]` |

Плюс `application/config/custom_user_dir_name` задаёт имя папки (поддерживает вложенность через `/`).

**Почему это Группа 1:**
1. Дефолтный путь лежит **внутри общей папки Godot**, вместе с сейвами всех остальных Godot-игр на машине. Steam Auto-Cloud туда настроить можно, но правило получится вида «синкать `%APPDATA%\Godot\app_userdata\Tidebound\*`» — хрупко и странно выглядит для игрока.
2. ⚠️ **Смена настройки после релиза = потеря сейвов игроков.** Путь меняется, старые файлы остаются на месте, игра их не видит. Лечится только кодом миграции, который придётся тащить вечно.

**Решение: включить на этапе 00 (или, если этап 00 уже сделан, — немедленно, до первой раздачи билда).**
```
application/config/use_custom_user_dir = true
application/config/custom_user_dir_name = "Tidebound"
```

### 3.2 Auto-Cloud или Cloud API

| | Auto-Cloud | Cloud API (`ISteamRemoteStorage`) |
|---|---|---|
| Код | **ноль** | обёртка чтения/записи |
| Настройка | паттерны путей в партнёрке | в коде |
| Кросс-платформа | Root Overrides | вручную |
| Контроль конфликтов | диалог Steam | свой |

**Наш выбор — Auto-Cloud.** Два маленьких JSON-файла (`save_run.json`, `profile.json`), никакой сложной логики. Cloud API нужен, когда сейвов много или требуется своя логика слияния — у нас не тот случай.

**Настройка в партнёрке (Steamworks → Cloud → Auto-Cloud):**
- Root: `WinAppDataRoaming`, Path: `Tidebound`, Pattern: `*.json`
- Root Override для macOS: `MacAppSupport` → `Tidebound`
- Root Override для Linux: `LinuxXdgDataHome` → `Tidebound`
- OS в правиле — **«All OSes»** с оверрайдами, иначе кросс-платформенная синхронизация не заработает.

⚠️ **Известная проблема:** при запуске macOS-билда через кастомный compat-tool на Linux Steam не умеет разрешить `MacAppSupport` и пишет «out of sync» ([steam-for-linux#12612](https://github.com/ValveSoftware/steam-for-linux/issues/12612)). Нас это касается только если будем раздавать macOS-билд под Proton — не будем.

⚠️ **Квоты.** Cloud имеет лимит на число файлов и общий объём (настраивается в партнёрке). Наши два файла — не проблема. Но **не класть в `user://` логи и скриншоты**, если они попадают под паттерн `*.json`/`*` — иначе квота кончится.

### 3.3 Конфликт устройств

Игрок сыграл на Deck без сети, потом на ПК — Steam покажет диалог выбора. Чтобы выбор был осмысленным:

**В сейв обязательно писать метаданные для человекочитаемого сравнения:**
```gdscript
{
	"save_version": 1,
	"saved_at_unix": 1755000000,       # ⚠️ Time.get_unix_time_from_system() — в SaveService, НЕ в sim
	"cycle": 7, "points_estimate": 240,
	"device_hint": OS.get_name(),      # "Windows" / "Linux" — виден в диалоге не будет,
	                                   # но полезен в баг-репортах
}
```
⚠️ `Time.*` запрещён только в `sim/`. `SaveService` — автолоад, ему можно.

⚠️ **Steam сравнивает файлы по времени изменения**, а не по содержимому. Атомарная запись через `rename` (research/18 §4) сохраняет mtime корректно — специально ничего делать не надо, но **не «трогать» файл без изменений** (например, не переписывать профиль каждый кадр — debounce из research/18 §8 обязателен, иначе Cloud будет синхронизировать постоянно).

---

## 4. Steam Deck Verified

Официальные критерии (partner.steamgames.com/doc/steamdeck/compat) делятся на четыре категории. Ниже — только то, что реально касается нас, с цитатами.

### 4.1 Input

> «your game must support Steam Deck's physical controls»; «The default controller configuration must provide users with the ability to access all content»

- ✅ Промпт 16 п.2 уже требует полной проходимости геймпадом. **Приёмка «вся игра проходима только геймпадом» — это и есть Deck Verified Input.**
- ⚠️ **Глифы:** *«On-screen glyphs must match the inputs being used… Mouse and keyboard glyphs should not be shown if they are not the active input»*. Наш детектор активного устройства (research/20 §5) это закрывает — но должен различать **Deck-глифы**, а не только «геймпад вообще». Valve рекомендует SteamInput API именно ради автоматического подбора глифов.
- ⚠️ **Ввод текста:** *«a Steamworks API for text entry»* либо собственная экранная клавиатура. У нас есть **поле ввода сида** (промпт 15 п.2)! Значит нужно: либо `Steam.showGamepadTextInput(...)` через `Platform`, либо (проще) **сделать поле сида необязательным и полностью доступным без клавиатуры** — например, кнопка «случайный сид» + пошаговый выбор цифр D-pad'ом. **Записать в промпт 15 как требование.**

### 4.2 Display — здесь у нас конфликт с промптом 12

> «smallest on-screen font character should never fall below **9 pixels in height at 1280×800**»; рекомендация — **минимум 12 px**.

⚠️ **`FONT_S = 8` из промпта 12 §1 это нарушает.** Deck — 1280×800; при базовом разрешении UI 1280×720 и `stretch aspect = expand` горизонтальный масштаб = 1.0, то есть 8-пиксельный шрифт останется 8 физическими пикселями. **Это прямой отказ в Verified.**

**Три варианта (выбрать на этапе 12, не на 19):**

| Вариант | Как | Оценка |
|---|---|---|
| **A. Поднять `FONT_S` до 12** | токены: `FONT_S=12, FONT_M=16, FONT_TITLE=24` | ✅ проще всего; требует шрифт с родным размером 12 (Ark Pixel — ровно 12, см. research/28) |
| B. Feature-override на Deck | `content_scale_factor` ×1.5 при `OS.has_feature("linuxbsd")` + детект Deck | ⚠️ Deck не даёт надёжного feature-тега; детект по `OS.get_processor_name()`/`SteamUtils.isSteamRunningOnSteamDeck()` |
| C. Не использовать `FONT_S` для игрового текста | оставить 8 px только для дебага | хрупко: кто-нибудь применит |

**Рекомендация: A + B.** Базовый минимум 12 px, плюс `Steam.isSteamRunningOnSteamDeck()` (через `Platform`) поднимает `content_scale_factor` до 1.25 — тогда мелкий текст будет 15 px, а требование «читаемо с 30 см» выполняется с запасом.

> «the game must run at a resolution supported by Steam Deck», предпочтительно **1280×800**

⚠️ **Наше базовое — 1280×720 (16:9), Deck — 1280×800 (16:10).** `stretch aspect = expand` это переживает (research/10 §1) — UI просто получит на 80 px больше по высоте. **Но проверить руками:** HUD с якорями «низ» и safe area не должен разъехаться. Добавить 1280×800 в список тестовых разрешений этапа 19 (сейчас там 800×600 / 1280×720 / 1920×1080 / 3840×2160).

### 4.3 Seamlessness

> «the app must not present the user with information that the Deck/Machine software… or hardware… is unsupported»

- Ни одного диалога «требуется мышь», «неподдерживаемое разрешение», «установите драйвер».
- **Лаунчера у нас нет — и не заводить.** Это одна из самых частых причин отказа у инди.
- ⚠️ **Дефолтные настройки должны работать на Deck без правки.** Значит `Settings` при первом запуске обязан давать играбельный результат на 1280×800: `ui_scale = 1.0`, зум мира по умолчанию, vsync on, `max_fps = 60` (research/26 §6.2).

### 4.4 System Support (Proton)

Игра идёт через Proton. Godot-игры под Proton работают штатно; риски — не в движке, а в:
- ⚠️ **GodotSteam под Proton:** Windows-билд + Windows-версия GodotSteam под Proton работают (Steam API проксируется). **Нативный Linux-билд с Linux-версией GodotSteam надёжнее** и даёт лучшую производительность на Deck. У нас Linux-пресет и так есть (промпт 16 п.4) — **делать нативный Linux-билд основным для Deck.**
- ⚠️ **Пути `user://` под Proton** превращаются в путь внутри префикса. Auto-Cloud с `LinuxXdgDataHome` для нативного билда и `WinAppDataRoaming` для Proton-билда — разные места. **Ещё один аргумент за нативный Linux-билд.**

**Целевая производительность (ориентир 2026):** для 2D-тайтлов Valve ориентируется на **30 FPS при 1280×720** как минимум для Verified-семейства. Наш бюджет (60 fps, тик ≤2 мс) с огромным запасом.

---

## 5. Что нужно от билда для страницы и демо

### 5.1 Страница магазина
- Steam Direct: **$100 за App ID** (возвращаются после $1000 выручки), заполнение налоговой информации, ~30 дней от создания страницы до релиза.
- Ассеты: капсулы (главная 616×353, малая 462×174, вертикальная 374×448, header 460×215, библиотечные 600×900 и 1920×620), скриншоты 1920×1080, трейлер.
- ⚠️ **Скриншоты — 1920×1080, а мир у нас 640×360.** При апскейле ×3 = 1920×1080 ровно. **Готовить скриншоты из билда с `stretch_shrink=2` в окне 1920×1080** — тогда пиксель целый и картинка «продающая» (это же требование приёмки этапа 18 п.«скриншот-тест»).
- Билд для ревью Valve: обычный релизный, достаточно рабочего запуска.

### 5.2 Демо: отдельный App ID + feature-флаги

Valve: демо — **отдельное приложение со своим App ID**, привязанное к основному; может иметь собственную страницу.

**Как собрать демо из одного проекта без второй ветки — механизм Godot: custom feature tags.**

Док feature_tags (4.7):
- кастомные теги задаются **в пресете экспорта**;
- ⚠️ *«Custom feature tags are only used when running the exported project… They're unavailable when testing from the editor»*;
- настройки проекта переопределяются суффиксом: `application/config/version.demo`;
- ⚠️ читать переопределённые настройки надо через `ProjectSettings.get_setting_with_override(...)`, обычный `get_setting` оверрайд не увидит.

```gdscript
## Единственная точка проверки — как и со Steam.
class_name Build
static func is_demo() -> bool:
	return OS.has_feature("demo")

static func max_cycles() -> int:
	return 4 if is_demo() else Balance.CYCLES_PER_RUN
```

Пресеты: `Windows Desktop`, `Windows Desktop (Demo)` — второй с custom feature tag `demo`, своим `APP_ID` (через `.demo`-оверрайд настройки) и своим exclude-фильтром.

**Что режет демо (решение дизайнерское, но техника одна):**
- лимит циклов (4 из 12) → `Build.max_cycles()`;
- часть разблокировок Журнала недоступна → фильтр в `Meta`;
- экран «спасибо, вишлист» вместо `RunSummary` → ветка в роутере.

⚠️ **Профиль демо и полной версии — разные файлы.** `custom_user_dir_name.demo = "Tidebound Demo"`. Иначе покупка полной версии подхватит демо-профиль (или наоборот), и это баг, который всплывёт в отзывах.

⚠️ **Достижения в демо Valve не разрешает** (у демо нет своих достижений). `Platform.unlock()` при `Build.is_demo()` — no-op. Одна строка, но забыть легко.

---

## 6. Что заложить на каких этапах (сводка)

| Этап | Действие | Цена сейчас | Цена потом |
|---|---|---|---|
| **00** | `use_custom_user_dir = true`, `custom_user_dir_name = "Tidebound"` | 2 минуты | миграция сейвов навсегда |
| **11** | расширить `run_ended.report` полями §2.3 | 20 строк | правка sim + сейва + миграции |
| **11** | `saved_at_unix` в сейве | 1 строка | нечитаемые конфликты Cloud |
| **12** | `FONT_S = 12` (не 8) | смена константы | переверстка UI |
| **15** | ввод сида проходим без клавиатуры | продумать при вёрстке | отказ Deck Verified |
| **16** | нативный Linux-пресет как основной для Deck | уже в промпте | — |
| **после 16** | автолоад `Platform` + GodotSteam | день | — |
| **19** | 1280×800 в списке тестовых разрешений | строка в чек-листе | отказ Deck Verified |

---

## 7. Чек-лист релиза в Steam

**Интеграция:**
- [ ] Grep `Steam` по проекту даёт совпадения только в `autoload/platform.gd`.
- [ ] Без GDExtension (itch/Android/headless) игра запускается и работает — все методы `Platform` no-op.
- [ ] `Steam.run_callbacks()` вызывается каждый кадр; оверлей открывается по Shift+Tab.
- [ ] `steam_appid.txt` (для отладки) **исключён** из релизного экспорта.
- [ ] Каждое достижение выдалось хотя бы раз в soak-прогоне 20 забегов.
- [ ] В демо-сборке `Platform.unlock` — no-op.

**Cloud:**
- [ ] `use_custom_user_dir` включён; путь проверен на всех трёх ОС.
- [ ] Auto-Cloud настроен с Root Overrides, «All OSes».
- [ ] Тест конфликта: сыграть на двух машинах офлайн, включить сеть, убедиться, что диалог осмысленный и выбор работает.
- [ ] В `user://` нет ничего, кроме двух JSON (нет логов, скриншотов, кэшей).

**Deck:**
- [ ] Полная проходимость геймпадом, включая ввод сида.
- [ ] Минимальный шрифт ≥12 px на 1280×800.
- [ ] Глифы соответствуют активному устройству, клавиатурные не показываются на геймпаде.
- [ ] Нет лаунчера, нет диалогов «неподдерживаемая система».
- [ ] Дефолтные настройки играбельны на Deck без правки.
- [ ] Нативный Linux-билд, а не только Proton.
- [ ] 30+ FPS при 1280×800 в худшем кадре (12-й цикл, шторм, все огни).

**Демо:**
- [ ] Отдельный App ID; сборка отличается только feature-тегом.
- [ ] Отдельная папка профиля.
- [ ] Лимит демо реализован через `Build.is_demo()`, а не через отдельную ветку git.

---

## Источники

- [GodotSteam](https://godotsteam.com) · [исходники (Codeberg)](https://codeberg.org/godotsteam/godotsteam) · [GDExtension в Asset Library](https://godotengine.org/asset-library/asset/2445) — совместимость с 4.4+/4.7.1, платформы, установка
- [Steam Deck Verified — критерии совместимости (Valve)](https://partner.steamgames.com/doc/steamdeck/compat) — цитаты по Input/Display/Seamlessness/System Support, 9 px при 1280×800
- [Steam Cloud (Steamworks)](https://partner.steamgames.com/doc/features/cloud) — Auto-Cloud, Root Overrides, квоты
- [Godot 4.7 — File paths in Godot projects](https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html) — точные пути `user://` с `use_custom_user_dir` и без
- [Godot 4.7 — Feature tags](https://docs.godotengine.org/en/stable/tutorials/export/feature_tags.html) — кастомные теги в пресетах, `.suffix`-оверрайды, `get_setting_with_override`
- [steam-for-linux#12612](https://github.com/ValveSoftware/steam-for-linux/issues/12612) — `MacAppSupport` не разрешается под compat-tool
- [Steam Deck Verified: типовые причины отказа у малых команд (2026)](https://gamineai.com/blog/steam-deck-verified-review-2026-submission-fails-small-team-builds) — лаунчеры, клавиатурные меню, нечитаемый UI
- [Valve о требованиях Verified для Steam Machine/Frame, GDC 2026](https://hothardware.com/news/valve-reveals-steam-machine-verified-badge-requirements) — ориентир 30 FPS / 1280×720 для 2D
