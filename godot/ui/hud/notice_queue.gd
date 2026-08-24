class_name NoticeQueue
extends Node
## Единая очередь уведомлений с приоритетами: банер > подсказка > тост.
##
## Заводится сразу на этапе 13, хотя подсказки появятся только на 15-м:
## иначе три независимых источника начнут накладываться друг на друга
## и разбирать это придётся уже в готовом HUD (research/25 §4).

## Кто показывается поверх кого. Одновременно виден один банер и одна
## подсказка; тосты идут своим стеком и очередь их не задерживает.
enum Kind { TOAST, HINT, BANNER }

## Кто кого ЖДЁТ, а не только кто кого важнее. Подсказка ждёт закрытия банера:
## на скриншоте четвёртого цикла у первого живого игрока висели разом банер
## «Приход», драфт и карточка урока — три текста читает ноль человек
## (FIX-playtest-01 §4).
const WAITS_FOR: Dictionary[int, int] = {Kind.HINT: Kind.BANNER}

signal show_banner(payload: Dictionary)
signal show_hint(payload: Dictionary)
signal show_toast(payload: Dictionary)

var _queue: Array[Dictionary] = []
var _busy: Dictionary[int, bool] = {}

## payload — что понадобится получателю; очередь в него не заглядывает.
func push(kind: Kind, payload: Dictionary) -> void:
	_queue.append({"kind": int(kind), "payload": payload})
	# Сортировка стабильная: при равном приоритете порядок прихода сохраняется.
	_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["kind"]) > int(b["kind"]))
	_pump()

## Получатель сообщает, что освободился (банер закрыт, подсказка прочитана).
func release(kind: Kind) -> void:
	_busy.erase(int(kind))
	_pump()

func clear() -> void:
	_queue.clear()
	_busy.clear()

func _pump() -> void:
	var rest: Array[Dictionary] = []
	for item: Dictionary in _queue:
		var kind: int = int(item["kind"])
		if kind != int(Kind.TOAST) and _busy.has(kind):
			rest.append(item)         # место занято — ждёт своей очереди
			continue
		if _busy.has(int(WAITS_FOR.get(kind, -1))):
			rest.append(item)         # ждёт того, кто важнее
			continue
		if kind != int(Kind.TOAST):
			_busy[kind] = true
		_emit(kind, item["payload"] as Dictionary)
	_queue = rest

func _emit(kind: int, payload: Dictionary) -> void:
	match kind:
		int(Kind.BANNER): show_banner.emit(payload)
		int(Kind.HINT): show_hint.emit(payload)
		_: show_toast.emit(payload)
