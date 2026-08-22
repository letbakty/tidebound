class_name DepositTooltip
extends Control
## Подсказка по депозиту: сколько осталось, восполняется ли, есть ли шанс
## реликвии (docs/03 §6). Не панель: не закрывает другие окна и живёт сама.

const LIFE_SEC: float = 4.0

var _tip: TooltipView = null
var _timer: Timer = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip = TooltipView.new()
	_tip.name = "Tip"
	_tip.visible = false
	add_child(_tip)
	_timer = Timer.new()
	_timer.name = "Life"
	_timer.one_shot = true
	_timer.timeout.connect(hide_tip)
	add_child(_timer)

func show_for(deposit_id: int, at: Vector2) -> void:
	var d: Dictionary = Game.query_deposit(deposit_id)
	if d.is_empty():
		return
	var lines: Array[String] = []
	lines.append(tr("DEPOSIT_%s" % str(d["kind"]).to_upper()))
	lines.append(tr("DEPOSIT_LEFT").format({
		"n": int(d["amount"]), "total": int(d["capacity"]),
		"item": tr(StationPanel.item_key(str(d["item"])))}))
	lines.append(tr("DEPOSIT_REFILL").format({"n": int(d["refill"])})
		if int(d["refill"]) > 0 else tr("DEPOSIT_NO_REFILL"))
	if bool(d["relic_marked"]):
		lines.append(tr("DEPOSIT_RELIC_MARKED"))
	elif bool(d["relic"]):
		lines.append(tr("DEPOSIT_RELIC_CHANCE").format(
			{"p": int(Balance.RELIC_CHANCE * 100.0)}))
	_tip.setup("\n".join(lines))
	_tip.position = _place(at, _tip.get_combined_minimum_size())
	_tip.visible = true
	_timer.start(LIFE_SEC)

## Правая нижняя четверть — мёртвая зона кнопки «Отзыв», её не перекрывает
## ничто (docs/03 §1). Подсказка, наехавшая на единственную командную кнопку
## игры, — это пропущенное нажатие в Сигнале (аудит B4).
func _place(at: Vector2, tip: Vector2) -> Vector2:
	var view: Vector2 = get_viewport_rect().size
	var gap: float = float(UITokens.SPACE_3)
	var pos: Vector2 = at + Vector2(gap, gap)
	var dead: Rect2 = Rect2(view - Vector2.ONE * float(UITokens.DEADZONE_PX),
		Vector2.ONE * float(UITokens.DEADZONE_PX))
	if Rect2(pos, tip).intersects(dead):
		# Уводим влево-вверх от точки касания: там места всегда больше.
		pos = at - Vector2(tip.x + gap, tip.y + gap)
	return pos.clamp(Vector2.ZERO, (view - tip).max(Vector2.ZERO))

func hide_tip() -> void:
	_tip.visible = false
