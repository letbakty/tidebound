extends SceneTree
## Доктор проекта: шесть проверок окружения ПЕРЕД первым запуском.
##
##   godot --headless --path godot -s res://tools/doctor.gd
##
## Одной строкой и без shell — на Windows его нет, а именно там ломается
## больше всего (переводы строк, вторая копия из распакованного ZIP).
##
## ⚠️ Работает ДО импорта: движок с ключом -s выполняет скрипт сразу, ничего
## не импортируя, поэтому доктор не грузит ни одного ресурса и читает всё
## текстом. Отсюда же смысл проверки №6: на свежем клоне `.godot/` ещё нет.
##
## Что доктор ловит и чего не ловит: он про СЛОМАННОЕ ОКРУЖЕНИЕ (не та версия
## движка, вторая копия проекта, CRLF после клона на Windows). Про сломанный
## КОММИТ — `tests/test_project_integrity.gd`, он зовёт отсюда те же функции,
## чтобы логика жила в одном месте.

const NEED_MAJOR: int = 4
const NEED_MINOR: int = 7

## Расширения, в которых ищем ссылки res://.
const LINK_EXTS: PackedStringArray = ["gd", "tscn", "tres"]

## Сколько находок печатать в одной проверке. Вторая копия проекта даёт их
## сотнями (тот случай на чужой машине — 434 ошибки парсера), и стена текста
## прячет остальные пять проверок.
const MAX_SHOWN: int = 8

func _initialize() -> void:
	print("TIDEBOUND — доктор проекта")
	print("проект: %s" % ProjectSettings.globalize_path("res://"))
	print("")
	var found: int = 0
	var checks: Array[Array] = [
		["вторая копия проекта внутри res://", nested_projects(),
			"вынести папку за пределы godot/ либо положить внутрь неё пустой"
			+ " файл .gdignore — такую папку движок пропускает целиком"],
		["дубли class_name", duplicate_class_names(),
			"это и есть след второй копии без project.godot: движок отвечает"
			+ " «Class \"X\" hides a global script class» и сотнями ошибок"
			+ " парсера при исправном коде. Оставить один файл, копию убрать"],
		["дубли id у дефов data/**/*.tres", duplicate_def_ids(),
			"DB индексирует дефы по id, а не по имени файла: второй деф молча"
			+ " затирает первый. Развести id"],
		["битые ссылки res://", broken_res_links(),
			"файл переименовали или не добавили в коммит — проверить по имени"
			+ " и строке выше"],
		["версия движка", wrong_engine_version(),
			"версия зафиксирована в project.godot (config/features): младший"
			+ " движок откажется открывать проект, старший молча обновит"
			+ " формат сцен и ресурсов"],
		["переводы строк в tools/*.sh", crlf_shell_scripts(),
			"git config core.autocrlf false && git add --renormalize . &&"
			+ " git checkout -- . В репозитории есть .gitattributes с eol=lf,"
			+ " но у тех, кто клонировал раньше, дерево не поправится само"],
		["импорт ассетов выполнен", import_not_done(),
			"godot --headless --path godot --import --quit — первый импорт"
			+ " занимает около минуты; папка godot/.godot/ в репозиторий"
			+ " не входит и создаётся сама"],
	]
	for probe: Array in checks:
		var lines: PackedStringArray = probe[1] as PackedStringArray
		if lines.is_empty():
			print("  ok    %s" % str(probe[0]))
			continue
		found += lines.size()
		print("  НАДО  %s" % str(probe[0]))
		for i: int in mini(lines.size(), MAX_SHOWN):
			print("        %s" % lines[i])
		if lines.size() > MAX_SHOWN:
			print("        …и ещё %d" % (lines.size() - MAX_SHOWN))
		print("        → %s" % str(probe[2]))
	print("")
	print("проверок %d, находок %d" % [checks.size(), found])
	if found == 0:
		print("окружение в порядке — можно открывать godot/project.godot")
	quit(1 if found > 0 else 0)

# --- Проверка 1: вторая копия проекта -------------------------------------

## Папка с вложенным project.godot. Второй копией чаще всего оказывается
## распакованный с GitHub ZIP (`tidebound-main/`) или клон, положенный внутрь
## папки проекта: Godot сканирует ВСЕ .gd под res:// и валит проект целиком.
static func nested_projects() -> PackedStringArray:
	var out: PackedStringArray = []
	for p: String in _walk("res://", ["godot"]):
		if p == "res://project.godot":
			continue
		out.append("вложенный проект: %s" % p)
	return out

# --- Проверка 2: дубли class_name -----------------------------------------

## Вторая копия бывает и БЕЗ project.godot — например, если скопировали одну
## папку godot/. Тогда единственный след — два одинаковых class_name, и
## движок отвечает «Class "X" hides a global script class» и сотнями ошибок
## парсера при полностью исправном коде.
static func duplicate_class_names() -> PackedStringArray:
	var seen: Dictionary[String, PackedStringArray] = {}
	var rx: RegEx = RegEx.create_from_string("(?m)^class_name\\s+([A-Za-z_][A-Za-z0-9_]*)")
	for path: String in _walk("res://", ["gd"]):
		var m: RegExMatch = rx.search(_read(path))
		if m == null:
			continue
		var name: String = m.get_string(1)
		if not seen.has(name):
			seen[name] = PackedStringArray()
		var arr: PackedStringArray = seen[name]
		arr.append(path)
		seen[name] = arr
	var out: PackedStringArray = []
	for name: String in seen:
		var paths: PackedStringArray = seen[name]
		if paths.size() < 2:
			continue
		out.append("class_name %s объявлен %d раза: %s"
			% [name, paths.size(), ", ".join(paths)])
	return out

# --- Проверка 3: дубли id у дефов -----------------------------------------

## DB индексирует дефы по полю id, а не по имени файла: второй деф с тем же
## id молча затирает первый, и понять это по игре почти невозможно.
static func duplicate_def_ids() -> PackedStringArray:
	var seen: Dictionary[String, PackedStringArray] = {}
	var rx: RegEx = RegEx.create_from_string("(?m)^id\\s*=\\s*\"([^\"]+)\"")
	for path: String in _walk("res://data", ["tres"]):
		var m: RegExMatch = rx.search(_read(path))
		if m == null:
			continue
		var id: String = m.get_string(1)
		if not seen.has(id):
			seen[id] = PackedStringArray()
		var arr: PackedStringArray = seen[id]
		arr.append(path)
		seen[id] = arr
	var out: PackedStringArray = []
	for id: String in seen:
		var paths: PackedStringArray = seen[id]
		if paths.size() < 2:
			continue
		out.append("id \"%s\" у %d дефов: %s" % [id, paths.size(), ", ".join(paths)])
	return out

# --- Проверка 4: битые ссылки res:// --------------------------------------

## Ссылки собираются текстом, а не загрузкой ресурсов: доктор обязан работать
## на неимпортированном клоне, где load() любой текстуры падает.
static func broken_res_links() -> PackedStringArray:
	var out: PackedStringArray = []
	var rx: RegEx = RegEx.create_from_string("res://[A-Za-z0-9_./-]*")
	for path: String in _walk("res://", LINK_EXTS):
		var lines: PackedStringArray = _read(path).split("\n")
		for i: int in lines.size():
			for m: RegExMatch in rx.search_all(lines[i]):
				# Хвостовая точка — конец фразы в комментарии, а не часть пути.
				# Обрезать её у ВСЕЙ ссылки нельзя: голое упоминание «res://»
				# в комментарии превратилось бы в «res:» и попало в находки.
				var tail: String = m.get_string(0).substr(6).rstrip(".")
				if tail.is_empty():
					continue                     # просто слово «res://» в тексте
				var link: String = "res://" + tail
				# Кэш импорта — не ссылка на исходник: его нет ни в репозитории,
				# ни на свежем клоне, а упоминается он в самом докторе (проверка
				# №7). Без этого исключения доктор находил дефект в себе — и
				# ровно на том клоне, ради которого написан.
				if link.begins_with("res://.godot"):
					continue
				if _link_ok(link):
					continue
				out.append("%s:%d — нет файла %s" % [path, i + 1, link])
	return out

## Ссылка живая, если это существующий файл или существующая папка.
## Папка — не поблажка: пути вида "res://data/items/" + id + ".tres" собираются
## в рантайме, и регулярка видит от них только каталог.
static func _link_ok(link: String) -> bool:
	if FileAccess.file_exists(link) or DirAccess.dir_exists_absolute(link):
		return true
	# .tscn/.tres после экспорта лежат как .remap, а исходник — .gd рядом.
	return FileAccess.file_exists(link + ".remap")

# --- Проверка 5: версия движка --------------------------------------------

static func wrong_engine_version() -> PackedStringArray:
	var v: Dictionary = Engine.get_version_info()
	if int(v["major"]) == NEED_MAJOR and int(v["minor"]) == NEED_MINOR:
		return []
	return PackedStringArray(["движок %s, а проекту нужен %d.%d.x"
		% [str(v["string"]), NEED_MAJOR, NEED_MINOR]])

# --- Проверка 6: переводы строк -------------------------------------------

## Установщик Git для Windows по умолчанию ставит core.autocrlf=true. После
## клона каждый .sh получает CRLF и умирает на первой строке:
## `/usr/bin/env bash^M: bad interpreter`.
static func crlf_shell_scripts() -> PackedStringArray:
	var bad: PackedStringArray = []
	for path: String in _walk("res://tools", ["sh"]):
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		if bytes.find(13) >= 0:                      # 13 = CR
			bad.append(path)
	if bad.is_empty():
		return []
	return PackedStringArray(["CRLF в %d скриптах: %s" % [bad.size(), ", ".join(bad)]])

# --- Проверка 7: импорт ---------------------------------------------------

## Ключ -s выполняет скрипт БЕЗ импорта, поэтому на свежем клоне .godot/ ещё
## нет — и любой прогон тестов упадёт на первой же текстуре.
static func import_not_done() -> PackedStringArray:
	var root: String = ProjectSettings.globalize_path("res://.godot")
	if DirAccess.dir_exists_absolute(root + "/imported"):
		return []
	return PackedStringArray(["кэш импорта не собран (нет godot/.godot/imported/)"])

# --- Обход дерева ---------------------------------------------------------

## Рекурсивный обход res:// с фильтром по расширениям.
##
## ⚠️ Скрытые папки DirAccess по умолчанию не отдаёт, поэтому в .godot/ обход
## не заходит; папки с .gdignore движок не показывает вовсе — и это правильно:
## закрытая копия проекта уже обезврежена.
static func _walk(root: String, exts: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = []
	var queue: PackedStringArray = [root]
	while not queue.is_empty():
		var dir_path: String = queue[0]
		queue.remove_at(0)
		var d: DirAccess = DirAccess.open(dir_path)
		if d == null:
			continue
		for sub: String in d.get_directories():
			queue.append(dir_path.path_join(sub))
		for f: String in d.get_files():
			var name: String = f.trim_suffix(".remap")
			if exts.has(name.get_extension()):
				out.append(dir_path.path_join(name))
	out.sort()
	return out

## Счётчики для сьюта: проверка, которая ничего не нашла, потому что обход
## сломался, зеленее той, что нашла всё.
static func script_count() -> int:
	return _walk("res://", ["gd"]).size()

static func def_count() -> int:
	return _walk("res://data", ["tres"]).size()

static func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)
