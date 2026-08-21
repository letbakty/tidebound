class_name CreditsScreen
extends ScreenBase
## Титры (docs/03 §3.7). Лицензии шрифтов указаны не из вежливости: OFL и CC0
## ТРЕБУЮТ указания — это юридическая обязанность.

func _ready() -> void:
	super()
	set_title("CREDITS_TITLE")
	_build_credits()

func _build_credits() -> void:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	for key: String in ["CREDITS_DEV", "CREDITS_FONTS", "CREDITS_FONTS_LIC",
			"CREDITS_ENGINE", "CREDITS_SOUND", "CREDITS_TESTERS"]:
		var label: Label = Label.new()
		UILayout.wrap(label, 560.0)
		label.text = key
		box.add_child(label)
