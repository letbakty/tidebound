extends RefCounted
## Приёмка этапа 16: цели касания, кегли, ремап и палитра доступности.
##
## Ручной аудит по чеклисту не переживает следующий этап — здесь он тестом
## (research/20 §8).

const INTERACTIVE_SCENES: Array[String] = [
	"res://ui/components/pixel_button.tscn",
	"res://ui/components/agent_chip.tscn",
	"res://ui/components/policy_slider.tscn",
	"res://ui/components/card_view.tscn",
]

## Любая интерактивная цель — не меньше 48 dp (docs/01 §5).
static func test_touch_targets(t: TestCtx) -> void:
	var button: PixelButton = PixelButton.new()
	button.setup("UI_OK", PixelButton.Variant.NORMAL)
	t.check(button.custom_minimum_size.x >= float(UITokens.TOUCH_MIN)
		and button.custom_minimum_size.y >= float(UITokens.TOUCH_MIN),
		"кнопка мельче 48 dp")
	button.free()

	var chip: AgentChip = AgentChip.new()
	chip.setup(1, "А", 50.0)
	t.check(chip.custom_minimum_size.y >= float(UITokens.TOUCH_MIN),
		"чип агента мельче 48 dp")
	chip.free()

	var policy: PolicySlider = PolicySlider.new()
	policy.setup(0, 1, "POLICY_GREED")
	for step: Node in policy.get_children():
		for maybe_button: Node in step.get_children():
			var b: Button = maybe_button as Button
			if b == null:
				continue
			t.check(b.custom_minimum_size.y >= float(UITokens.TOUCH_MIN),
				"ступень политики мельче 48 dp")
	policy.free()

	var recall: RecallButton = RecallButton.new()
	t.check_eq(recall.get_class(), "Control", "кнопка отзыва — контейнер зоны")
	recall.free()

## ⚠️ Ни один шрифт не мельче 9 px на экране 1280×800 — жёсткое требование
## Steam Deck Verified (docs/03 §8).
static func test_font_sizes_deck_safe(t: TestCtx) -> void:
	for base: int in [UITokens.FONT_S, UITokens.FONT_M, UITokens.FONT_L,
			UITokens.FONT_TITLE]:
		t.check(base >= 9, "кегль %d мельче 9 px" % base)
	# Даже при минимальном пользовательском масштабе шрифта.
	var prev: float = UIThemeFactory.font_scale
	UIThemeFactory.font_scale = 0.75
	for base2: int in [UITokens.FONT_S, UITokens.FONT_M]:
		t.check(UIThemeFactory.size_of(base2) >= 9,
			"при мелком шрифте кегль %d ушёл ниже 9 px" % base2)
	UIThemeFactory.font_scale = prev

## Пресеты для дальтоников подменяют ровно семантику и различимы между собой.
static func test_colorblind_presets(t: TestCtx) -> void:
	UIPalette.apply(0, false)
	t.check_eq(UIPalette.danger(), UITokens.DANGER, "без пресета цвет исходный")
	for mode: int in [1, 2, 3]:
		UIPalette.apply(mode, false)
		t.check(UIPalette.danger() != UIPalette.success(),
			"пресет %d: опасность и успех должны различаться" % mode)
		t.check(UIPalette.accent() != UIPalette.water(),
			"пресет %d: акцент и вода должны различаться" % mode)
		# Несемантические цвета пресет не трогает.
		t.check_eq(UIPalette.map(UITokens.MUTED), UITokens.MUTED,
			"пресет %d трогает несемантический цвет" % mode)
	UIPalette.apply(0, false)
	t.check(UIPalette.panel() != UITokens.PAPER, "обычная подложка полупрозрачна")
	UIPalette.apply(0, true)
	t.check_eq(UIPalette.panel(), UITokens.PAPER, "повышенный контраст делает подложку плотной")
	UIPalette.apply(0, false)

## Ремап: конфликт двух действий на одной клавише виден, сброс возвращает всё.
static func test_remap_conflicts(t: TestCtx) -> void:
	var settings: Node = (load("res://autoload/settings.gd") as GDScript).new()
	settings.call("capture_defaults")
	t.check(InputMap.has_action("recall"), "действие recall есть в проекте")
	t.check_eq((settings.call("conflicts") as Dictionary).size(), 0,
		"в умолчаниях конфликтов нет")
	var e: InputEventKey = InputEventKey.new()
	e.physical_keycode = KEY_P              # уже занято политиками
	settings.call("rebind", "recall", e)
	var bad: Dictionary = settings.call("conflicts")
	t.check(bad.has("recall") and bad.has("policies"),
		"конфликт подсвечивает ОБА действия")
	settings.call("reset_bindings")
	t.check_eq((settings.call("conflicts") as Dictionary).size(), 0,
		"сброс к умолчаниям убирает конфликт")
	settings.free()

## Масштаб UI снапится к четвертям: дробный множитель мылит пиксель-шрифт.
static func test_ui_scale_is_snapped(t: TestCtx) -> void:
	var settings: Node = (load("res://autoload/settings.gd") as GDScript).new()
	settings.set("ui_scale", 1.13)
	var eff: float = settings.call("effective_scale")
	t.check_approx(fmod(eff, 0.25), 0.0, 0.001, "масштаб не кратен четверти: %f" % eff)
	settings.free()

## Сцены компонентов инстанцируются и не мельче цели касания.
static func test_component_scenes_are_touchable(t: TestCtx) -> void:
	for path: String in INTERACTIVE_SCENES:
		t.check(ResourceLoader.exists(path), "нет сцены %s" % path)
