extends SceneTree
## Раскладка аудио-шин: Master → Music, SFX, UI, Ambient.
##   godot --headless -s res://tools/gen_bus_layout.gd
##
## Генератором, а не кликами в редакторе (research/23 §1): раскладка — часть
## контракта настроек (Settings._apply_bus зовёт шины по именам), и она должна
## пересобираться из исходников так же, как тема и данные.
##
## SceneTree, а не EditorScript: проект собирается headless, как остальные
## tools/gen_*.
##
## Стартовый баланс шин — research/35 §6.3: музыка не перекрывает колокол,
## эмбиент остаётся фоном, клики не громче мира. Игрок правит это в настройках,
## здесь — точка отсчёта.

const OUT: String = "res://default_bus_layout.tres"

## Имя шины -> её громкость относительно Master, дБ.
const BUSES: Array[Array] = [
	["Music", -6.0],
	["SFX", -3.0],
	["UI", -6.0],
	["Ambient", -9.0],
]

func _initialize() -> void:
	AudioServer.set_bus_count(1 + BUSES.size())
	for i: int in BUSES.size():
		var idx: int = i + 1
		AudioServer.set_bus_name(idx, str(BUSES[i][0]))
		AudioServer.set_bus_send(idx, "Master")
		AudioServer.set_bus_volume_db(idx, float(BUSES[i][1]))
	# Master без запаса вниз не оставляем: сумма слоёв не должна упираться
	# в ноль (док Godot про шины).
	AudioServer.set_bus_volume_db(0, 0.0)
	var err: Error = ResourceSaver.save(AudioServer.generate_bus_layout(), OUT)
	if err != OK:
		push_error("gen_bus_layout: не сохранилась раскладка, ошибка %d" % err)
		quit(1)
		return
	print("раскладка шин готова: %s (%d шины под Master)" % [OUT, BUSES.size()])
	quit(0)
