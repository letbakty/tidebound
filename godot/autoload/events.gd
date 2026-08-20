extends Node
## Шина сигналов. ВСЕ сигналы объявляются здесь и только здесь — это контракт
## между слоями (docs/02 §3.2). Логики в этом файле не бывает никогда.
##
## Список объявлен ЦЕЛИКОМ сразу, включая ещё не используемые сигналы: следующие
## этапы подписываются на готовые имена и сигнатуры, а не правят этот файл.
##
## ⚠️ Обработчик с несовместимой сигнатурой просто не вызывается, а warning
## виден только в debug-сборке (docs/02 §10). Типизируй параметры обработчиков
## ровно так же, как здесь.

# --- От симуляции (эмитит ТОЛЬКО Game после world.tick()) -----------------
signal sim_ticked(tick: int)
signal phase_changed(phase: int, cycle: int)
signal water_level_changed(level: float)          # раз в 3 тика достаточно
signal cycle_started(cycle: int)
signal cycle_ended(report: Dictionary)
signal run_started(seed_value: int)
signal run_ended(report: Dictionary)
signal agent_spawned(id: int)
signal agent_updated(id: int)                     # смена состояния/яруса, не каждый тик
signal agent_died(id: int, cause: String)
signal agent_drowning(id: int)
signal building_placed(id: int)
signal building_state_changed(id: int)            # затоплено/повреждено/починено
signal building_removed(id: int)
signal deposit_changed(id: int)
signal storage_changed(id: int)
signal resources_changed(totals: Dictionary)      # {item_id: int} агрегат
signal crisis_announced(type: int, cycle: int)
signal crisis_started(type: int)
signal crisis_ended(type: int)
signal creature_spawned(id: int)
signal creature_left(id: int)
signal ship_arrived()                             # судно прибыло (начало HIGH последнего цикла)
signal draft_ready(card_ids: Array[String])
signal card_picked(card_id: String)
signal beacon_moved(cell: Vector2i)
signal policy_changed(policy: int, value: int)
signal recall_issued(hard: bool)
signal unlock_gained(unlock_id: String)

# --- От UI/оркестрации (не из sim) ----------------------------------------
signal speed_changed(mult: int)                   # 0 = пауза
signal ui_panel_opened(panel_name: String)
signal ui_panel_closed(panel_name: String)
