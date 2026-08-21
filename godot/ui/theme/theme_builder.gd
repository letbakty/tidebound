@tool
extends EditorScript
## Генератор темы из редактора: File -> Run (Ctrl+Shift+X), НЕ кнопкой Play.
## Логика сборки — в ui/theme/theme_factory.gd; здесь только запуск и сохранение.
##
## Headless-эквивалент (им пользуется CI и агенты):
##   godot --headless -s res://tools/gen_theme.gd

func _run() -> void:
	var th: Theme = UIThemeFactory.build()
	var err: Error = UIThemeFactory.save(th)
	print("theme: %s (%s)" % [UIThemeFactory.OUT_PATH,
		"OK" if err == OK else "ERR %d" % err])
