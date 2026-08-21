class_name GoldenRun
extends RefCounted
## Снимок забега на фиксированных тиках (TEST-05). Общий код генератора
## эталона (tools/gen_golden.gd) и теста (tests/test_golden.gd): считать
## снимок обязан ОДИН код, иначе эталон и проверка разъедутся сами по себе.
##
## Кроме хеша в снимке лежат читаемые числа. Хеш отвечает на вопрос «что-то
## изменилось?», числа — на вопрос «что именно», и именно ради второго
## golden-master вообще заводят.

## Хеш состояния — с ПОЛНОЙ точностью, как в сейве: усечённый прячет
## расхождения ниже значимого разряда, и тест оказывается слабее файла,
## который игра реально пишет (TEST-06).
static func hash_of(w: SimWorld) -> String:
	return JSON.stringify(w.to_dict(), "", true, true).sha256_text()

## Читаемая сводка: по ней видно, ЧТО изменилось, когда хеш разошёлся.
static func summary(w: SimWorld) -> Dictionary:
	var totals: Dictionary = w.storage.totals()
	var keys: Array[String] = []
	keys.assign(totals.keys())
	keys.sort()                       # порядок ключей словаря нестабилен
	var stock: Array[String] = []
	for k: String in keys:
		stock.append("%s:%d" % [k, int(totals[k])])
	return {
		"tick": w.clock.total_ticks(),
		"cycle": w.clock.cycle,
		"phase": SimTypes.phase_name(int(w.clock.phase)),
		"level": snappedf(w.tide.level, 0.001),
		"alive": w.agents.alive_count(),
		"buildings": w.buildings.buildings.size(),
		"stock": ", ".join(stock),
		"hash": hash_of(w),
	}

## Прогоняет забег и снимает состояние каждые `every` тиков.
static func capture(seed_value: int, ticks: int, every: int,
		cliff: CliffDef) -> Dictionary:
	var w: SimWorld = SimWorld.new()
	w.new_run(seed_value, cliff)
	w.events_out.clear()
	var points: Array = []
	for i: int in ticks:
		w.tick()
		w.events_out.clear()
		if (i + 1) % every == 0:
			points.append(summary(w))
	return {"seed": seed_value, "ticks": ticks, "every": every, "points": points}
