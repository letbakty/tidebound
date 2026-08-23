extends RefCounted
## Приёмка этапа 18: время в шейдерах, бюджет света, кадры агента, порядок
## слоёв мира, атлас интерфейса, режим съёмки.
##
## Картинку тест не проверяет — она проверяется глазами по скриншотам. Здесь
## ровно те вещи, которые ломаются молча и замечаются через месяц.

const SHADER_DIR: String = "res://assets/shaders/"
const WORLD_SCENE: String = "res://game/world.tscn"
const ATLAS: String = "res://assets/sprites/ui_atlas.png"
## Атлас тайлов мира. Имя файла осталось от заглушек: на него ссылается
## data/tilesets/placeholder.tres, а data/ правит другой агент (см. SOURCES.csv).
const TILES: String = "res://assets/sprites/placeholder_tiles.png"
## Файлы, которые собираются из токенов темы, а не из арта.
const SKIN_FILES: PackedStringArray = ["ui_atlas.png"]

## Шейдеры, которым время нужно (остальным — нет, и это не дефект).
const ANIMATED: Array[String] = ["water", "rain", "vignette", "wet_tiles"]
const ALL_SHADERS: Array[String] = ["water", "rain", "vignette", "wet_tiles",
	"depth_fog", "sprite_lit"]

# --- Время ----------------------------------------------------------------

## ⚠️ Главный пункт приёмки этапа. Встроенный TIME не останавливается на паузе
## (подтверждено документацией 4.7), а пауза — главная механика управления:
## вода, продолжающая волноваться на паузе, ломает её насмерть.
static func test_no_builtin_time_in_shaders(t: TestCtx) -> void:
	var re: RegEx = RegEx.new()
	# Слово TIME целиком и НЕ как часть sim_time: границы \b по обе стороны.
	re.compile(r"(^|[^A-Za-z_])TIME([^A-Za-z_]|$)")
	for name: String in ALL_SHADERS:
		var src: String = FileAccess.get_file_as_string(SHADER_DIR + name + ".gdshader")
		t.check(not src.is_empty(), "шейдер %s читается" % name)
		for line: String in src.split("\n"):
			# Комментарии не считаем: в них TIME упоминается как раз с запретом.
			var code: String = line.split("//")[0]
			t.check(re.search(code) == null,
				"%s: встроенный TIME запрещён, только sim_time (%s)" % [name, line.strip_edges()])

## Анимированные шейдеры обязаны объявлять global uniform: без объявления
## sim_time молча читается как ноль, и всё стоит на месте.
static func test_animated_shaders_use_sim_time(t: TestCtx) -> void:
	for name: String in ANIMATED:
		var src: String = FileAccess.get_file_as_string(SHADER_DIR + name + ".gdshader")
		t.check(src.contains("global uniform float sim_time"),
			"%s не объявляет sim_time" % name)

## Оверлеи не должны освещаться PointLight2D: иначе фонарь подсвечивает сам
## туман, и над лампой висит тёплое пятно в воздухе.
static func test_overlays_are_unshaded(t: TestCtx) -> void:
	for name: String in ["water", "rain", "vignette", "depth_fog"]:
		t.check(_render_mode(name).contains("unshaded"),
			"%s должен быть unshaded" % name)
	# А материалы мира — наоборот, обязаны освещаться. Слово ищем именно в
	# render_mode: в комментариях unshaded упоминается как раз с объяснением,
	# почему его здесь нет.
	t.check(not _render_mode("sprite_lit").contains("unshaded"),
		"sprite_lit обязан освещаться: unshaded — это opt-OUT")

# --- Материалы ------------------------------------------------------------

## Материал есть у каждого шейдера, и в нём стоят числа приёмки: пена ровно
## 2 px (промпт 18 п.3), отражение 0.20 (п.4).
static func test_materials_are_generated(t: TestCtx) -> void:
	for name: String in ALL_SHADERS:
		var path: String = SHADER_DIR + name + "_material.tres"
		t.check(ResourceLoader.exists(path), "нет материала %s" % path)
	var water: ShaderMaterial = load(SHADER_DIR + "water_material.tres") as ShaderMaterial
	t.check(water != null and water.shader != null, "у воды есть шейдер")
	if water == null:
		return
	t.check_eq(float(water.get_shader_parameter(&"u_foam_px")), 2.0,
		"пена по промпту — 2 px")
	t.check_eq(float(water.get_shader_parameter(&"u_reflect_alpha")), 0.20,
		"отражение по промпту — альфа 0.2")
	t.check(float(water.get_shader_parameter(&"u_refract_px")) > 0.0,
		"искажение включено")

# --- Порядок слоёв --------------------------------------------------------

## CanvasLayer.layer перебивает z_index: туман обязан лежать ПОД водой, иначе
## вода не тонирует то, что под ней, а дождь рисуется поверх глади.
static func test_world_layers_order(t: TestCtx) -> void:
	var src: String = FileAccess.get_file_as_string(WORLD_SCENE)
	var fog: int = _layer_of(src, "FogLayer")
	var rain: int = _layer_of(src, "RainLayer")
	var water: int = _layer_of(src, "WaterLayer")
	t.check(fog > 0 and rain > 0 and water > 0, "все три слоя на месте")
	t.check(fog < rain, "туман под дождём")
	t.check(rain < water, "дождь под водой")

## Parallax2D не должен лежать на CanvasLayer: у слоя follow_viewport_enabled
## по умолчанию false, параллакс перестаёт получать движение камеры и застывает.
static func test_parallax_is_not_on_canvas_layer(t: TestCtx) -> void:
	var src: String = FileAccess.get_file_as_string(WORLD_SCENE)
	var re: RegEx = RegEx.new()
	re.compile(r'\[node name="([A-Za-z0-9_]+)" type="Parallax2D" parent="([^"]*)"\]')
	var found: int = 0
	for m: RegExMatch in re.search_all(src):
		found += 1
		t.check_eq(m.get_string(2), ".",
			"%s должен быть прямым потомком мира" % m.get_string(1))
	t.check_eq(found, 3, "три слоя параллакса из промпта")

## ⚠️ Дефект, который стоил всему миру 40% яркости и жил незамеченным.
##
## В canvas_item-шейдере встроенный COLOR на входе в fragment() — это УЖЕ
## texture(TEXTURE, UV) * modulate (док Godot 4.7). Строка `COLOR = tex * COLOR`
## в wet_tiles возводила цвет тайла в КВАДРАТ: #c9a15e приезжал на экран как
## #9e6623. На одноцветных заглушках это читалось как «атмосферно темно», и
## увидеть это можно было только замером пикселя финального кадра.
##
## Поэтому проверка грепом, а не глазами: сравнивать скриншоты некому.
## Если однажды понадобится СДВИНУТЫЙ UV (искажение), исключение вносится сюда
## осознанно — вместе с объяснением, почему двойного умножения там нет.
static func test_shaders_do_not_resample_own_texture(t: TestCtx) -> void:
	for name: String in ALL_SHADERS:
		var src: String = FileAccess.get_file_as_string(SHADER_DIR + name + ".gdshader")
		for line: String in src.split("\n"):
			var code: String = line.split("//")[0]
			t.check(not code.contains("texture(TEXTURE"),
				"%s: COLOR уже равен texture(TEXTURE, UV) * modulate — "
				% name + "повторная выборка возводит цвет в квадрат (%s)"
				% line.strip_edges())

# --- Тайлсет мира (этап 18: арт вместо заглушек) --------------------------

## Атлас тайлов: шесть слотов 32×32 в ряд. Размер и порядок — контракт с
## game/world.gd (T_CLIFF=0 … кромка=5) и data/tilesets/placeholder.tres.
## Сборщик — tools/gen_tiles.gd; руками файл не правится.
static func test_tile_atlas_geometry(t: TestCtx) -> void:
	var gen: GDScript = load("res://tools/gen_tiles.gd") as GDScript
	var slots: Array = gen.get("SLOTS") as Array
	t.check_eq(slots.size(), 6, "шесть слотов, как ждёт тайлсет")
	t.check_eq(int(gen.get("TILE")), WorldGeo.TILE, "тайл 32×32 из WorldGeo")
	var tex: Texture2D = load(TILES) as Texture2D
	t.check(tex != null, "атлас тайлов загружается")
	if tex == null:
		return
	t.check_eq(tex.get_height(), WorldGeo.TILE, "высота атласа — один тайл")
	t.check_eq(tex.get_width(), WorldGeo.TILE * slots.size(),
		"ширина атласа = число слотов")
	# Порядок слотов и константы world.gd обязаны совпадать: перепутанная
	# колонка даёт руины на верхнем ярусе и молчит.
	t.check_eq(int(slots[WorldView.T_CLIFF]["name"] == "cliff"), 1, "слот 0 — утёс")
	t.check_eq(int(slots[WorldView.T_SAND]["name"] == "sand"), 1, "слот 1 — песок")
	t.check_eq(int(slots[WorldView.T_RUINS]["name"] == "ruins"), 1, "слот 2 — руины")
	t.check_eq(int(slots[WorldView.T_LADDER]["name"] == "ladder"), 1, "слот 3 — лестница")
	t.check_eq(int(slots[WorldView.T_BACK]["name"] == "back"), 1, "слот 4 — стенка")

## Пиксель-арт: только a=0 или a=255 и только цвета палитры. Полупрозрачность
## и «лишний» оттенок — это всегда след ресайза или антиалиасинга кисти
## (research/29 §3.3), и в игре они видны как мыло по кромке тайла.
##
## Проверяются ТОЛЬКО слоты, за которыми уже стоит арт: слоты-заглушки залиты
## программными оттенками и законно вне палитры. Порог «сколько чужого можно»
## был бы вечнозелёным враньём — как только слот получает арт, он обязан быть
## чистым целиком.
static func test_tile_atlas_is_clean_pixel_art(t: TestCtx) -> void:
	var img: Image = (load(TILES) as Texture2D).get_image()
	if img == null:
		t.check(false, "атлас тайлов не читается как Image")
		return
	var allowed: Dictionary[String, bool] = _palette_hexes()
	t.check_eq(allowed.size(), 32, "палитра art/tidebound.gpl прочиталась")
	var gen: GDScript = load("res://tools/gen_tiles.gd") as GDScript
	var slots: Array = gen.get("SLOTS") as Array
	var tile: int = int(gen.get("TILE"))
	var with_art: int = 0
	for i: int in slots.size():
		var slot: Dictionary = slots[i]
		if str(slot["src"]).is_empty():
			continue
		with_art += 1
		var semi: int = 0
		var strays: Dictionary[String, bool] = {}
		for y: int in tile:
			for x: int in tile:
				var c: Color = img.get_pixel(i * tile + x, y)
				if c.a < 0.004:
					continue
				if c.a < 0.996:
					semi += 1
					continue
				var hex: String = "%02x%02x%02x" % [int(c.r8), int(c.g8), int(c.b8)]
				if not allowed.has(hex):
					strays[hex] = true
		t.check_eq(semi, 0, "слот %s: полупрозрачных пикселей нет" % str(slot["name"]))
		t.check(strays.is_empty(), "слот %s (%s): цвета вне палитры — %s"
			% [str(slot["name"]), str(slot["src"]), ", ".join(strays.keys())])
	t.check(with_art > 0, "хотя бы один слот уже на настоящем арте")

## Палитра проекта — art/tidebound.gpl рядом с проектом (не в res://: в билд
## ей не надо). Собирает tools/gen_palette.gd из отобранного арта.
static func _palette_hexes() -> Dictionary[String, bool]:
	var out: Dictionary[String, bool] = {}
	var path: String = ProjectSettings.globalize_path("res://../art/tidebound.gpl")
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line: String = f.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#") or line.begins_with("GIMP") \
				or line.begins_with("Name:") or line.begins_with("Columns:"):
			continue
		var parts: PackedStringArray = line.split("\t", false)
		if parts.is_empty():
			continue
		var rgb: PackedStringArray = parts[0].split(" ", false)
		if rgb.size() < 3:
			continue
		out["%02x%02x%02x" % [int(rgb[0]), int(rgb[1]), int(rgb[2])]] = true
	return out

## Мокрые тайлы — материалом на Ground: без него правило docs/00 §5 не видно
## в картинке вообще.
static func test_ground_has_wet_material(t: TestCtx) -> void:
	var src: String = FileAccess.get_file_as_string(WORLD_SCENE)
	var idx: int = src.find('[node name="Ground"')
	t.check(idx >= 0, "слой Ground на месте")
	if idx < 0:
		return
	var tail: String = src.substr(idx, 240)
	t.check(tail.contains("material = ExtResource"), "у Ground есть материал")
	t.check(src.contains("wet_tiles_material.tres"), "и это материал мокрых тайлов")

# --- Свет -----------------------------------------------------------------

## Приёмка промпта: «спавн 12 фонарей не роняет fps, дальние гаснут».
static func test_light_budget_caps_at_max(t: TestCtx) -> void:
	t.check_eq(LightBudget.lit_for(12), Balance.MAX_LIGHTS,
		"из двенадцати горят только восемь")
	t.check_eq(LightBudget.lit_for(3), 3, "меньше лимита — горят все")
	t.check_eq(LightBudget.lit_for(0), 0, "ноль светов — ноль горящих")
	t.check_eq(Balance.MAX_LIGHTS, 8, "лимит docs/00 §16")

# --- Кадры агента ---------------------------------------------------------

## Кадр выбирается по сим-времени: на паузе агент замирает, на ×3 перебирает
## ногами втрое быстрее — и то и другое бесплатно.
static func test_agent_frames(t: TestCtx) -> void:
	t.check_eq(AgentView.cell_for(SimTypes.AgentState.IDLE, false, false, 3.7),
		Vector2i(0, AgentView.Row.IDLE), "стоящий налегке — ряд ожидания")
	var seen: Dictionary[int, bool] = {}
	for i: int in 32:
		var c: Vector2i = AgentView.cell_for(SimTypes.AgentState.GOTO, true,
			false, float(i) * 0.05)
		t.check_eq(c.y, int(AgentView.Row.WALK), "ходьба живёт в своём ряду")
		t.check(c.x >= 0 and c.x < AgentView.COLS, "кадр внутри листа")
		seen[c.x] = true
	t.check_eq(seen.size(), AgentView.COLS, "за цикл проходят все кадры ходьбы")
	# Груз виден позой, а не значком: ходьба туда-обратно с котомкой — главный
	# смысл всей колонии, и она обязана читаться на 16 пикселях.
	t.check_eq(AgentView.cell_for(SimTypes.AgentState.GOTO, true, true, 0.3).y,
		int(AgentView.Row.CARRY), "с грузом — ряд переноски")
	t.check_eq(AgentView.cell_for(SimTypes.AgentState.GOTO, false, true, 0.3).y,
		int(AgentView.Row.CARRY),
		"остановился с грузом — груз никуда не делся")
	for st: int in [SimTypes.AgentState.WORK, SimTypes.AgentState.GATHER]:
		t.check_eq(AgentView.cell_for(st, false, false, 0.0).y,
			int(AgentView.Row.WORK), "работа живёт в своём ряду")
	t.check_eq(AgentView.cell_for(SimTypes.AgentState.DROWNING, false, false, 0.0).y,
		int(AgentView.Row.DROWN), "тонущий — свой ряд")
	t.check_eq(AgentView.cell_for(SimTypes.AgentState.PANIC, true, false, 0.0).y,
		int(AgentView.Row.PANIC), "паника перебивает ходьбу")
	# Одно и то же время — один и тот же кадр: анимация не зависит от кадров
	# рендера, иначе на паузе спрайт продолжал бы шагать.
	t.check_eq(AgentView.cell_for(SimTypes.AgentState.GOTO, true, false, 1.234),
		AgentView.cell_for(SimTypes.AgentState.GOTO, true, false, 1.234),
		"кадр — функция сим-времени, а не счётчика кадров")

## Лист спрайтов на месте и нужного размера: иначе region_rect молча уедет
## за край и агенты станут прозрачными.
static func test_agent_sheet_size(t: TestCtx) -> void:
	var gen: GDScript = load("res://tools/gen_agent.gd") as GDScript
	var rows: Array = gen.get("ROWS") as Array
	t.check_eq(int(gen.get("COLS")), AgentView.COLS, "столбцов поровну")
	t.check_eq(Vector2i(gen.get("CELL")), Vector2i(AgentView.W, AgentView.H),
		"размер кадра тот же")
	# Ряд листа — это состояние агента. Перепутанный порядок дал бы тонущего
	# вместо идущего и не уронил бы ничего.
	var names: Array = AgentView.Row.keys()
	t.check_eq(rows.size(), names.size(), "рядов столько же, сколько состояний")
	for i: int in mini(rows.size(), names.size()):
		t.check_eq(str((rows[i] as Dictionary)["name"]).to_upper(),
			str(names[i]), "ряд %d — то же состояние" % i)
	var tex: Texture2D = load("res://assets/sprites/agent.png") as Texture2D
	t.check(tex != null, "лист агента загружается")
	if tex == null:
		return
	t.check_eq(tex.get_width(), AgentView.W * AgentView.COLS, "ширина листа")
	t.check_eq(tex.get_height(), AgentView.H * names.size(), "высота листа")
	var dead: Texture2D = load(AgentView.DEAD_SPRITE) as Texture2D
	t.check(dead != null, "лежащий агент на месте")

# --- Атлас интерфейса -----------------------------------------------------

## Тема и генератор атласа обязаны знать один и тот же список кадров: иначе
## StyleBoxTexture возьмёт чужую рамку и не упадёт при этом.
static func test_ui_atlas_matches_theme(t: TestCtx) -> void:
	var gen: GDScript = load("res://tools/gen_ui_atlas.gd") as GDScript
	var frames: Array = gen.get("FRAMES") as Array
	t.check_eq(frames, UIThemeFactory.ATLAS_FRAMES as Array,
		"список кадров совпадает у темы и генератора")
	t.check_eq(int(gen.get("CELL")), UIThemeFactory.ATLAS_CELL, "размер кадра")
	t.check_eq(int(gen.get("MARGIN")), UIThemeFactory.ATLAS_MARGIN, "поля 9-patch")
	var tex: Texture2D = load(ATLAS) as Texture2D
	t.check(tex != null, "атлас на месте")
	if tex != null:
		t.check_eq(tex.get_width(), UIThemeFactory.ATLAS_CELL * frames.size(),
			"ширина атласа = число кадров")

## Скин переключается ОДНОЙ константой, и в атласном режиме панель приходит
## текстурой, а не заливкой.
static func test_skin_switch(t: TestCtx) -> void:
	var sb: StyleBox = UIThemeFactory.skin("panel", UITokens.PANEL_BG,
		UITokens.BORDER)
	if UIThemeFactory.USE_ATLAS:
		t.check(sb is StyleBoxTexture, "в атласном скине панель — текстура")
	else:
		t.check(sb is StyleBoxFlat, "в плоском скине панель — заливка")
	# Неизвестный кадр не должен ронять сборку темы — только откатываться
	# к плоскому стилю.
	t.check(UIThemeFactory.skin("нет-такого", UITokens.PANEL_BG,
		UITokens.BORDER) is StyleBoxFlat, "неизвестный кадр откатывается к flat")

# --- Режим съёмки ---------------------------------------------------------

## Дебаг-слой не попадает в кадр НИ В ОДНОМ режиме: он один способен испортить
## любой дубль, и заметить это можно только на смонтированном ролике.
static func test_capture_hides_layers(t: TestCtx) -> void:
	var main: Node = Node.new()
	var names: Array[String] = ["WorldContainer", "HUDLayer", "PanelLayer",
		"BannerLayer", "ScreenLayer", "DebugLayer", "WeatherLayer"]
	for n: String in names:
		var layer: CanvasLayer = CanvasLayer.new()
		layer.name = n
		main.add_child(layer)
	var cap: CaptureMode = CaptureMode.new()
	main.add_child(cap)

	cap.set_layers(CaptureMode.Layers.WORLD_ONLY)
	t.check(_vis(main, "WorldContainer"), "мир в кадре")
	t.check(not _vis(main, "HUDLayer"), "HUD скрыт")
	t.check(not _vis(main, "PanelLayer"), "панели скрыты")
	t.check(not _vis(main, "DebugLayer"), "дебаг скрыт")

	cap.set_layers(CaptureMode.Layers.UI_ONLY)
	t.check(not _vis(main, "WorldContainer"), "мир скрыт")
	t.check(_vis(main, "HUDLayer"), "HUD в кадре")
	t.check(not _vis(main, "DebugLayer"), "дебаг скрыт и здесь")

	cap.set_layers(CaptureMode.Layers.ALL)
	t.check(_vis(main, "WorldContainer") and _vis(main, "HUDLayer"),
		"обычный режим возвращает всё")
	t.check(not _vis(main, "DebugLayer"), "кроме дебага — он не нужен никогда")
	main.free()

# --- Утилиты --------------------------------------------------------------

static func _vis(main: Node, name: String) -> bool:
	var n: CanvasLayer = main.get_node_or_null(NodePath(name)) as CanvasLayer
	return n != null and n.visible

## Строка render_mode шейдера без комментариев.
static func _render_mode(name: String) -> String:
	var src: String = FileAccess.get_file_as_string(SHADER_DIR + name + ".gdshader")
	for line: String in src.split("\n"):
		var code: String = line.split("//")[0].strip_edges()
		if code.begins_with("render_mode"):
			return code
	return ""

static func _layer_of(scene_src: String, node_name: String) -> int:
	var idx: int = scene_src.find('[node name="%s" type="CanvasLayer"' % node_name)
	if idx < 0:
		return -1
	var re: RegEx = RegEx.new()
	re.compile(r"layer = (\d+)")
	var m: RegExMatch = re.search(scene_src.substr(idx, 120))
	return int(m.get_string(1)) if m != null else -1

# --- Настоящий арт: контракты сборщиков (этап 18, ART-integration) ---------

## Спрайт постройки обязан совпадать с её size из дефа. Постройка «на клетку
## шире» наезжает на соседнюю и молчит: ни один тест мира этого не заметит,
## потому что логика размещения считает по дефу, а видит игрок спрайт.
static func test_building_art_matches_defs(t: TestCtx) -> void:
	var gen: GDScript = load("res://tools/gen_building_art.gd") as GDScript
	var table: Dictionary = gen.get("BUILDINGS") as Dictionary
	# Постройки без арта перечислены поимённо (NO_ART): у них нет спрайта мира,
	# и BuildingView рисует программный силуэт. Список — способ УВИДЕТЬ дыру,
	# а не разрешение её не замечать: каждая постройка обязана быть ровно
	# в одной из двух таблиц, и размер в клетках сверяется с дефом в обеих.
	var no_art: Dictionary = gen.get("NO_ART") as Dictionary
	var ids: Array[String] = DB.building_ids()
	t.check_eq(table.size() + no_art.size(), ids.size(),
		"в таблицах арта столько же построек, сколько дефов")
	for id: String in ids:
		var row: Dictionary = (no_art.get(id, table.get(id, {}))) as Dictionary
		t.check(not row.is_empty(), "для %s есть строка в gen_building_art" % id)
		if row.is_empty():
			continue
		t.check(not (table.has(id) and no_art.has(id)),
			"%s числится и с артом, и без него" % id)
		var def: BuildingDef = DB.building(id)
		t.check_eq(Vector2i(row["cells"]), def.size,
			"%s: размер в клетках совпадает с дефом" % id)
		# ⚠️ Сначала exists(), потом load(): load() отсутствующего файла пишет
		# в лог `ERROR: Resource file not found`, а раннер валит прогон по любой
		# ошибке движка — проверка «спрайта нет» роняла бы сборку сама собой.
		var path: String = "res://assets/sprites/buildings/%s.png" % id
		if no_art.has(id):
			t.check(not ResourceLoader.exists(path),
				"%s: спрайта нет — рисуется заглушка" % id)
			continue
		t.check(ResourceLoader.exists(path), "%s: спрайт на месте" % id)
		if not ResourceLoader.exists(path):
			continue
		var tex: Texture2D = load(path) as Texture2D
		if tex == null:
			continue
		t.check_eq(tex.get_size(), Vector2(def.size) * float(WorldGeo.TILE),
			"%s: спрайт ровно на свои клетки" % id)

## Порядок кадров в атласах иконок — это АЛФАВИТ id, и считают его двое:
## сборщик и интерфейс. Разъезд показывает не ту иконку и ничего не роняет.
static func test_icon_atlases_match_defs(t: TestCtx) -> void:
	var items: GDScript = load("res://tools/gen_item_icons.gd") as GDScript
	var item_ids: Array[String] = DB.item_ids()
	t.check_eq((items.get("ITEMS") as Dictionary).keys().size(), item_ids.size(),
		"иконка есть у каждого предмета")
	for id: String in item_ids:
		t.check((items.get("ITEMS") as Dictionary).has(id), "иконка предмета %s" % id)
	t.check_eq(items.call("order"), item_ids, "порядок предметов — тот же алфавит")
	var atlas: Texture2D = load(IconStub.ITEM_ATLAS) as Texture2D
	t.check(atlas != null, "атлас предметов на месте")
	if atlas != null:
		t.check_eq(atlas.get_width(), IconStub.ITEM_CELL * item_ids.size(),
			"ширина атласа предметов = число предметов")
		t.check_eq(atlas.get_height(), IconStub.ITEM_CELL, "высота — одна клетка")
	var blds: GDScript = load("res://tools/gen_building_art.gd") as GDScript
	t.check_eq(blds.call("icon_order"), DB.building_ids(),
		"порядок построек — тот же алфавит")
	var batlas: Texture2D = load(IconStub.BUILDING_ATLAS) as Texture2D
	t.check(batlas != null, "атлас построек на месте")
	if batlas != null:
		t.check_eq(batlas.get_width(),
			IconStub.BUILDING_CELL * DB.building_ids().size(),
			"ширина атласа построек = число построек")

## Лист существа: ряд = состояние. Перепутанный порядок дал бы грызущее
## существо там, где оно плывёт, и не уронил бы ничего.
static func test_creature_sheet(t: TestCtx) -> void:
	var gen: GDScript = load("res://tools/gen_creature.gd") as GDScript
	var rows: Array = gen.get("ROWS") as Array
	var names: Array = CreatureView.Row.keys()
	t.check_eq(int(gen.get("COLS")), CreatureView.COLS, "столбцов поровну")
	t.check_eq(rows.size(), names.size(), "рядов столько же, сколько состояний")
	for i: int in mini(rows.size(), names.size()):
		t.check_eq(str((rows[i] as Dictionary)["name"]).to_upper(), str(names[i]),
			"ряд %d — то же состояние" % i)
	var tex: Texture2D = load(CreatureView.SHEET) as Texture2D
	t.check(tex != null, "лист существа загружается")
	if tex != null:
		t.check_eq(tex.get_width(), CreatureView.W * CreatureView.COLS, "ширина листа")
		t.check_eq(tex.get_height(), CreatureView.H * names.size(), "высота листа")

## Parallax2D повторяет слой ровно на repeat_size. Не равен ширине текстуры —
## значит шов при повторе, и виден он только в движении, на панораме.
static func test_parallax_repeat_matches_texture(t: TestCtx) -> void:
	var src: String = FileAccess.get_file_as_string(WORLD_SCENE)
	var re: RegEx = RegEx.new()
	re.compile(r'\[node name="(\w+)" type="Parallax2D"[^\]]*\]\n(?:[^\[]*?)repeat_size = Vector2\((\d+), \d+\)')
	var found: int = 0
	for m: RegExMatch in re.search_all(src):
		found += 1
		var node: String = m.get_string(1)
		var want: int = int(m.get_string(2))
		var tex_re: RegEx = RegEx.new()
		tex_re.compile(r'parent="%s"\]\ntexture = ExtResource\("([^"]+)"\)' % node)
		var tm: RegExMatch = tex_re.search(src)
		t.check(tm != null, "%s: у слоя есть спрайт с текстурой" % node)
		if tm == null:
			continue
		var path_re: RegEx = RegEx.new()
		path_re.compile(r'path="([^"]+)" id="%s"' % tm.get_string(1))
		var pm: RegExMatch = path_re.search(src)
		t.check(pm != null, "%s: текстура слоя разрешается в файл" % node)
		if pm == null:
			continue
		var tex: Texture2D = load(pm.get_string(1)) as Texture2D
		t.check(tex != null, "%s: текстура грузится" % node)
		if tex == null:
			continue
		t.check_eq(tex.get_width(), want,
			"%s: repeat_size = ширине текстуры, иначе шов" % node)
	t.check_eq(found, 3, "у всех трёх слоёв задан repeat_size")

## Весь арт в игре — из 32 цветов палитры и без полупрозрачных краёв.
##
## ⚠️ Единственная проверка, которая ловит «ассет пришёл мимо конвейера»:
## лишний оттенок от ресайза и антиалиасинг кисти в игре не видно, пока
## кто-нибудь не посмотрит на палитру рядом. Считаем нарушения на файл, а не
## на пиксель: 700 тысяч провалов в отчёте не помогут никому.
static func test_sprites_are_in_palette(t: TestCtx) -> void:
	var pal: Dictionary[int, bool] = {}
	for line: String in FileAccess.get_file_as_string(
			"res://../art/tidebound.gpl").split("\n"):
		var s: String = line.strip_edges()
		if s.is_empty() or not s[0].is_valid_int():
			continue
		var p: PackedStringArray = s.split("\t")[0].split(" ", false)
		if p.size() >= 3:
			pal[Color8(int(p[0]), int(p[1]), int(p[2])).to_rgba32()] = true
	t.check_eq(pal.size(), 32, "в палитре ровно 32 цвета")
	for path: String in _pngs("res://assets/sprites/"):
		# ui_atlas.png собирается не из арта, а из токенов темы
		# (tools/gen_ui_atlas.gd): скин интерфейса живёт в своих 16 цветах, и
		# палитра мира на него не распространяется.
		if path.get_file() in SKIN_FILES:
			continue
		var tex: Texture2D = load(path) as Texture2D
		if tex == null:
			continue
		var img: Image = tex.get_image()
		var outside: int = 0
		var semi: int = 0
		for y: int in img.get_height():
			for x: int in img.get_width():
				var c: Color = img.get_pixel(x, y)
				if c.a < 0.004:
					continue
				if c.a < 0.996:
					semi += 1
					continue
				if not pal.has(Color(c.r, c.g, c.b, 1.0).to_rgba32()):
					outside += 1
		t.check_eq(outside, 0, "%s: цвета вне палитры" % path.get_file())
		t.check_eq(semi, 0, "%s: полупрозрачные пиксели" % path.get_file())

static func _pngs(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if dir.current_is_dir():
			out.append_array(_pngs(dir_path.path_join(name) + "/"))
		elif name.ends_with(".png"):
			out.append(dir_path.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out
