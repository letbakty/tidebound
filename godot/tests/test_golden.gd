extends RefCounted
## TEST-05 — golden master: состояние мира на фиксированных тиках сверяется
## с эталоном из tests/golden/.
##
## Зачем отдельно от test_determinism: тот отвечает только на «два прогона
## совпали друг с другом» и не заметит, что после правки баланса вся колония
## стала жить иначе — оба прогона изменятся одинаково.
##
## Если тест упал ОСОЗНАННО (правили баланс, правила, генерацию карты):
##   godot --headless -s res://tools/gen_golden.gd
## и обязательно посмотреть дифф файлов эталона — в нём видно, что именно
## поменялось в жизни колонии.

const GOLDEN_DIR: String = "res://tests/golden/"
const CLIFF: String = "res://data/cliffs/cliff_01.tres"

static func test_golden_runs_match(t: TestCtx) -> void:
	var files: Array[String] = _golden_files()
	t.check(not files.is_empty(),
		"нет эталонов: запусти tools/gen_golden.gd и закоммить tests/golden/")
	var cliff: CliffDef = load(CLIFF) as CliffDef
	for path: String in files:
		_compare(t, path, cliff)

static func _compare(t: TestCtx, path: String, cliff: CliffDef) -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var golden: Dictionary = raw as Dictionary
	if golden == null:
		t.check(false, "эталон %s не читается" % path)
		return
	var seed_value: int = int(golden["seed"])
	var expected: Array = golden["points"] as Array
	var actual: Array = (GoldenRun.capture(seed_value, int(golden["ticks"]),
		int(golden["every"]), cliff)["points"]) as Array
	t.check_eq(actual.size(), expected.size(),
		"сид %d: число снимков" % seed_value)
	var diverged: bool = false
	for i: int in mini(actual.size(), expected.size()):
		var a: Dictionary = actual[i] as Dictionary
		var e: Dictionary = expected[i] as Dictionary
		if str(a["hash"]) == str(e["hash"]):
			continue
		# Печатаем ПЕРВОЕ расхождение с разбором по полям и дальше молчим:
		# после расхождения все последующие снимки отличаются тоже, и сотня
		# одинаковых строк только мешает.
		if not diverged:
			diverged = true
			t.check(false, "сид %d: состояние разошлось на тике %s" % [
				seed_value, str(e.get("tick", "?"))])
			for key: String in ["cycle", "phase", "level", "alive", "buildings", "stock"]:
				if str(a.get(key, "")) != str(e.get(key, "")):
					t.check(false, "  %s: было %s, стало %s" % [
						key, str(e.get(key, "")), str(a.get(key, ""))])
	if not diverged:
		t.check(true, "сид %d: забег совпал с эталоном (%d снимков)" % [
			seed_value, expected.size()])

## Хеш считается с полной точностью — той же, что у сейва (TEST-06). Усечённый
## прячет расхождения ниже значимого разряда: тест проходит, а после save → load
## мир расходится.
static func test_hash_uses_full_precision(t: TestCtx) -> void:
	var src: String = FileAccess.get_file_as_string("res://tests/test_ctx.gd")
	t.check(src.contains('JSON.stringify(world.call("to_dict"), "", true, true)'),
		"state_hash считает хеш с той же точностью, что и сейв")
	# И по сути: сдвиг ровно на один квант (Balance.quant, шаг 1e-4) обязан
	# менять и хеш теста, и хеш эталона. Меньше кванта состояние не бывает —
	# всё, что мельче, sim и так округляет.
	var cliff: CliffDef = load(CLIFF) as CliffDef
	var a: SimWorld = SimWorld.new()
	a.new_run(11, cliff)
	var b: SimWorld = SimWorld.new()
	b.new_run(11, cliff)
	t.check_eq(TestCtx.state_hash(a), TestCtx.state_hash(b),
		"одинаковые миры — одинаковый хеш")
	b.tide.level = Balance.quant(b.tide.level + 0.0001)
	t.check(TestCtx.state_hash(a) != TestCtx.state_hash(b),
		"сдвиг на квант виден в хеше теста")
	t.check(GoldenRun.hash_of(a) != GoldenRun.hash_of(b),
		"и в хеше эталона")

static func _golden_files() -> Array[String]:
	var out: Array[String] = []
	var d: DirAccess = DirAccess.open(GOLDEN_DIR)
	if d == null:
		return out
	for f: String in d.get_files():
		if f.ends_with(".json"):
			out.append(GOLDEN_DIR + f)
	out.sort()
	return out
