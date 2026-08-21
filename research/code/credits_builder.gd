class_name CreditsBuilder
extends RefCounted
## Титры, собранные из источников, а не набранные руками. Переносить в
## res://ui/screens/credits_builder.gd (этап 15).
##
## Почему генерация: титры, набранные вручную, разъезжаются с содержимым папок
## через месяц. А лицензии Godot (MIT), OFL-шрифтов и CC-BY-звуков — это
## юридическое обязательство, а не украшение (research/38 §1).
##
## Источники:
##   Engine.get_license_text()  — MIT движка
##   Engine.get_copyright_info()— сторонние компоненты движка
##   assets/sfx/SOURCES.csv     — звук (research/35 §1.2)
##   assets/CREDITS.md          — арт и прочее (research/29 §6.2)

const SFX_SOURCES: String = "res://assets/sfx/SOURCES.csv"
const ASSET_CREDITS: String = "res://assets/CREDITS.md"

## Лицензии, которые в проекте быть НЕ должно. Проверяется тестом этапа 19.
const FORBIDDEN: Array[String] = ["CC-BY-NC", "CC BY-NC", "CC-BY-SA", "CC BY-SA"]

# --- Сборка ---------------------------------------------------------------

static func build() -> String:
	var out: PackedStringArray = []
	out.append("TIDEBOUND")
	out.append("© %s" % ProjectSettings.get_setting("application/config/author", ""))
	out.append("v%s" % ProjectSettings.get_setting("application/config/version", "0.0.0"))
	out.append("")
	out.append_array(_engine_section())
	out.append_array(_fonts_section())
	out.append_array(_audio_section())
	out.append_array(_assets_section())
	return "\n".join(out)

## Док Godot рекомендует именно эту вводную формулировку.
static func _engine_section() -> PackedStringArray:
	var out: PackedStringArray = ["— ДВИЖОК —", ""]
	out.append("This game uses Godot Engine, available under the following license:")
	out.append("")
	out.append(Engine.get_license_text())
	out.append("")
	return out

## Полный список сторонних компонентов движка (freetype, zlib и прочее).
## Показывать отдельной страницей: список длинный.
static func engine_third_party() -> String:
	var out: PackedStringArray = []
	for entry: Dictionary in Engine.get_copyright_info():
		out.append(str(entry.get("name", "")))
		for part: Dictionary in (entry.get("parts", []) as Array):
			for c: Variant in (part.get("copyright", []) as Array):
				out.append("  © %s" % str(c))
			out.append("  %s" % str(part.get("license", "")))
		out.append("")
	return "\n".join(out)

## ⚠️ Субсеттинг шрифта — это Modified Version по OFL: имя обязано отличаться
## от зарезервированного, а исходный копирайт — остаться (research/38 §1.2).
static func _fonts_section() -> PackedStringArray:
	var out: PackedStringArray = ["— ШРИФТЫ —", ""]
	var dir: DirAccess = DirAccess.open("res://assets/fonts/")
	if dir == null:
		return out
	var names: PackedStringArray = dir.get_files()
	names.sort()
	for f: String in names:
		var name: String = f.trim_suffix(".remap")
		if not name.begins_with("OFL") and not name.begins_with("LICENSE"):
			continue
		var fa: FileAccess = FileAccess.open("res://assets/fonts/" + name, FileAccess.READ)
		if fa == null:
			continue
		out.append(fa.get_as_text())
		fa.close()
		out.append("")
	return out

## CSV: file,source,pack_or_url,license,author,downloaded,notes
## CC0 и royalty-free сворачиваются в одну строку; CC-BY перечисляется поимённо
## — общая фраза «Sounds from Freesound» требованию CC-BY не удовлетворяет.
static func _audio_section() -> PackedStringArray:
	var out: PackedStringArray = ["— ЗВУК —", ""]
	var rows: Array[PackedStringArray] = _read_csv(SFX_SOURCES)
	if rows.is_empty():
		return out
	var packs: Dictionary[String, bool] = {}
	var attributed: PackedStringArray = []
	for r: PackedStringArray in rows:
		if r.size() < 5:
			continue
		var lic: String = r[3].strip_edges()
		var author: String = r[4].strip_edges()
		var url: String = r[2].strip_edges()
		if lic.to_upper().begins_with("CC-BY") or lic.to_upper().begins_with("CC BY"):
			attributed.append("%s — %s (%s), %s" % [author, r[0], lic, url])
		else:
			packs[r[1].strip_edges()] = true
	for p: String in packs:
		out.append("%s — royalty-free / CC0" % p)
	if not attributed.is_empty():
		out.append("")
		attributed.sort()
		out.append_array(attributed)
	out.append("")
	return out

static func _assets_section() -> PackedStringArray:
	var out: PackedStringArray = ["— ГРАФИКА И ПРОЧЕЕ —", ""]
	var f: FileAccess = FileAccess.open(ASSET_CREDITS, FileAccess.READ)
	if f != null:
		out.append(f.get_as_text())
		f.close()
	out.append("")
	return out

# --- Проверка для теста этапа 19 -------------------------------------------

## Возвращает список нарушений: запрещённые лицензии и строки без автора.
## Пустой массив = можно релизиться.
static func audit() -> Array[String]:
	var problems: Array[String] = []
	for path: String in [SFX_SOURCES, ASSET_CREDITS]:
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		if f == null:
			problems.append("нет файла источников: %s" % path)
			continue
		var text: String = f.get_as_text()
		f.close()
		for bad: String in FORBIDDEN:
			if text.contains(bad):
				problems.append("%s: запрещённая лицензия %s" % [path, bad])
	for r: PackedStringArray in _read_csv(SFX_SOURCES):
		if r.size() < 5:
			continue
		var lic: String = r[3].strip_edges().to_upper()
		if (lic.begins_with("CC-BY") or lic.begins_with("CC BY")) \
				and r[4].strip_edges().is_empty():
			problems.append("%s: CC-BY без автора" % r[0])
	return problems

static func _read_csv(path: String) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var first: bool = true
	while not f.eof_reached():
		var line: PackedStringArray = f.get_csv_line()
		if first:
			first = false                 # заголовок
			continue
		if line.size() > 1:
			out.append(line)
	f.close()
	return out
