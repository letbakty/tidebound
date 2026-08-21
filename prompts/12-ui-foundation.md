# Этап 12 — UI-фундамент: токены, тема, компонентная библиотека

**Модель:** Opus 5 или Fable 5 (архитектура UI; от качества этого этапа зависит скорость всех следующих).
**Зависит от:** 00 (слои главной сцены). Может идти ПАРАЛЛЕЛЬНО этапам 04–11 (не трогает sim).
**Читать:** docs/01-ui-spec.md §1.2–1.3, §4, §6 — дословно; docs/02 §8.
**Ресерч:** [research/19-ui-theme-components.md](../research/19-ui-theme-components.md) — тема из кода, каскад и CanvasLayer, **настройки пиксель-шрифта**, правила компонента, радиал, витрина. Дополнительно: [research/20](../research/20-input-gestures-gamepad.md) §1–5 (порядок обработки ввода, мультитач, пинч вручную, long-press).
**Готовый код:** `research/code/input_service.gd` → `ui/input_service.gd` — переноси, а не пиши с нуля (черновики под контракты docs/02, но не компилировались: сверь имена полей с прошлыми этапами).

## Задача
0. **UI-kit готов и принят** — [../design/tidebound-ui-kit.dc.html](../design/tidebound-ui-kit.dc.html) (открывается в браузере, `support.js` должен лежать рядом). **Это источник правды по визуалу — бери значения оттуда, а не выводи из текста docs/01.**
   - **A** — токены: палитра из 16 цветов, шкала кеглей, отступы, таблица «элемент → dp → зазор».
   - **X** — раскладка атласа `512×512` с координатами блоков и таблица 9-slice (угол и кромка по каждой рамке).
   - **E** — атомы во всех состояниях: четыре варианта кнопки × пять состояний, чипы, ползунки политик.
   - **F** — шкала прилива в пяти состояниях (обычный отлив, низкая вода, сигнал, высокая вода, сизигия со штормом).
   - **I**, **J** — игровой экран на ПК 1280×720 и телефоне 390×844.
   - Шрифты выбраны и проверены на кириллицу: **Handjet** (основной), **Press Start 2P** (заголовки), JetBrains Mono (числа). ⚠️ `Pixelify Sans` не брать ни при каких условиях — в нём нет заглавных `О` и `П`.
   - Пять мест в ките помечены «уточнить» — данные для них перечислены в [../design/README.md](../design/README.md), раздел «Что осталось доопределить».
1. **Токены** `ui/theme/tokens.gd` — `class_name UITokens`, только const: палитра из docs/01 §4 (имена: `INK, PAPER, PANEL_BG, ACCENT, DANGER, SUCCESS, MUTED, WATER_COLD, WARM`), `SPACE_1..5 = 4/8/12/16/24`, `FONT_S/M/L/TITLE`, `BORDER_W`, `TOUCH_MIN = 48`.
2. **Шрифты:** ⚠️ настройки импорта, без которых текст мылит и «едет на полпикселя», — [research/19](../research/19-ui-theme-components.md) §4: помимо перечисленного ниже обязательны **`keep_rounding_remainders = false`** (issue 71046) и отключённое subpixel positioning. скачай/попроси у пользователя пиксель-шрифт с кириллицей (приоритет: monogram, Public Pixel — CC0; заголовки — Press Start 2P OFL). Файл(ы) в `assets/fonts/`. Импорт: Antialiasing=None, Hinting=None, Subpixel=Disabled, MSDF=off, Mipmaps=off. Если файла нет — используй системный моноширинный как ВРЕМЕННЫЙ (пометь TODO), не блокируйся.
3. **Сборщик темы** `ui/theme/theme_builder.gd` (`EditorScript`, запуск File → Run): генерирует `ui/theme/main_theme.tres` из токенов. Точный API темы из кода (частая галлюцинация — `set_type_variation`) и скелет билдера — [research/19](../research/19-ui-theme-components.md) §1–2. Состав:
   - Базовые типы: Panel, Button (normal/hover/pressed/disabled/focus StyleBoxFlat из токенов; focus — видимая рамка ACCENT), Label, HSlider, CheckBox, LineEdit, TooltipPanel/TooltipLabel.
   - Type variations (docs/01 §1.2): `PanelDark`, `PanelRaised`, `ButtonPrimary`, `ButtonDanger`, `ButtonGhost`, `LabelTitle`, `LabelSmall`, `LabelNum`, `CardPanel`, `TooltipPanel`.
   - Пока StyleBoxFlat (плоский стиль по палитре); переход на StyleBoxTexture с атласом — этап 18 (заложи в builder ветку `USE_ATLAS: bool = false`).
   - Тема прописывается в Project Settings → GUI → Theme → Custom И назначается на корни CanvasLayer-слоёв (каскад рвётся — docs/01 §1.2).
4. **Компоненты** `ui/components/` — сцены + скрипты, каждый: без игровой логики, `setup(...)` типизированный, сигналы наружу, реакция на `NOTIFICATION_THEME_CHANGED`:
   - `pixel_button.tscn` (Button c вариацией по export-полю), `pixel_panel.tscn` (заголовок tr-ключом, крестик, сигнал closed; свайп-вниз закрытие — принимает жест от InputService ниже),
   - `resource_chip.tscn` (иконка-заглушка 16×16, число LabelNum, стрелка тренда ▲▼→ по сигнатуре setup(item_id, count, trend: int)),
   - `policy_slider.tscn` (4 ступени, крупные насечки, подпись значения через callback-словарь описаний, сигнал value_picked(policy, v)),
   - `agent_chip.tscn` (квадрат 32, инициал/портрет-заглушка, нижняя полоска цветом худшей потребности, сигналы tapped/double_tapped),
   - `card_view.tscn` (CardPanel, название/описание tr, рамка-акцент для rare, сигнал picked),
   - `radial_menu.tscn` — СВОЯ реализация: до 6 слотов вокруг точки, слот = иконка+подпись; открытие в точке, выбор: тап по слоту ИЛИ drag-в-сторону+отпуск (tap+swipe одним жестом); закрытие тапом мимо; сигнал slot_picked(idx); геймпад: стик выбирает сектор;
   - `tooltip_view.tscn` (кастомный тултип через `_make_custom_tooltip` у компонентов; на таче показ по long-press на UI-элементе; PanelDark-подложка),
   - `toast.tscn` (иконка+текст+счётчик группировки, автоскрытие 5 с, сигнал tapped),
   - `banner_view.tscn` (широкая плашка события по центру-верху, автопауза-совместимая),
   - `confirm_dialog.tscn`.
5. **InputService** — **перенеси готовый `research/code/input_service.gd`**. Нода в Main, НЕ автолоад (почему — [research/19](../research/19-ui-theme-components.md) §7). ⚠️ `InputEventMagnifyGesture` покрывает не все платформы — пинч считается вручную по `index` касаний ([research/20](../research/20-input-gestures-gamepad.md) §2–3). Состав: распознавание жестов поверх мира: tap / long-press (0.5 с, с прогресс-индикатором у пальца — docs/01 ресерч) / drag / pinch (дистанция → сигнал zoom_step(+1/-1)) / двойной тап; edge-swipe справа. Эмитит СВОИ сигналы (`world_tapped(pos)`, `world_long_pressed(pos)`, `edge_swipe_right`...), никого не вызывает напрямую. Мышь мапится в те же сигналы (ПКМ-удержание = long-press и т.д.).
6. **Витрина** `ui/components/_gallery.tscn` — сцена со всеми компонентами во всех состояниях (запускается отдельно). Это «страница стилей»: правишь токены → перегенерил тему → смотришь витрину.

## Приёмка
- [ ] Витрина показывает все компоненты; фокус ходит клавиатурой; все подписи через tr().
- [ ] Смена значения в tokens.gd + перегенерация меняет вид ВСЕХ компонентов без правки сцен.
- [ ] Радиал работает мышью (удержание ПКМ) и одним жестом тапа-свайпа (эмуляция тача в редакторе).
- [ ] Ни один компонент не обращается к Game/Events/sim.

## Не делать
HUD и панели игры (13–15), атласный скин (18), звук кликов (17).
