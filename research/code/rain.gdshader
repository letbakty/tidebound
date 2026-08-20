// TIDEBOUND — дождь шторма (промпт 18 п.6, docs/00 §9.4).
//
// ГДЕ: ColorRect 640×360 на CanvasLayer ВНУТРИ WorldViewport
//      (layer = 5, follow_viewport_enabled = false, размер = вьюпорт).
//      Внутри — чтобы дождь пикселизовался вместе с миром и попал под апскейл.
//
// ПОЧЕМУ ШЕЙДЕР, А НЕ GPUParticles2D: полноэкранный ливень партиклами — это
// тысячи частиц и весь бюджет 30 fps на среднем Android. Здесь 1 draw call,
// 0 CPU. Партиклы оставляем на точечные эффекты (брызги, пар) — см.
// research/04-weather-particles-vignette.md.
//
// ВРЕМЯ: global uniform sim_time, не TIME — дождь замирает на паузе.

shader_type canvas_item;
render_mode unshaded, blend_mix;

global uniform float sim_time;

uniform float u_intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4  u_tint : source_color = vec4(0.72, 0.80, 0.95, 1.0);
uniform float u_alpha : hint_range(0.0, 1.0) = 0.55;
uniform vec2  u_speed = vec2(0.15, 1.4);   // наклон и скорость падения
uniform float u_tiling = 6.0;
uniform vec2  u_view_size = vec2(640.0, 360.0);

// Процедурная генерация — чтобы не заводить ассет-текстуру раньше времени.
// Когда художник нарисует rain_tile.png 64×64, заменить hash-функцию на
// texture(rain_tex, uv).r с filter_nearest, repeat_enable — вид станет лучше.
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float rain_layer(vec2 uv, float scale, float speed_mul, float seed) {
	vec2 cell = vec2(uv.x * u_view_size.x / scale, uv.y * u_view_size.y / (scale * 4.0));
	float col_id = floor(cell.x);
	float phase = hash21(vec2(col_id, seed));
	float y = fract(cell.y - sim_time * u_speed.y * speed_mul * (0.7 + phase * 0.6) - phase);
	float x = fract(cell.x);
	float streak = (1.0 - smoothstep(0.05, 0.28, abs(x - 0.5)))
	             * smoothstep(0.70, 1.0, y);
	// не в каждой колонке и не всегда — иначе получается решётка
	streak *= step(0.45, hash21(vec2(col_id, floor(cell.y) + seed)));
	return streak;
}

void fragment() {
	// Нулевая стоимость в ясную погоду: оверлей висит в сцене всегда,
	// но в ясный цикл не пишет ни одного пикселя.
	if (u_intensity <= 0.001) {
		discard;
	}

	vec2 uv = UV;
	uv.x += uv.y * u_speed.x;

	float near_l = rain_layer(uv, u_tiling, 1.0, 0.0);
	float far_l  = rain_layer(uv * 1.7 + vec2(0.37, 0.0), u_tiling, 0.65, 11.0);

	float drops = max(near_l, far_l * 0.55);
	COLOR = vec4(u_tint.rgb, drops * u_alpha * u_intensity);
}
