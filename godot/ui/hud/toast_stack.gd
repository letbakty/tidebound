class_name ToastStack
extends Control
## Стек тостов у правого края НАД кнопкой отзыва. Однотипные группируются
## («смыло 3 стака ×3»), тап ведёт камеру к месту, свайп скрывает.

signal focus_requested(cell: Vector2i)

const GROUP_WINDOW_SEC: float = 10.0
const MAX_VISIBLE: int = 4

## type -> {node, count, t_last}. Группировка по типу события, а не по тексту:
## три разных склада с одинаковой бедой — одна карточка ×3.
var _active: Dictionary[String, Dictionary] = {}
var _box: VBoxContainer = null
## Мёртвая зона кнопки отзыва вычисляется от её размера, а не «на глаз»:
## при масштабе UI 150% тосты иначе наедут на кнопку (research/21 §4).
var _bottom_margin: float = float(UITokens.DEADZONE_PX)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	Events.run_started.connect(_on_run_started)

## Стек жмётся к правому нижнему углу и растёт вверх: ширина — по содержимому,
## а не во весь экран, иначе тост перечёркивает половину мира.
func _build() -> void:
	_box = VBoxContainer.new()
	_box.name = "Box"
	_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_box.alignment = BoxContainer.ALIGNMENT_END
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	_apply_deadzone()

## Зовётся из HUD после сборки: отступ снизу = высота кнопки отзыва + зазор.
func set_deadzone(height: float) -> void:
	_bottom_margin = height + float(UITokens.SPACE_3)
	_apply_deadzone()

func _apply_deadzone() -> void:
	if _box != null:
		_box.offset_bottom = -_bottom_margin

## text — уже переведённая строка. type — ключ группировки.
func push(type: String, text: String, tone: Toast.Tone, cell: Vector2i,
		life_sec: float = -1.0) -> void:
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var group: Dictionary = _active.get(type, {})
	if not group.is_empty() and is_instance_valid(group["node"] as Node) \
			and now - float(group["t_last"]) < GROUP_WINDOW_SEC:
		var node: Toast = group["node"] as Toast
		group["count"] = int(group["count"]) + 1
		group["t_last"] = now
		_active[type] = group
		node.set_count(int(group["count"]))
		node.restart_timer()
		return
	var toast: Toast = Toast.new()
	_box.add_child(toast)
	toast.setup(text, tone, cell, life_sec)
	toast.tapped.connect(func() -> void: focus_requested.emit(toast.cell))
	toast.dismissed.connect(func() -> void: _dismiss(type, toast))
	_active[type] = {"node": toast, "count": 1, "t_last": now}
	# ⚠️ remove_child ДО queue_free: очередь удаления разбирается в конце кадра,
	# и до неё get_child_count не меняется — цикл по одному queue_free вешал
	# игру намертво на пятом тосте (аудит B1.1).
	while _box.get_child_count() > MAX_VISIBLE:
		var oldest: Node = _box.get_child(0)
		_forget(oldest)
		_box.remove_child(oldest)
		oldest.queue_free()

## Снять тост этого типа со стека, если он ещё висит. Нужен персистентным
## тостам (life = 0): их некому убрать по таймеру, а повод показывать может
## исчезнуть — «колония на грани» гаснет с приходом человека (docs/01 §2).
func dismiss(type: String) -> void:
	var group: Dictionary = _active.get(type, {})
	if group.is_empty():
		return
	var node: Node = group["node"] as Node
	_active.erase(type)
	if not is_instance_valid(node):
		return
	# ⚠️ remove_child ДО queue_free — по той же причине, что и в push().
	if node.get_parent() == _box:
		_box.remove_child(node)
	node.queue_free()

## Вытесненный тост нельзя оставлять в группировке: следующий тост того же
## типа «догруппировался» бы к ноде, которой на экране уже нет.
func _forget(node: Node) -> void:
	for type: String in _active.keys():
		if (_active[type] as Dictionary)["node"] == node:
			_active.erase(type)
			return

func _dismiss(type: String, toast: Toast) -> void:
	var group: Dictionary = _active.get(type, {})
	if not group.is_empty() and group["node"] == toast:
		_active.erase(type)
	toast.queue_free()

func _on_run_started(_seed_value: int) -> void:
	_active.clear()
	for c: Node in _box.get_children():
		c.queue_free()
