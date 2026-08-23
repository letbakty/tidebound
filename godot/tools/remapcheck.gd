extends SceneTree
## Тонкий лаунчер проверки ремапа. Сам сценарий — в remapcheck_run.gd.
##
## ⚠️ Почему два файла: скрипт, запущенный через `-s`, компилируется ДО того,
## как движок регистрирует имена автолоадов, и `Settings` в нём — «не найденный
## идентификатор». Загруженный в рантайме — уже видит их (как в playtest.gd).

const RUNNER: String = "res://tools/remapcheck_run.gd"

## Ссылку держим полем: локальная умрёт вместе с _initialize, и корутина
## оборвётся молча.
var _runner: RefCounted = null

func _initialize() -> void:
	var script: GDScript = load(RUNNER) as GDScript
	if script == null:
		push_error("remapcheck: не загрузился %s" % RUNNER)
		quit(2)
		return
	_runner = script.new() as RefCounted
	_runner.call("start", self)
