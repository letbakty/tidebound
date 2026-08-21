// TIDEBOUND — глубинный туман (промпт 18 п.1).
// Вертикальный градиент по МИРОВОМУ Y: наверху утёса тепло и светло,
// внизу в руинах холодно и темно. Главный приём «дорогой» картинки вместе
// с тёплым PointLight2D наверху.
//
// Вешается на ColorRect на CanvasLayer внутри WorldViewport, layer = 0 и
// z_index выше мира, ЛИБО (проще) на отдельный CanvasLayer layer = 0..1,
// но СТРОГО НИЖЕ WaterLayer — иначе вода не будет тонировать то, что под ней.
//
// Порядок: World (layer 0) → DepthFog (layer 1) → Water (layer 2).
//
// НЕ читает screen texture — это просто прозрачный градиент поверх мира.
// Значит бэкбуфер не трогает и BackBufferCopy не провоцирует.

shader_type canvas_item;
render_mode blend_mix, unshaded;

// Экранные Y (в пикселях вьюпорта) двух опорных отметок. Пишет GDScript
// каждый кадр из canvas_transform — так туман привязан к миру, а не к экрану,
// и не «плывёт» при панораме камеры.
uniform float u_top_y    = 0.0;     // экранный Y отметки +6 (верх утёса)
uniform float u_bottom_y = 360.0;   // экранный Y отметки -8 (дно руин)

uniform vec4  u_warm : source_color = vec4(0.784, 0.631, 0.369, 0.00); // #c9a15e, наверху почти нет
uniform vec4  u_cold : source_color = vec4(0.102, 0.227, 0.290, 0.55); // #1a3a4a, внизу плотно

// Кривая: 1.0 = линейно, >1 = туман собирается у дна, <1 = размазан.
uniform float u_curve : hint_range(0.25, 4.0) = 1.6;

// Ступенчатость градиента — против бандинга и ради пиксельного вида.
// 0 = гладко. 12..16 полос выглядят как осознанный приём, а не как артефакт.
uniform float u_bands : hint_range(0.0, 32.0) = 14.0;

uniform vec2  u_view_size = vec2(640.0, 360.0);

void fragment() {
	float px_y = SCREEN_UV.y * u_view_size.y;
	float t = clamp((px_y - u_top_y) / max(1.0, u_bottom_y - u_top_y), 0.0, 1.0);
	t = pow(t, u_curve);

	if (u_bands > 0.5) {
		t = floor(t * u_bands) / u_bands;
	}

	COLOR = mix(u_warm, u_cold, t);
}
