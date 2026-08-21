extends SceneTree
## Эталон состояния мира (TEST-05, golden master).
##   godot --headless -s res://tools/gen_golden.gd
##
## Записывает снимки на фиксированных тиках в tests/golden/. Тест test_golden
## прогоняет те же сиды и сверяет; расхождение означает, что поведение
## изменилось — намеренно или нет.
##
## ⚠️ Обновлять эталон можно ТОЛЬКО осознанно, вместе с правкой баланса или
## правил, и обязательно смотреть дифф: это единственное место, где видно
## «после правки вся колония стала жить иначе». test_determinism на такое не
## реагирует — два одинаково изменившихся прогона совпадут друг с другом.

const OUT_DIR: String = "res://tests/golden/"
const CLIFF: String = "res://data/cliffs/cliff_01.tres"

## Сид -> сколько тиков прогонять. Первый — полный забег, второй — полтора
## цикла: короткий ловит правки старта, длинный — правки всего забега.
const RUNS: Dictionary[int, int] = {4242: 36000, 777: 4500}
## Шаг снимков. 1500 тиков = полфазы LOW: чаще смысла нет, реже — расхождение
## придётся искать бинарным поиском вручную.
const EVERY: int = 1500

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var cliff: CliffDef = load(CLIFF) as CliffDef
	var written: int = 0
	for seed_value: int in RUNS:
		var data: Dictionary = GoldenRun.capture(seed_value, int(RUNS[seed_value]),
			EVERY, cliff)
		var path: String = OUT_DIR + "run_%d.json" % seed_value
		var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			push_error("gen_golden: не открыть %s" % path)
			continue
		# С отступами и сортировкой ключей: файл должен читаться в диффе
		# глазами, иначе он бесполезен.
		f.store_string(JSON.stringify(data, "\t", true, true))
		f.close()
		written += 1
		print("эталон %s: снимков %d" % [path, (data["points"] as Array).size()])
	quit(0 if written == RUNS.size() else 1)
