extends SceneTree
## Генератор темы интерфейса.
##   godot --headless -s res://tools/gen_theme.gd
##   godot --headless --import --quit
##
## SceneTree, а не EditorScript: проект собирается и проверяется headless
## (тот же принцип, что у остальных tools/gen_*).

func _initialize() -> void:
	var th: Theme = UIThemeFactory.build()
	var err: Error = UIThemeFactory.save(th)
	if err != OK:
		push_error("gen_theme: не сохранилась тема, ошибка %d" % err)
		quit(1)
		return
	print("тема собрана: %s" % UIThemeFactory.OUT_PATH)
	quit(0)
