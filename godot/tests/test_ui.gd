extends RefCounted
## Тесты UI-фундамента (этап 12): токены, тема, компоненты, ключи локализации.
##
## Проверки — через ctx.check, а не assert: assert вырезается в release-сборке
## и «зелёный» прогон экспорта ничего не проверял бы (CONVENTIONS).

const COMPONENT_SCENES: Array[String] = [
	"res://ui/components/pixel_button.tscn",
	"res://ui/components/pixel_panel.tscn",
	"res://ui/components/resource_chip.tscn",
	"res://ui/components/policy_slider.tscn",
	"res://ui/components/agent_chip.tscn",
	"res://ui/components/card_view.tscn",
	"res://ui/components/radial_menu.tscn",
	"res://ui/components/tooltip_view.tscn",
	"res://ui/components/toast.tscn",
	"res://ui/components/banner_view.tscn",
	"res://ui/components/confirm_dialog.tscn",
]

## Компонент не смеет знать об игре — это приёмка промпта 12.
const FORBIDDEN_IN_COMPONENTS: Array[String] = ["Game.", "Events.", "SimWorld", "Meta.", "Settings."]

static func test_tokens(t: TestCtx) -> void:
	t.check(UITokens.TOUCH_MIN >= 48, "цель касания < 48 dp")
	t.check(UITokens.TOUCH_GAP >= 8, "зазор между целями < 8 dp")
	t.check_eq(UITokens.SPACE_1, 4, "шкала отступов начинается с 4")
	t.check(UITokens.SPACE_2 == 8 and UITokens.SPACE_3 == 12
		and UITokens.SPACE_4 == 16 and UITokens.SPACE_5 == 24, "шкала отступов 4/8/12/16/24")
	for size: int in [UITokens.FONT_S, UITokens.FONT_M, UITokens.FONT_L, UITokens.FONT_TITLE]:
		# Кегль, не кратный базовым 8, мылит независимо от настроек импорта.
		t.check(size % 8 == 0, "кегль %d не кратен 8" % size)
		# Требование Steam Deck Verified: ни один шрифт мельче 9 px.
		t.check(size >= 9, "кегль %d мельче 9 px (Steam Deck)" % size)
	var palette: Array[Color] = [UITokens.PAPER, UITokens.PANEL_BG, UITokens.RAISE,
		UITokens.BORDER, UITokens.BORDER_STRONG, UITokens.DIVIDER, UITokens.INK,
		UITokens.MUTED, UITokens.FAINT, UITokens.ACCENT, UITokens.ACCENT_SHADE,
		UITokens.DANGER, UITokens.SUCCESS, UITokens.WATER_COLD, UITokens.COLD_DEEP,
		UITokens.WARM]
	t.check_eq(palette.size(), 16, "в палитре ровно 16 цветов (кит, артборд A)")
	var seen: Dictionary[String, bool] = {}
	for c: Color in palette:
		var key: String = c.to_html(false)
		t.check(not seen.has(key), "цвет %s повторяется в палитре" % key)
		seen[key] = true
	t.check_eq(UITokens.trend_color(1), UITokens.SUCCESS, "рост — зелёным")
	t.check_eq(UITokens.trend_color(-1), UITokens.DANGER, "падение — красным")
	t.check_eq(UITokens.need_color(10.0), UITokens.DANGER, "потребность <30 — тревога")

static func test_theme_resource(t: TestCtx) -> void:
	t.check(ResourceLoader.exists(UIThemeFactory.OUT_PATH),
		"нет собранной темы — запусти tools/gen_theme.gd")
	var th: Theme = load(UIThemeFactory.OUT_PATH) as Theme
	if th == null:
		t.check(false, "тема не грузится")
		return
	t.check(th.default_font != null, "в теме нет шрифта по умолчанию")
	t.check_eq(th.default_font_size, UITokens.FONT_S, "кегль по умолчанию из токенов")
	for name: String in UIThemeFactory.VARIATIONS:
		t.check_eq(str(th.get_type_variation_base(name)),
			UIThemeFactory.VARIATIONS[name], "вариация %s объявлена от своего типа" % name)
	# Фокус — отдельный stylebox поверх обычного, иначе геймпадом не пройти.
	t.check(th.has_stylebox("focus", "Button"), "у кнопки нет стиля фокуса")
	var focus: StyleBoxFlat = th.get_stylebox("focus", "Button") as StyleBoxFlat
	t.check(focus != null and focus.border_color == UITokens.ACCENT,
		"рамка фокуса не акцентного цвета")
	# Скругления и сглаживание в пиксель-арте = грязь на кромках.
	for type_name: String in th.get_stylebox_type_list():
		for item: String in th.get_stylebox_list(type_name):
			var sb: StyleBoxFlat = th.get_stylebox(item, type_name) as StyleBoxFlat
			if sb == null:
				continue
			t.check(not sb.anti_aliasing, "%s/%s: включено сглаживание" % [type_name, item])
			t.check_eq(sb.corner_radius_top_left, UITokens.RADIUS_MAX,
				"%s/%s: скругление угла" % [type_name, item])

## Тема пересобирается из токенов: значение поменялось — стиль поменялся,
## сцены при этом не трогаются.
static func test_theme_is_rebuilt_from_tokens(t: TestCtx) -> void:
	var th: Theme = UIThemeFactory.build()
	var panel: StyleBox = th.get_stylebox("panel", "PanelContainer")
	t.check(panel != null, "PanelContainer без стиля")
	if panel == null:
		return
	# Скин выбирается одной константой (этап 18), и проверять надо тот, который
	# собран: в атласном панель приходит текстурой, в плоском — заливкой.
	if UIThemeFactory.USE_ATLAS:
		var tex: StyleBoxTexture = panel as StyleBoxTexture
		t.check(tex != null, "в атласном скине панель — StyleBoxTexture")
		if tex != null:
			t.check_eq(tex.texture_margin_left, float(UIThemeFactory.ATLAS_MARGIN),
				"поле 9-patch — из константы атласа")
			t.check_eq(tex.region_rect.size.x, float(UIThemeFactory.ATLAS_CELL),
				"кадр атласа целиком")
	else:
		var flat: StyleBoxFlat = panel as StyleBoxFlat
		t.check(flat != null, "в плоском скине панель — StyleBoxFlat")
		if flat != null:
			t.check_eq(flat.border_color, UITokens.BORDER,
				"кромка панели — из токена BORDER")
			t.check_eq(flat.border_width_left, UITokens.BORDER_W,
				"толщина кромки — из токена")
	# Акцентная кнопка остаётся плоской В ЛЮБОМ скине: её цвет зависит от
	# пресета для дальтоников, а кадр атласа запечён (см. ATLAS_FRAMES).
	var primary: StyleBoxFlat = th.get_stylebox("normal", "ButtonPrimary") as StyleBoxFlat
	t.check(primary != null and primary.bg_color == UITokens.ACCENT,
		"главная кнопка — акцентом из токена")

static func test_components_instantiate(t: TestCtx) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for path: String in COMPONENT_SCENES:
		if not ResourceLoader.exists(path):
			t.check(false, "нет сцены компонента %s" % path)
			continue
		var scene: PackedScene = load(path) as PackedScene
		var node: Control = scene.instantiate() as Control
		t.check(node != null, "%s: корень не Control" % path)
		if node == null:
			continue
		tree.root.add_child(node)
		t.check(node.has_method("setup") or node is PixelButton,
			"%s: нет типизированного setup()" % path)
		node.queue_free()

static func test_component_states(t: TestCtx) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var chip: ResourceChip = ResourceChip.new()
	tree.root.add_child(chip)
	chip.setup("rations", 0, -1)
	t.check_eq(chip.item_id, "rations", "чип помнит предмет")

	var agent: AgentChip = AgentChip.new()
	tree.root.add_child(agent)
	agent.setup(7, "Т", 12.0)
	t.check_eq(agent.agent_id, 7, "чип агента помнит id")
	t.check(agent.custom_minimum_size.x >= float(UITokens.TOUCH_MIN),
		"чип агента мельче цели касания")
	t.check_eq(agent.focus_mode, Control.FOCUS_ALL, "чип агента вне навигации фокусом")

	var policy: PolicySlider = PolicySlider.new()
	tree.root.add_child(policy)
	var picked: Array[int] = []
	policy.value_picked.connect(func(_p: int, v: int) -> void: picked.append(v))
	policy.setup(1, 2, "POLICY_CAUTION", func(_p: int, v: int) -> String: return "v%d" % v)
	t.check_eq(policy.value, 2, "ползунок принял текущее значение")
	policy.set_value(3)
	t.check(picked.is_empty(), "внешнее обновление не должно эмитить сигнал обратно")

	var card: CardView = CardView.new()
	tree.root.add_child(card)
	card.setup("great_ebb", "CARD_GREAT_EBB", "CARD_GREAT_EBB_D", true)
	card.set_selected(true)
	t.check(card.is_selected(), "карта не запомнила выделение")

	var toast: Toast = Toast.new()
	tree.root.add_child(toast)
	toast.setup("текст", Toast.Tone.WARN, Vector2i(3, 4), 0.0)
	toast.set_count(3)
	t.check_eq(toast.count(), 3, "тост не сгруппировался")
	t.check_eq(toast.cell, Vector2i(3, 4), "тост не помнит клетку события")

	for n: Node in [chip, agent, policy, card, toast]:
		n.queue_free()

## Радиал: та же формула сектора, что в бою. Верхний-левый сектор — главная
## ловушка (fmod вместо fposmod даёт −1).
static func test_radial_sectors(t: TestCtx) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var radial: RadialMenu = RadialMenu.new()
	tree.root.add_child(radial)
	var slots: Array[Dictionary] = []
	for i: int in 4:
		slots.append({"label": "GALLERY_SLOT", "letter": str(i), "enabled": true})
	var center: Vector2 = Vector2(200.0, 200.0)
	radial.open_at(center, slots, true)
	var r: float = RadialMenu.RADIUS
	t.check_eq(radial.call("_sector_at", center + Vector2(r, -r) * 0.7), 0,
		"верх-право — сектор 0")
	t.check_eq(radial.call("_sector_at", center + Vector2(r, r) * 0.7), 1,
		"низ-право — сектор 1")
	t.check_eq(radial.call("_sector_at", center + Vector2(-r, r) * 0.7), 2,
		"низ-лево — сектор 2")
	t.check_eq(radial.call("_sector_at", center + Vector2(-r, -r) * 0.7), 3,
		"верх-лево — сектор 3 (fposmod, а не fmod)")
	t.check_eq(radial.call("_sector_at", center), -1, "центр — мёртвая зона")
	t.check_eq(radial.call("_sector_at", center + Vector2(1000.0, 0.0)), -1,
		"за внешней границей выбора нет")
	var got: Array[int] = []
	radial.slot_picked.connect(func(i: int) -> void: got.append(i))
	radial.call("_release", center + Vector2(0.0, -r))
	t.check_eq(got.size(), 1, "увод пальца вверх и отпускание выбирают слот")
	t.check(not radial.is_open(), "радиал не закрылся после выбора")
	radial.queue_free()

## InputService — нода, а не автолоад: автолоад получал бы _input раньше GUI
## и ел бы события у панелей (research/19 §7).
static func test_input_service_is_node(t: TestCtx) -> void:
	var svc: InputService = InputService.new()
	t.check(svc is Node, "InputService должен быть нодой")
	t.check(not ProjectSettings.has_setting("autoload/InputService"),
		"InputService не должен быть автолоадом")
	var names: Array[String] = ["world_tapped", "world_double_tapped",
		"world_long_pressed", "long_press_progress", "world_dragged",
		"zoom_step", "edge_swipe_right", "device_changed"]
	for n: String in names:
		t.check(svc.has_signal(n), "InputService без сигнала %s" % n)
	svc.free()

## Компоненты не обращаются к игре — иначе их нельзя ни переиспользовать,
## ни показать в витрине.
static func test_components_are_pure(t: TestCtx) -> void:
	for path: String in _gd_files("res://ui/components/"):
		var src: String = FileAccess.get_file_as_string(path)
		for needle: String in FORBIDDEN_IN_COMPONENTS:
			if path.ends_with("_gallery.gd"):
				continue           # витрина — не компонент, ей можно локаль
			t.check(not src.contains(needle),
				"%s обращается к %s" % [path.get_file(), needle])

## Сырых ключей на экране быть не должно: tr() возвращает сам ключ, если его
## нет в CSV (research/22 §3.1).
static func test_ui_keys_exist(t: TestCtx) -> void:
	var known: Dictionary[String, bool] = _csv_keys()
	t.check(known.size() > 100, "не прочитался assets/i18n/strings.csv")
	var re: RegEx = RegEx.new()
	re.compile('"([A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+)"')
	var checked: int = 0
	for path: String in _gd_files("res://ui/"):
		var src: String = FileAccess.get_file_as_string(path)
		for m: RegExMatch in re.search_all(src):
			var key: String = m.get_string(1)
			if key.begins_with("MOUSE_") or key.begins_with("AUTOWRAP_"):
				continue
			checked += 1
			t.check(known.has(key), "%s: ключа %s нет в strings.csv" % [path.get_file(), key])
	t.check(checked > 10, "ключи локализации в ui/ не нашлись — проверь регулярку")

## ⚠️ Незакавыченная запятая в русской строке рвёт CSV: значение обрезается
## по запятой, а хвост уезжает в английскую колонку. На экране это выглядит
## как оборванная фраза — так пропала половина биографий агентов.
static func test_csv_is_well_formed(t: TestCtx) -> void:
	var f: FileAccess = FileAccess.open("res://assets/i18n/strings.csv", FileAccess.READ)
	if f == null:
		t.check(false, "не открылся strings.csv")
		return
	var seen: Dictionary[String, bool] = {}
	var line_no: int = 0
	while not f.eof_reached():
		var row: PackedStringArray = f.get_csv_line()
		line_no += 1
		if row.size() == 1 and row[0].is_empty():
			continue                       # хвостовая пустая строка
		t.check_eq(row.size(), 3, "строка %d: колонок должно быть три (%s)"
			% [line_no, row[0]])
		if row.size() < 3:
			continue
		if line_no == 1:
			continue                       # заголовок keys,ru,en
		t.check(not seen.has(row[0]), "ключ %s повторяется" % row[0])
		seen[row[0]] = true
		t.check(not row[1].strip_edges().is_empty(), "%s: пустой русский текст" % row[0])
		t.check(not row[2].strip_edges().is_empty(), "%s: пустой английский текст" % row[0])
	f.close()
	t.check(seen.size() > 300, "ключей подозрительно мало: %d" % seen.size())

# --- Утилиты --------------------------------------------------------------

static func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while not name.is_empty():
		var full: String = dir_path.path_join(name)
		if dir.current_is_dir():
			out.append_array(_gd_files(full))
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out

static func _csv_keys() -> Dictionary[String, bool]:
	var out: Dictionary[String, bool] = {}
	var f: FileAccess = FileAccess.open("res://assets/i18n/strings.csv", FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line: PackedStringArray = f.get_csv_line()
		if line.size() > 0 and not line[0].is_empty():
			out[line[0]] = true
	f.close()
	return out
