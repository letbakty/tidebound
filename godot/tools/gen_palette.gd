extends SceneTree
## Палитра проекта из ФАКТИЧЕСКИХ цветов отобранного арта
## (prompts/ART-integration §2 п.2, research/29 §3.1).
##
##   godot --headless -s res://tools/gen_palette.gd
##
## Почему из ассетов, а не наоборот: палитру никто не рисовал заранее —
## её задала генерация. Собранный отсюда art/tidebound.gpl становится
## ЕДИНСТВЕННЫМ источником правды по цвету; в ui/theme/tokens.gd HEX руками
## не копировать (два источника правды разъедутся).
##
## Заодно это проверка приёмки из ART-generation §5: «палитра ровно из 32
## цветов, без промежуточных оттенков от ресайза». Больше 32 — значит где-то
## ресайз или антиалиасинг, и это надо чинить в арте, а не в игре.

const SRC_DIR: String = "res://../art-rd/processed/"
const OUT_GPL: String = "res://../art/tidebound.gpl"
const WANT_COLORS: int = 32

## Имена цветов: чтобы .gpl читался человеком и диффился в git осмысленно.
## Цвет, которого здесь нет, получит имя вида c_1a3a4a — это сигнал, что арт
## притащил новый оттенок и его надо назвать (или убрать).
const NAMES: Dictionary[String, String] = {
	"0a1216": "deep_ink", "0e1a20": "abyss", "0f1d26": "deep_water",
	"14282f": "trench", "16262e": "silt_dark", "1a3a4a": "water_cold",
	"1e343d": "silt", "2a4550": "shoal", "2d6b7a": "surf",
	"33565c": "kelp_shadow", "3d6270": "water_shallow", "3d6b54": "weed_dark",
	"55707a": "wet_stone", "64757c": "rust_cold", "7aa85e": "weed",
	"96a0a4": "stone_pale", "9aabb0": "fog", "e8eff0": "foam",
	"282c34": "shadow", "464c54": "metal", "d8d4c4": "bone",
	"584434": "wood_dark", "786048": "wood", "8a7442": "brass_dark",
	"965836": "rust_warm", "a68e6a": "sand_shadow", "c8b28c": "linen",
	"c9a15e": "sand", "d4553a": "fire", "e8a85a": "ember",
	"e8c170": "sand_lit", "f0d6aa": "lamp",
}

func _initialize() -> void:
	var picks: PackedStringArray = _pick_files()
	if picks.is_empty():
		push_error("gen_palette: в %s нет файлов *_pick" % SRC_DIR)
		quit(2)
		return
	var area: Dictionary[String, int] = {}
	var semi_files: PackedStringArray = []
	for file: String in picks:
		var img: Image = Image.new()
		if img.load(SRC_DIR + file) != OK:
			push_error("gen_palette: не читается %s" % file)
			continue
		img.convert(Image.FORMAT_RGBA8)
		var semi: int = 0
		for y: int in img.get_height():
			for x: int in img.get_width():
				var c: Color = img.get_pixel(x, y)
				if c.a < 0.004:
					continue
				if c.a < 0.996:
					semi += 1
					continue
				var key: String = _hex(c)
				area[key] = int(area.get(key, 0)) + 1
		if semi > 0:
			semi_files.append("%s (%d)" % [file, semi])

	# Полупрозрачность в пиксель-арте — почти всегда случайный антиалиасинг
	# кисти (research/29 §3.3). Это дефект арта, а не повод его чинить кодом.
	if not semi_files.is_empty():
		push_error("gen_palette: полупрозрачные пиксели: %s"
			% ", ".join(semi_files))

	var keys: Array[String] = []
	keys.assign(area.keys())
	# Сортировка: зона (холод -> тепло -> нейтраль), внутри — по площади.
	# Порядок в .gpl — это то, что художник видит в Aseprite слева направо.
	keys.sort_custom(func(a: String, b: String) -> bool:
		var za: int = _zone(a)
		var zb: int = _zone(b)
		if za != zb:
			return za < zb
		return int(area[a]) > int(area[b]))

	var out: PackedStringArray = ["GIMP Palette", "Name: Tidebound 32",
		"Columns: 8",
		"# АВТОСБОРКА: godot --headless -s res://tools/gen_palette.gd",
		"# Источник — art-rd/processed/*_pick.png, ТОЛЬКО отобранные файлы.",
		"# Это источник правды по цвету (research/29 §3.1): HEX руками",
		"# в ui/theme/tokens.gd не копировать.",
		"# Порядок: холод (ниже яруса 0) -> тепло (выше) -> нейтраль.", "#"]
	var zones: Array[int] = [0, 0, 0]
	for key: String in keys:
		var c: Color = Color(key)
		zones[_zone(key)] += 1
		out.append("%3d %3d %3d\t%s" % [int(c.r8), int(c.g8), int(c.b8),
			NAMES.get(key, "c_" + key)])
	var f: FileAccess = FileAccess.open(OUT_GPL, FileAccess.WRITE)
	if f == null:
		push_error("gen_palette: не пишется %s" % OUT_GPL)
		quit(2)
		return
	f.store_string("\n".join(out) + "\n")
	f.close()
	print("палитра: %d цветов (холод %d, тепло %d, нейтраль %d) из %d файлов"
		% [keys.size(), zones[0], zones[1], zones[2], picks.size()])
	if keys.size() != WANT_COLORS:
		push_error("gen_palette: цветов %d, а по ТЗ ровно %d — где-то ресайз "
			% [keys.size(), WANT_COLORS] + "или антиалиасинг")
		quit(1)
		return
	quit(0)

func _pick_files() -> PackedStringArray:
	var out: PackedStringArray = []
	# ⚠️ DirAccess не ходит за пределы res:// по относительному пути —
	# папка арта лежит РЯДОМ с проектом, её путь надо глобализовать.
	# Image.load() при этом «res://../» понимает, отсюда и расхождение.
	var dir: DirAccess = DirAccess.open(ProjectSettings.globalize_path(SRC_DIR))
	if dir == null:
		return out
	for file: String in dir.get_files():
		if file.ends_with(".png") and file.contains("_pick"):
			out.append(file)
	out.sort()
	return out

func _hex(c: Color) -> String:
	return "%02x%02x%02x" % [int(c.r8), int(c.g8), int(c.b8)]

## 0 — холод, 1 — тепло, 2 — нейтраль. Граница тёплого/холодного по тону:
## главный визуальный язык игры — «ничего тёплого ниже нуля» (docs/00 §3.1).
func _zone(key: String) -> int:
	var c: Color = Color(key)
	if c.s < 0.10:
		return 2
	var h: float = c.h * 360.0
	return 1 if (h < 70.0 or h > 330.0) else 0
