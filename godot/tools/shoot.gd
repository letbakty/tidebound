extends SceneTree
## Тонкий лаунчер съёмки кадров игры (сценарий — tools/shoot_run.gd).
##
## ⚠️ Два файла по той же причине, что у playtest.gd: скрипт под `-s`
## компилируется ДО регистрации автолоадов, и `Game`/`Settings` в нём —
## «не найденный идентификатор». Загруженный в рантайме уже их видит.

const RUNNER: String = "res://tools/shoot_run.gd"

## Ссылку держим полем: локальная умрёт вместе с _initialize и корутина
## оборвётся молча — процесс просто повиснет.
var _runner: RefCounted = null

func _initialize() -> void:
	var script: GDScript = load(RUNNER) as GDScript
	if script == null:
		push_error("shoot: не загрузился %s" % RUNNER)
		quit(2)
		return
	_runner = script.new() as RefCounted
	_runner.call("start", self)
