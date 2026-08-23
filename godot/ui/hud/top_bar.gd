class_name TopBar
extends PanelContainer
## Верхняя строка HUD: пауза и скорости, номер цикла, ресурсы с трендом, агенты.
## Все данные — из событий; собственный кэш вместо чтения sim (research/21 §1).

signal agent_focus_requested(agent_id: int)
signal agent_card_requested(agent_id: int)
## Кнопка «Политики». Панелями владеет Main, HUD о PanelHost не знает —
## поэтому наружу уходит сигнал, а не вызов (docs/02 §3.3).
signal policies_requested()

## Четыре ресурса первой линии (docs/01 §2). driftwood считаем СУХОЙ:
## мокрое полено в очаг не пойдёт, и показывать его как топливо — обман.
const SHOWN_ITEMS: Array[String] = ["rations", "freshwater", "driftwood", "part"]
const DRY_ITEMS: Array[String] = ["driftwood"]
## Больше восьми агентов — чипы сжимаются в точки-статусы (docs/01 §2).
const COMPACT_FROM: int = 8

var _totals: Dictionary[String, int] = {}
var _totals_prev_cycle: Dictionary[String, int] = {}
## Сухие остатки отдельным кэшем: чип топлива показывает СУХОЙ плавник, и
## тренд обязан сравнивать то же число, а не общее (аудит B2.10).
var _dry: Dictionary[String, int] = {}
var _dry_prev_cycle: Dictionary[String, int] = {}
var _chips: Dictionary[String, ResourceChip] = {}
var _agents: Dictionary[int, AgentChip] = {}

var _speed_buttons: Dictionary[int, Button] = {}
var _cycle_label: Label = null
var _agent_row: HBoxContainer = null

func _ready() -> void:
	theme_type_variation = &"PanelHud"
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	Events.run_started.connect(_on_run_started)
	Events.resources_changed.connect(_on_resources)
	Events.cycle_started.connect(_on_cycle_started)
	Events.phase_changed.connect(_on_phase_changed)
	Events.speed_changed.connect(_on_speed_changed)
	Events.agent_spawned.connect(_on_agent_spawned)
	Events.agent_updated.connect(_on_agent_updated)
	Events.agent_died.connect(_on_agent_died)

func _build() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Row"
	add_child(row)

	for m: int in 4:
		var b: PixelButton = PixelButton.new()
		b.name = "Speed%d" % m
		b.setup("HUD_PAUSE" if m == 0 else "HUD_SPEED_%d" % m,
			PixelButton.Variant.GHOST)
		b.tooltip_text = "HUD_SPEED_TIP"
		var mult: int = m
		b.pressed.connect(func() -> void: Game.cmd_set_speed(mult))
		row.add_child(b)
		_speed_buttons[m] = b

	# ⚠️ Единственный постоянный рычаг игры (шесть политик) до этого открывался
	# только клавишей P и свайпом от правого края — на экране входа не было
	# вовсе. Игрок, не нашедший панель, смотрит на скринсейвер. Кнопка стоит
	# ЗДЕСЬ, среди постоянных команд, а не в правом низу: там мёртвая зона
	# «Отзыва» (docs/01 §2). Подпись словом, не иконкой.
	var policies: PixelButton = PixelButton.new()
	policies.name = "Policies"
	policies.setup("PANEL_POLICIES", PixelButton.Variant.GHOST)
	policies.tooltip_text = "POLICY_HINT"
	policies.pressed.connect(func() -> void: policies_requested.emit())
	row.add_child(policies)

	_cycle_label = Label.new()
	_cycle_label.name = "Cycle"
	_cycle_label.theme_type_variation = &"LabelNum"
	_cycle_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	row.add_child(_cycle_label)

	for item_id: String in SHOWN_ITEMS:
		var chip: ResourceChip = ResourceChip.new()
		chip.name = "Chip_%s" % item_id
		row.add_child(chip)
		chip.setup(item_id, 0, 0)
		_chips[item_id] = chip

	_agent_row = HBoxContainer.new()
	_agent_row.name = "Agents"
	_agent_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_agent_row)

	_refresh_cycle()

## Клавиши 1/2/3 — здесь, а не в отдельном обработчике: скорость живёт в HUD.
## _unhandled_input, чтобы цифры не срабатывали при фокусе в поле ввода.
##
## РЕШЕНИЕ: промпт называет Space клавишей паузы, но docs/00 §13 отдаёт Space
## Отзыву, а паузу — Esc. Приоритет у docs/00 (CONVENTIONS): пауза — кнопка ⏸
## в этой строке, Esc открывает окно паузы на этапе 15.
func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return                          # скрытый HUD не командует симом (B1.5)
	for m: int in [1, 2, 3]:
		if event.is_action_pressed("speed_%d" % m):
			Game.cmd_set_speed(m)
			get_viewport().set_input_as_handled()
			return

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh_cycle()

# --- События --------------------------------------------------------------

func _on_run_started(_seed_value: int) -> void:
	# Стартовый запас приходит без события — забираем срезом (docs/02 §3.3).
	_totals.clear()
	var start: Dictionary = Game.query_totals()
	for k: Variant in start:
		_totals[str(k)] = int(start[k])
	_totals_prev_cycle = _totals.duplicate()
	_pull_dry()
	_dry_prev_cycle = _dry.duplicate()
	for id: int in _agents:
		_agents[id].queue_free()
	_agents.clear()
	_refresh_chips()

func _on_resources(totals: Dictionary) -> void:
	_totals.clear()
	for k: Variant in totals:
		_totals[str(k)] = int(totals[k])
	_refresh_chips()

## duplicate() обязателен: словари ходят по ссылке, без копии «прошлое»
## всегда равно «настоящему» и стрелка тренда вечно показывает → (research/21 §9).
func _on_cycle_started(cycle: int) -> void:
	_totals_prev_cycle = _totals.duplicate()
	_pull_dry()
	_dry_prev_cycle = _dry.duplicate()
	_refresh_cycle()
	_refresh_chips()

func _on_phase_changed(_phase: int, _cycle: int) -> void:
	_refresh_cycle()

func _on_speed_changed(mult: int) -> void:
	for m: int in _speed_buttons:
		_speed_buttons[m].variant = PixelButton.Variant.PRIMARY if m == mult \
			else PixelButton.Variant.GHOST

func _on_agent_spawned(id: int) -> void:
	if _agents.has(id):
		return
	var chip: AgentChip = AgentChip.new()
	chip.name = "Agent%d" % id
	_agent_row.add_child(chip)
	chip.tapped.connect(func(aid: int) -> void: agent_focus_requested.emit(aid))
	chip.double_tapped.connect(func(aid: int) -> void: agent_card_requested.emit(aid))
	_agents[id] = chip
	_update_agent(id)
	_apply_compact()

func _on_agent_updated(id: int) -> void:
	_update_agent(id)

func _on_agent_died(id: int, _cause: String) -> void:
	if not _agents.has(id):
		return
	_agents[id].queue_free()
	_agents.erase(id)
	_apply_compact()

# --- Отрисовка состояния --------------------------------------------------

## Лёгкий срез вместо полного: чипу нужны имя, худшая потребность и «жив ли»,
## а query_agent ради этого копировал котомку на каждое обновление (аудит B3).
func _update_agent(id: int) -> void:
	if not _agents.has(id):
		return
	var a: Dictionary = Game.query_agent_look(id)
	if a.is_empty():
		return
	_agents[id].setup(id, str(a["name"]), float(a["worst_need"]), bool(a["dead"]))

func _apply_compact() -> void:
	var compact: bool = _agents.size() > COMPACT_FROM
	for id: int in _agents:
		_agents[id].set_compact(compact)

func _pull_dry() -> void:
	_dry.clear()
	var dry: Dictionary = Game.query_dry_totals()
	for k: Variant in dry:
		_dry[str(k)] = int(dry[k])

func _refresh_chips() -> void:
	_pull_dry()
	for item_id: String in SHOWN_ITEMS:
		_chips[item_id].setup(item_id, shown_count(item_id), trend(item_id))

## Что показывает чип: у сухих предметов — сухой остаток («мокрое полено в очаг
## не пойдёт»), у остальных — общий. Ноль показывается нулём (docs/03 §8).
func shown_count(item_id: String) -> int:
	if DRY_ITEMS.has(item_id):
		return int(_dry.get(item_id, 0))
	return int(_totals.get(item_id, 0))

## Стрелка тренда сравнивает ТО ЖЕ число, что показано: иначе подсохший за цикл
## плавник давал стрелку вниз при растущем топливе.
func trend(item_id: String) -> int:
	if DRY_ITEMS.has(item_id):
		return signi(int(_dry.get(item_id, 0)) - int(_dry_prev_cycle.get(item_id, 0)))
	return signi(int(_totals.get(item_id, 0)) - int(_totals_prev_cycle.get(item_id, 0)))

func _refresh_cycle() -> void:
	if _cycle_label == null:
		return
	var clock: Dictionary = Game.query_clock()
	var cycle: int = int(clock.get("cycle", 1))
	_cycle_label.text = tr("HUD_CYCLE_OF").format({
		"n": cycle, "total": Balance.CYCLES_PER_RUN})
