extends RefCounted
## Целостность репозитория: то, что видно изнутри движка и не зависит от машины.
##
## Делит работу с `tools/doctor.gd`, и логика живёт ТАМ: доктор ловит сломанное
## ОКРУЖЕНИЕ (не та версия движка, CRLF после клона на Windows, невыполненный
## импорт) — это чинит человек у себя; сьют ловит сломанный КОММИТ — это не
## должно доехать до main. Проверки, зависящие от машины, здесь намеренно
## не повторяются: в CI они дали бы красный на исправном коде.
##
## tools/ вырезается только при экспорте (`exclude_filter` во всех пресетах),
## а тесты живут в том же дереве и вызвать доктора могут.

const Doctor = preload("res://tools/doctor.gd")

static func test_no_duplicate_class_names(t: TestCtx) -> void:
	var found: PackedStringArray = Doctor.duplicate_class_names()
	t.check(found.is_empty(),
		"дублей class_name нет (иначе движок валит проект целиком): %s"
		% ", ".join(found))

static func test_no_duplicate_def_ids(t: TestCtx) -> void:
	var found: PackedStringArray = Doctor.duplicate_def_ids()
	t.check(found.is_empty(),
		"дублей id у дефов нет (DB индексирует по id, второй затирает первый): %s"
		% ", ".join(found))

static func test_no_broken_res_links(t: TestCtx) -> void:
	var found: PackedStringArray = Doctor.broken_res_links()
	t.check(found.is_empty(),
		"все ссылки res:// ведут в существующие файлы: %s" % ", ".join(found))

## Страховка от тихого самоотключения: если обход дерева однажды перестанет
## находить файлы, три проверки выше станут зелёными и бессмысленными.
static func test_scanner_sees_the_project(t: TestCtx) -> void:
	t.check(Doctor.script_count() > 100,
		"обход дерева видит скрипты проекта (нашёл %d)" % Doctor.script_count())
	t.check(Doctor.def_count() > 20,
		"и дефы данных (нашёл %d)" % Doctor.def_count())

## Презентация знает про ВСЕ данные, которыми её расширили.
##
## Эти две проверки живут здесь, а не в докторе: доктор работает текстом на
## неимпортированном клоне и загруженных классов не видит, а тут нужны именно
## константы WorldView и BuildingView.
##
## Ловят ровно то, что случилось: волна контента добавила четыре вида
## депозитов в Balance.DEPOSIT_KINDS, а WorldView.DEPOSIT_COLORS об этом
## не узнал — и половина депозитов на карте рисовалась Color.MAGENTA.
static func test_every_deposit_kind_has_a_color(t: TestCtx) -> void:
	var missing: PackedStringArray = []
	for kind: String in Balance.DEPOSIT_KINDS:
		if not WorldView.DEPOSIT_COLORS.has(kind):
			missing.append(kind)
	t.check(missing.is_empty(),
		"у каждого вида депозита есть цвет в WorldView.DEPOSIT_COLORS"
		+ " (иначе Color.MAGENTA на карте): %s" % ", ".join(missing))

static func test_every_building_special_has_a_color(t: TestCtx) -> void:
	var missing: PackedStringArray = []
	for id: String in DB.building_ids():
		var def: BuildingDef = DB.building(id)
		if def == null or def.special.is_empty():
			continue
		if not BuildingView.COLORS.has(def.special):
			missing.append("%s (special=%s)" % [id, def.special])
	t.check(missing.is_empty(),
		"у каждой постройки есть цвет заглушки в BuildingView.COLORS"
		+ " (иначе серый #909090): %s" % ", ".join(missing))
