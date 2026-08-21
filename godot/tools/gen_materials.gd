extends SceneTree
## Материалы шейдеров этапа 18.
##   godot --headless -s res://tools/gen_materials.gd
##
## Генератором, а не кликами в редакторе: значения должны переживать
## пересоздание сцены и читаться в диффе. Художник правит их в инспекторе —
## тогда правку надо перенести сюда, иначе следующая перегенерация её сотрёт.
##
## РЕШЕНИЕ: числа воды, тумана и дождя — визуальные, а не игровые, поэтому
## живут здесь и в .tres, а не в sim/balance.gd (CONVENTIONS: в Balance —
## игровые числа). Цвета взяты из палитры docs/01 §4.

const DIR: String = "res://assets/shaders/"

## Стартовые значения — таблица research/01 §7 (вода) и research/02 (туман).
const MATERIALS: Dictionary = {
	"water": {
		"u_view_size": Vector2(640.0, 360.0),
		"u_surface_y": 200.0,
		"u_shallow": Color("2d6b7a", 0.40),
		# 0.72, а не 0.90 из таблицы research/01 §7: при 0.90 затопленный ярус
		# превращается в ровное поле, а под водой продолжается игра — видно
		# должно быть и постройки, и тонущего агента (проверено скриншотом).
		"u_deep": Color("1a3a4a", 0.72),
		"u_foam": Color("e8eff0", 1.0),
		"u_depth_range_px": 160.0,
		"u_wave_amp_px": 3.0,
		"u_wave_len_px": 96.0,
		"u_wave_speed": 10.0,
		"u_quant_x_px": 2.0,
		"u_foam_px": 2.0,
		"u_refract_px": 3.0,
		"u_refract_fade_px": 40.0,
		"u_reflect_alpha": 0.20,
		"u_reflect_fade_px": 48.0,
		"u_caustics": 0.05,
		"u_storm": 0.0,
	},
	"depth_fog": {
		"u_top_y": 0.0,
		"u_bottom_y": 360.0,
		# Наверху тумана почти нет (альфа 0), внизу — плотный холод.
		"u_warm": Color("c9a15e", 0.0),
		# 0.42, а не 0.55: вместе с толщей воды дно уходило в чёрное поле,
		# а на дне идёт вся добыча — читаться оно обязано.
		"u_cold": Color("1a3a4a", 0.42),
		"u_curve": 1.6,
		"u_bands": 14.0,
		"u_view_size": Vector2(640.0, 360.0),
	},
	"rain": {
		"u_intensity": 0.0,
		"u_tint": Color(0.72, 0.80, 0.95, 1.0),
		"u_alpha": 0.55,
		"u_speed": Vector2(0.15, 1.4),
		"u_tiling": 6.0,
		"u_view_size": Vector2(640.0, 360.0),
	},
	"vignette": {
		"u_intensity": 0.0,
		"u_color": Color("0e1a20"),
		"u_inner": 0.35,
		"u_outer": 0.95,
		"u_strength": 0.55,
		"u_aspect": 16.0 / 9.0,
		"u_gust": 0.12,
		"u_flash": 0.0,
		"u_flash_color": Color("e0eff0"),
	},
	"wet_tiles": {
		"u_wet_world_y": 99999.0,
		"u_wet_amount": 1.0,
		"u_wet_tint": Color("1a3a4a", 1.0),
		"u_darken": 0.30,
		"u_sheen": 0.07,
		"u_edge_px": 8.0,
	},
	"sprite_lit": {
		"u_light_px": 1.0,
	},
}

func _initialize() -> void:
	var written: int = 0
	for name: String in MATERIALS:
		var shader_path: String = DIR + name + ".gdshader"
		var sh: Shader = load(shader_path) as Shader
		if sh == null:
			push_error("gen_materials: нет шейдера %s" % shader_path)
			continue
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = sh
		var params: Dictionary = MATERIALS[name] as Dictionary
		for key: String in params:
			mat.set_shader_parameter(StringName(key), params[key])
		var out: String = DIR + name + "_material.tres"
		var err: Error = ResourceSaver.save(mat, out)
		if err != OK:
			push_error("gen_materials: %s не сохранён, ошибка %d" % [out, err])
			continue
		written += 1
	# Общая текстура света: одна на все светильники — меньше смен состояния
	# на GPU (research/02 §2). Радиальный градиент, а не PNG: рисовать нечего.
	var grad: Gradient = Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.35),
		Color(1, 1, 1, 0)])
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	if ResourceSaver.save(tex, DIR + "light_glow.tres") == OK:
		written += 1
	print("материалы записаны: %d" % written)
	quit(0 if written == MATERIALS.size() + 1 else 1)
