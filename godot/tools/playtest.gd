extends SceneTree
## Тонкий лаунчер прогона игры. Сам сценарий — в playtest_run.gd.
##
## ⚠️ Почему два файла: скрипт, запущенный через `-s`, компилируется ДО того,
## как движок регистрирует имена автолоадов, и `Game`/`Events` в нём — «не
## найденный идентификатор». Загруженный в рантайме — уже видит их.

const RUNNER: String = "res://tools/playtest_run.gd"

## Ссылку держим полем: локальная переменная умрёт вместе с _initialize, и
## корутина сценария оборвётся молча — прогон просто повиснет без единой строки.
var _runner: RefCounted = null

func _initialize() -> void:
	var script: GDScript = load(RUNNER) as GDScript
	if script == null:
		push_error("playtest: не загрузился %s" % RUNNER)
		quit(2)
		return
	_runner = script.new() as RefCounted
	_runner.call("start", self)
