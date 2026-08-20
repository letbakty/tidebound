// TIDEBOUND — виньетка шторма + вспышка молнии.
//
// ГДЕ: ColorRect Full Rect на CanvasLayer в ГЛАВНОЙ сцене, СНАРУЖИ
//      WorldViewport — в нативном разрешении окна.
//      Рекомендованный слой: между PanelLayer(20) и BannerLayer(30),
//      т.е. новый WeatherLayer с layer = 25.
//
// ПОЧЕМУ СНАРУЖИ: виньетка — кинематографический эффект «объектива», а не
// часть пиксельного мира. Внутри 640×360 её градиент даёт грубый бандинг,
// снаружи — гладкий. Это же соответствует docs/01 §1.1: «screen-space шейдеры
// (вода, виньетка шторма) вешаются на SubViewportContainer или UI-слой».
//
// НЕ ЧИТАЕТ SCREEN TEXTURE. Затемнение краёв не требует знать, что под ними —
// достаточно нарисовать полупрозрачный градиент в blend_mix. Второй screen-read
// шейдер потребовал бы BackBufferCopy и сломал бы воду
// (research/00-godot-4.7-api-facts.md §3).
//
// unshaded обязателен: иначе PointLight2D осветят сам оверлей.

shader_type canvas_item;
render_mode unshaded, blend_mix;

global uniform float sim_time;

uniform float u_intensity : hint_range(0.0, 1.0) = 0.0;

uniform vec3  u_color : source_color = vec3(0.055, 0.102, 0.125); // #0e1a20
uniform float u_inner : hint_range(0.0, 1.0) = 0.35;
uniform float u_outer : hint_range(0.0, 1.5) = 0.95;
uniform float u_strength : hint_range(0.0, 1.0) = 0.55;
uniform float u_aspect = 1.7777778;   // ширина/высота окна, пишет GDScript на resize

// Лёгкая пульсация плотности — «порывы ветра». Малая амплитуда, иначе тошнит.
uniform float u_gust : hint_range(0.0, 0.5) = 0.12;

// Вспышка молнии: GDScript гонит твином 0 -> 1 -> 0 за ~0.15 с.
uniform float u_flash : hint_range(0.0, 1.0) = 0.0;
uniform vec3  u_flash_color : source_color = vec3(0.878, 0.937, 0.941);

void fragment() {
	vec4 acc = vec4(0.0);

	if (u_intensity > 0.001) {
		vec2 p = (UV - vec2(0.5)) * vec2(u_aspect, 1.0);
		float d = length(p) / length(vec2(u_aspect, 1.0) * 0.5);
		float v = smoothstep(u_inner, u_outer, d);
		float gust = 1.0 + u_gust * sin(sim_time * 0.7) * sin(sim_time * 0.23 + 1.7);
		acc = vec4(u_color, v * u_strength * u_intensity * gust);
	}

	if (u_flash > 0.001) {
		acc.rgb = mix(acc.rgb, u_flash_color, u_flash);
		acc.a = max(acc.a, u_flash * 0.55);
	}

	COLOR = acc;
}
