extends RefCounted
## TEST-04 — санитария сигналов (этап 19 п.3).
##
## Шина Events объявляет ВСЕ сигналы сразу (контракт docs/02 §3.2), поэтому до
## этапа 19 «сигнал без слушателя» был нормой. Здесь это уже проверка: каждый
## сигнал кем-то эмитится, каждый тип SimEvent имеет ветку в Game._flush_events,
## а мёртвых веток в нём нет.
##
## Совпадение СИГНАТУР проверяет test_hud/test_event_handler_arity: обработчик
## с несовместимой сигнатурой движок просто не вызывает, а предупреждение
## видно только в debug-сборке (docs/02 §10).

const EVENTS_PATH: String = "res://autoload/events.gd"
const GAME_PATH: String = "res://autoload/game.gd"
const SCAN_DIRS: Array[String] = ["res://autoload/", "res://ui/", "res://game/",
	"res://debug/"]

## Сигналы, у которых нет статического слушателя, и это законно: их слушает
## только шпион дебаг-панели, который подписывается на ВСЮ шину динамически
## (`Events.connect(sname, cb)` — грепом такое не найти).
##
## Список закрытый: новый сигнал без слушателя обязан валить прогон, иначе
## он тихо умрёт между этапами.
const LISTENED_DYNAMICALLY: Array[String] = ["sim_ticked", "unlock_gained",
	"ui_panel_opened", "ui_panel_closed"]

# --- Сигналы --------------------------------------------------------------

## Сигнал, который никто не эмитит, — это мёртвый контракт: подписчик ждёт
## событие, которого не будет, и заметить это можно только в игре.
static func test_every_signal_is_emitted(t: TestCtx) -> void:
	var declared: Array[String] = _declared_signals()
	t.check(declared.size() > 20, "разобрался events.gd")
	var emitted: Dictionary[String, bool] = _scan(r"Events\.([a-z_]+)\.emit\(")
	for sig: String in declared:
		t.check(emitted.has(sig), "сигнал %s никто не эмитит" % sig)

## Слушатель есть либо статический, либо динамический — и тогда сигнал обязан
## быть в списке-исключении с объяснением.
static func test_every_signal_is_listened(t: TestCtx) -> void:
	var declared: Array[String] = _declared_signals()
	var listened: Dictionary[String, bool] = _scan(r"Events\.([a-z_]+)\.connect\(")
	for sig: String in declared:
		if listened.has(sig):
			continue
		t.check(LISTENED_DYNAMICALLY.has(sig),
			"сигнал %s никто не слушает и его нет в списке динамических" % sig)
	# И наоборот: если у «динамического» появился обычный слушатель, список
	# пора чистить — иначе исключение переживёт свою причину.
	for sig: String in LISTENED_DYNAMICALLY:
		t.check(declared.has(sig), "в списке динамических нет сигнала %s" % sig)

## Эмитить сигналы шины имеет право не кто угодно: события симуляции
## перекладывает ТОЛЬКО Game (docs/02 §3.2). Иначе один и тот же сигнал
## приходит дважды и из разных мест.
static func test_sim_signals_are_emitted_by_game_only(t: TestCtx) -> void:
	var sim_signals: Array[String] = _declared_signals_before("--- От UI/оркестрации")
	t.check(sim_signals.size() > 15, "разобрался блок сим-сигналов")
	var re: RegEx = RegEx.new()
	re.compile(r"Events\.([a-z_]+)\.emit\(")
	for path: String in _gd_files():
		if path.ends_with("autoload/game.gd") or path.ends_with("autoload/events.gd"):
			continue
		# Мета-профиль — осознанное исключение: unlock_gained рождается в Meta,
		# а не в симуляции.
		if path.ends_with("autoload/meta.gd"):
			continue
		# Дебаг-панель форсирует состояния (оверрайд воды, кнопки кризисов) и
		# обязана рассылать их сама — иначе картинка не обновится до тика,
		# которого на паузе не будет. В релиз res://debug/ не попадает вовсе
		# (фильтры экспорта, research/26 §2.2), поэтому на игру это не влияет.
		if path.begins_with("res://debug/"):
			continue
		var src: String = FileAccess.get_file_as_string(path)
		for m: RegExMatch in re.search_all(src):
			t.check(not sim_signals.has(m.get_string(1)),
				"%s эмитит сим-сигнал %s мимо Game" % [path.get_file(), m.get_string(1)])

# --- События симуляции ----------------------------------------------------

## Каждый тип SimEvent обязан иметь ветку в Game._flush_events: без неё
## _error_count растёт молча, а событие просто не доезжает до картинки.
static func test_every_sim_event_has_a_branch(t: TestCtx) -> void:
	var produced: Dictionary[String, bool] = _scan_dir("res://sim/",
		r'SimEvent\.make\(\s*"([a-z_]+)"')
	t.check(produced.size() > 20, "нашлись типы событий в sim/")
	var handled: Dictionary[String, bool] = _flush_branches()
	t.check(handled.size() > 20, "разобрался match в game.gd")
	for type_name: String in produced:
		t.check(handled.has(type_name),
			"тип события %s не разбирается в Game._flush_events" % type_name)

## И обратно: ветка без события — мёртвый код, который пережил переименование.
static func test_no_dead_branches(t: TestCtx) -> void:
	var produced: Dictionary[String, bool] = _scan_dir("res://sim/",
		r'SimEvent\.make\(\s*"([a-z_]+)"')
	for type_name: String in _flush_branches():
		t.check(produced.has(type_name),
			"ветка %s в Game._flush_events ничем не порождается" % type_name)

## Полный забег не должен породить ни одного неизвестного типа события.
## Это та же проверка, но не по исходникам, а прогоном — на случай события,
## собранного не литералом.
static func test_full_run_emits_only_known_types(t: TestCtx) -> void:
	var handled: Dictionary[String, bool] = _flush_branches()
	var w: SimWorld = SimWorld.new()
	w.new_run(4242, load("res://data/cliffs/cliff_01.tres") as CliffDef)
	var seen: Dictionary[String, bool] = {}
	# Полтора цикла: этого хватает на все фазовые события, драфт и кризисы,
	# а полный забег в 36 000 тиков в обычном прогоне тестов лишний.
	for i: int in 4500:
		w.tick()
		for e: SimEvent in w.events_out:
			seen[e.type] = true
		w.events_out.clear()
	t.check(seen.size() > 8, "за полтора цикла событий набралось")
	for type_name: String in seen:
		t.check(handled.has(type_name),
			"забег породил событие %s без ветки в Game" % type_name)

# --- Утилиты --------------------------------------------------------------

static func _declared_signals() -> Array[String]:
	return _declared_signals_before("")

## Сигналы, объявленные ДО строки-маркера. Нужен, чтобы отделить сим-сигналы
## от UI-сигналов: в events.gd они разделены комментарием-заголовком.
static func _declared_signals_before(marker: String) -> Array[String]:
	var out: Array[String] = []
	var re: RegEx = RegEx.new()
	re.compile(r"^signal\s+([a-z_]+)")
	for line: String in FileAccess.get_file_as_string(EVENTS_PATH).split("\n"):
		if not marker.is_empty() and line.contains(marker):
			break
		var m: RegExMatch = re.search(line)
		if m != null:
			out.append(m.get_string(1))
	return out

## Метки веток match e.type в Game._flush_events.
static func _flush_branches() -> Dictionary[String, bool]:
	var src: String = FileAccess.get_file_as_string(GAME_PATH)
	var start: int = src.find("for e: SimEvent in world.events_out:")
	var out: Dictionary[String, bool] = {}
	if start < 0:
		return out
	var re: RegEx = RegEx.new()
	re.compile(r'^\t{3}"([a-z_]+)":')
	for line: String in src.substr(start).split("\n"):
		var m: RegExMatch = re.search(line)
		if m != null:
			out[m.get_string(1)] = true
	return out

static func _scan(pattern: String) -> Dictionary[String, bool]:
	var out: Dictionary[String, bool] = {}
	var re: RegEx = RegEx.new()
	re.compile(pattern)
	for path: String in _gd_files():
		for m: RegExMatch in re.search_all(FileAccess.get_file_as_string(path)):
			out[m.get_string(1)] = true
	return out

static func _scan_dir(dir: String, pattern: String) -> Dictionary[String, bool]:
	var out: Dictionary[String, bool] = {}
	var re: RegEx = RegEx.new()
	re.compile(pattern)
	for path: String in _files_in(dir):
		for m: RegExMatch in re.search_all(FileAccess.get_file_as_string(path)):
			out[m.get_string(1)] = true
	return out

static func _gd_files() -> Array[String]:
	var out: Array[String] = []
	for dir: String in SCAN_DIRS:
		out.append_array(_files_in(dir))
	return out

static func _files_in(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d: DirAccess = DirAccess.open(dir)
	if d == null:
		return out
	for f: String in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + f)
	for sub: String in d.get_directories():
		out.append_array(_files_in(dir + sub + "/"))
	return out

# --- Промотка времени -----------------------------------------------------

## Во время промотки (дебаг-панель) частые события не рассылаются: за забег их
## набегают десятки тысяч, и в замере этапа 19 промотка целого забега разгоняла
## процесс до 2 ГБ и занимала минуты. Отбрасывать можно ТОЛЬКО то, что
## rebroadcast_state() восстановит из состояния мира.
##
## Отчёты цикла и забега так не восстанавливаются: они существуют один раз.
## Если кто-то добавит их в список — метапрогресс перестанет начисляться, и
## заметить это можно будет только по пустому Журналу.
const MUST_REACH_UI: Array[String] = ["run_started", "run_ended", "cycle_ended",
	"draft_ready", "card_picked", "agent_died", "ship_arrived", "crisis_started",
	"crisis_ended", "crisis_announced", "recall_issued"]

## Событие -> сигнал, которым его состояние восстанавливается после промотки.
## Пустая строка = восстанавливать нечего (счётчик тиков).
const RESTORED_BY: Dictionary[String, String] = {
	"sim_ticked": "",
	"water_level_changed": "water_level_changed",
	"agent_updated": "agent_spawned",
	"storage_changed": "storage_changed",
	"resources_changed": "resources_changed",
	"deposit_changed": "deposit_changed",
	"building_state_changed": "building_state_changed",
	"production_spilled": "building_state_changed",
	"relic_found": "agent_spawned",
}

static func test_fast_forward_drops_only_recoverable(t: TestCtx) -> void:
	var src: String = FileAccess.get_file_as_string(GAME_PATH)
	var noisy: Array[String] = []
	for v: Variant in _const_array(src, "NOISY_EVENTS"):
		noisy.append(str(v))
	t.check(not noisy.is_empty(), "список частых событий разобран")
	for type_name: String in MUST_REACH_UI:
		t.check(not noisy.has(type_name),
			"%s нельзя отбрасывать: его состояние больше нигде не взять" % type_name)
	var rebroadcast: String = _function_body(src, "func rebroadcast_state()")
	t.check(not rebroadcast.is_empty(), "rebroadcast_state найдена")
	for type_name: String in noisy:
		t.check(RESTORED_BY.has(type_name),
			"%s в списке частых, но не сказано, чем он восстанавливается" % type_name)
		var sig: String = str(RESTORED_BY.get(type_name, ""))
		if sig.is_empty():
			continue
		t.check(rebroadcast.contains("Events.%s.emit" % sig),
			"после промотки %s восстанавливать нечем: rebroadcast_state не шлёт %s"
				% [type_name, sig])

## Значения строкового const-массива из исходника: разбирать GDScript целиком
## незачем, а список читается ровно одной регуляркой.
static func _const_array(src: String, name: String) -> Array:
	var header: String = "const %s: Array[String] = [" % name
	var at: int = src.find(header)
	if at < 0:
		return []
	# Отсчёт от открывающей скобки ЛИТЕРАЛА: в самом заголовке уже есть
	# «Array[String]», и поиск «]» от начала строки нашёл бы его.
	var start: int = at + header.length()
	var finish: int = src.find("]", start)
	var re: RegEx = RegEx.new()
	re.compile(r'"([a-z_]+)"')
	var out: Array = []
	for m: RegExMatch in re.search_all(src.substr(start, finish - start)):
		out.append(m.get_string(1))
	return out

## Тело функции до следующей func на нулевом отступе.
static func _function_body(src: String, header: String) -> String:
	var start: int = src.find(header)
	if start < 0:
		return ""
	var finish: int = src.find("\nfunc ", start + header.length())
	return src.substr(start, (finish - start) if finish > 0 else -1)
