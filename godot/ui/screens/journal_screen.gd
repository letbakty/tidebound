class_name JournalScreen
extends ScreenBase
## Журнал: разблокировки, история забегов, павшие (docs/03 §3.5).
##
## Пустые состояния обязательны: до первого забега все три вкладки пусты,
## и это должно выглядеть осмысленно, а не сломанно.

const CARD_W: float = 190.0

var _tabs: TabContainer = null
var _points: Label = null
var _grid: GridContainer = null
var _history: VBoxContainer = null
var _fallen: VBoxContainer = null
var _stats: Label = null
var _confirm: ConfirmDialog = null
var _pending_unlock: String = ""

func _ready() -> void:
	super()
	set_title("JOURNAL_TITLE")
	_build_journal()

func _build_journal() -> void:
	_points = Label.new()
	_points.theme_type_variation = &"LabelTitle"
	_points.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	content.add_child(_points)

	_tabs = TabContainer.new()
	_tabs.name = "Tabs"
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_tabs)

	var unlocks: ScrollContainer = ScrollContainer.new()
	unlocks.name = "Unlocks"
	unlocks.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(unlocks)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unlocks.add_child(_grid)

	var history_tab: ScrollContainer = ScrollContainer.new()
	history_tab.name = "History"
	history_tab.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(history_tab)
	var history_box: VBoxContainer = VBoxContainer.new()
	history_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_tab.add_child(history_box)
	_stats = Label.new()
	_stats.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	UILayout.wrap(_stats, 520.0)
	history_box.add_child(_stats)
	_history = VBoxContainer.new()
	_history.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_box.add_child(_history)

	var fallen_tab: ScrollContainer = ScrollContainer.new()
	fallen_tab.name = "Fallen"
	fallen_tab.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(fallen_tab)
	_fallen = VBoxContainer.new()
	_fallen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fallen_tab.add_child(_fallen)

	_confirm = ConfirmDialog.new()
	_confirm.name = "Confirm"
	add_child(_confirm)
	_confirm.confirmed.connect(_on_buy_confirmed)

	resized.connect(_relayout)

func on_enter(_args: Dictionary = {}) -> void:
	_refresh()
	_relayout()

## Просмотренное перестаёт светиться рамкой при выходе из Журнала.
func on_exit() -> void:
	Meta.mark_unlocks_seen()

## Колонки считаем от ширины — дешевле, чем два лейаута (research/22 §5).
func _relayout() -> void:
	if _grid != null:
		_grid.columns = clampi(int(size.x / CARD_W), 2, 4)

func _refresh() -> void:
	_points.text = tr("JOURNAL_POINTS").format({"n": Meta.points_total})
	_refresh_tab_titles()
	_fill_unlocks()
	_fill_history()
	_fill_fallen()

func _refresh_tab_titles() -> void:
	_tabs.set_tab_title(0, tr("JOURNAL_TAB_UNLOCKS"))
	_tabs.set_tab_title(1, tr("JOURNAL_TAB_HISTORY"))
	_tabs.set_tab_title(2, tr("JOURNAL_TAB_FALLEN"))

func _fill_unlocks() -> void:
	for c: Node in _grid.get_children():
		c.queue_free()
	for id: String in DB.unlock_ids():
		_grid.add_child(_unlock_card(id))

## Три состояния карточки: куплена, доступна, дорого (docs/03 §3.5).
func _unlock_card(id: String) -> Control:
	var def: UnlockDef = DB.unlock(id)
	var card: PanelContainer = PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	card.custom_minimum_size = Vector2(CARD_W - float(UITokens.SPACE_3), 0.0)
	var bought: bool = Meta.has_unlock(id)
	if Meta.is_unlock_new(id):
		# Новое подсвечено рамкой до первого просмотра.
		card.add_theme_stylebox_override("panel", UIThemeFactory.flat(
			UITokens.RAISE, UITokens.ACCENT, UITokens.BORDER_FOCUS, UITokens.SPACE_3))
	var box: VBoxContainer = VBoxContainer.new()
	card.add_child(box)
	var title: Label = Label.new()
	UILayout.wrap(title, CARD_W - 40.0)
	title.text = def.display_key
	box.add_child(title)
	var desc: Label = Label.new()
	desc.theme_type_variation = &"LabelSmall"
	UILayout.wrap(desc, CARD_W - 40.0)
	desc.text = def.desc_key
	box.add_child(desc)
	var buy: PixelButton = PixelButton.new()
	if bought:
		buy.setup("JOURNAL_BOUGHT", PixelButton.Variant.GHOST)
		buy.disabled = true
	else:
		buy.text = tr("JOURNAL_BUY").format({"n": def.cost})
		buy.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		buy.variant = PixelButton.Variant.PRIMARY if Meta.points_total >= def.cost \
			else PixelButton.Variant.NORMAL
		# Не хватает очков — карточка видна, но неактивна с ценой (docs/03 §8).
		buy.disabled = Meta.points_total < def.cost
		buy.pressed.connect(func() -> void: _ask_buy(id))
	box.add_child(buy)
	return card

func _ask_buy(id: String) -> void:
	var def: UnlockDef = DB.unlock(id)
	_pending_unlock = id
	_confirm.setup("JOURNAL_BUY_TITLE", def.desc_key,
		tr("JOURNAL_BUY").format({"n": def.cost}), false, "")
	_confirm.open()

func _on_buy_confirmed() -> void:
	if _pending_unlock.is_empty():
		return
	Meta.buy_unlock(_pending_unlock)
	_pending_unlock = ""
	_refresh()

func _fill_history() -> void:
	var s: Dictionary = Meta.stats()
	_stats.text = tr("JOURNAL_STATS").format({
		"runs": int(s["runs_played"]), "wins": int(s["runs_won"]),
		"cycles": int(s["cycles_total"]), "lost": int(s["agents_lost"]),
		"best": int(s["best_score"]), "relics": int(s["relics_total"])})
	for c: Node in _history.get_children():
		c.queue_free()
	if Meta.history.is_empty():
		_history.add_child(_empty("JOURNAL_EMPTY_HISTORY"))
		return
	for i: int in Meta.history.size():
		var run: Dictionary = Meta.history[Meta.history.size() - 1 - i]
		var row: Label = Label.new()
		row.theme_type_variation = &"LabelSmall"
		row.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		row.text = tr("JOURNAL_RUN_ROW").format({
			"n": int(run["n"]),
			"end": tr(RunSummary._outcome_key(int(run["end"]))),
			"cycles": int(run["cycles"]), "score": int(run["score"])})
		_history.add_child(row)

func _fill_fallen() -> void:
	for c: Node in _fallen.get_children():
		c.queue_free()
	var any: bool = false
	for run: Dictionary in Meta.history:
		for d: Variant in run.get("deaths", []) as Array:
			any = true
			var death: Dictionary = d as Dictionary
			var row: Label = Label.new()
			row.theme_type_variation = &"LabelSmall"
			row.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			UILayout.wrap(row, 520.0)
			row.text = tr("RUN_EPITAPH").format({
				"name": str(death.get("name", "?")),
				"cause": tr("CAUSE_%s" % str(death.get("cause", "")).to_upper()),
				"bio": tr(str(death.get("bio", "")))})
			_fallen.add_child(row)
	if not any:
		_fallen.add_child(_empty("JOURNAL_EMPTY_FALLEN"))

## Пустое состояние: осмысленная строка вместо пустоты (docs/03 §3.5).
func _empty(key: String) -> Label:
	var label: Label = Label.new()
	label.theme_type_variation = &"LabelSmall"
	UILayout.wrap(label, 520.0)
	label.text = key
	return label

func _refresh_texts() -> void:
	super()
	if _tabs == null:
		return
	_refresh_tab_titles()
	# Цены, статистика и эпитафии собраны в коде — их надо пересобрать целиком.
	if visible:
		_refresh()
