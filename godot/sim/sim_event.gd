class_name SimEvent
extends RefCounted
## Единственный способ для sim/ сообщить что-то наружу. Сигналы в ядре
## запрещены: сигнал вызывается синхронно посреди тика, слушатель может
## изменить состояние — и порядок систем поедет (research/11 §4).

var type: String = ""
## РЕШЕНИЕ: data намеренно нетипизированный Dictionary — типизированный
## Dictionary[String, Variant] не даёт ни скорости, ни защиты, но мешает
## класть Vector2i (research/11 §5). Это осознанное исключение из правила
## «типизация везде», не забывать при рефакторинге.
var data: Dictionary = {}

static func make(p_type: String, p_data: Dictionary = {}) -> SimEvent:
	var e: SimEvent = SimEvent.new()
	e.type = p_type
	e.data = p_data
	return e
