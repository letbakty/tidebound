# Этап 10 — Планы вылазки (драфт карт)

**Модель:** Sonnet 5 достаточно.
**Зависит от:** 09. **Читать:** docs/00 §10; docs/02 §5.
**Результат:** драфт 1 из 3 на каждом Спаде; эффекты карт реально применяются на цикл.
**Ресерч:** [research/14-data-resources-tres.md](../research/14-data-resources-tres.md) — дефы карт и генерация `.tres`. Дополнительно: [research/25](../research/25-cross-engine-patterns.md) §2.4 (blackboard-модификаторы).

## Задача
1. `data/defs/card_def.gd` — `class_name CardDef extends Resource`: id, display_key, desc_key, rarity ("base"/"rare"), unlock_id, effects: Dictionary[String, float] с фикс-ключами: `low_plateau_add, low_time_mult, haul_speed_mult, bag_slots_add, recall_earlier_sec, drown_bonus_sec, gather_speed_mult, next_spring_add, cancel_visit, mark_relic`. Карта «Осторожно»: recall_earlier_sec=30, drown_bonus_sec=3, gather_speed_mult=0.8 (docs/00 §10).
2. `data/cards/*.tres` — 6 карт из docs/00 §10 дословно (3 base + 3 rare с unlock_id).
3. `sim/run_state.gd` — добавить (или создать, если ещё нет): `active_card: String`, `drafted_this_cycle: bool`, `unlocks: Array[String]` (на этом этапе — пустой список, наполняется ТЕСТОМ напрямую; этап 11 подключит Meta через параметр new_run); в начале EBB: собрать пул (base ×3 всегда; rare — если их unlock_id в unlocks; выбрать 3 без повторов сидированным RNG, при "u_draft_plus" в unlocks — 4), эмит `draft_ready(card_ids)` + автопауза (Game: сохранить текущую скорость, speed=0; возврат — `Game.resume_prev_speed()` после выбора).
4. `Game.cmd_pick_card(card_id)` → применение эффектов: low_plateau_add/low_time_mult → Tide/SimClock на этот цикл; haul/gather/bag/recall — модификаторы в AgentSystem/JobSystem (добавь единый `cycle_modifiers: Dictionary` в SimWorld, читаемый системами; сброс в конце цикла); cancel_visit → флаг в CrisisSystem; mark_relic → пометить случайный глубокий депозит гарантированной реликвией (событие для UI-метки). После выбора — снять паузу (вернуть прежнюю скорость).
5. Если игрок не выбрал за EBB (не должен случиться из-за автопаузы, но защита) — авто-выбор первой карты.
6. Дебаг-панель: секция «Карты» — показать текущий драфт, выбрать кнопкой (до UI этапа 15).

## Приёмка (tests/test_cards.gd)
- [ ] Драфт приходит каждый EBB; состав детерминирован сидом.
- [ ] «Глубокий заход»: плато LOW = −10 и LOW короче на 25% ровно на один цикл.
- [ ] «Тихая вода»: существа в цикл Прихода не спавнятся (тест кладёт "u_card_calm" в RunState.unlocks напрямую).
- [ ] «Осторожно»: время утопления всех агентов в цикле +3 с.
- [ ] «Находка»: помеченный депозит отдаёт реликвию первой же добычей.
- [ ] Модификаторы сбрасываются в конце цикла.

## Не делать
UI карт (этап 15), новые карты, баланс существующих.
