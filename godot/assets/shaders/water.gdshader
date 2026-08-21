// TIDEBOUND — главный шейдер воды. Godot 4.7, canvas_item.
// Вешается на ColorRect размером во весь WorldViewport (640×360), лежащий
// на CanvasLayer ВНУТРИ WorldViewport (см. research/01-water-shader.md §3).
//
// Контракты:
//  - ВРЕМЯ: только global uniform `sim_time` (секунды симуляции). TIME запрещён —
//    он не останавливается на паузе (research/05-shader-time-and-pause.md).
//  - u_surface_y — экранный Y кромки воды В ПИКСЕЛЯХ ВЬЮПОРТА, уже округлённый
//    в GDScript. Шейдер его не пересчитывает.
//  - Все смещения задаются в пикселях 640×360, не в UV.

shader_type canvas_item;
render_mode blend_mix, unshaded;

global uniform float sim_time;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;

uniform vec2  u_view_size      = vec2(640.0, 360.0);
uniform float u_surface_y      = 200.0;  // px, экранный Y кромки (0 = верх экрана)

// --- цвет и глубина ---
uniform vec4  u_shallow : source_color = vec4(0.176, 0.420, 0.478, 0.40);
uniform vec4  u_deep    : source_color = vec4(0.102, 0.227, 0.290, 0.90);
uniform vec4  u_foam    : source_color = vec4(0.910, 0.960, 0.965, 1.00);
uniform float u_depth_range_px = 160.0;  // на какой глубине достигается u_deep

// --- волна поверхности (общая для пены, альфы, рефракции и отражения) ---
uniform float u_wave_amp_px  = 3.0;
uniform float u_wave_len_px  = 96.0;
uniform float u_wave_speed   = 10.0;   // px/сек дрейфа
uniform float u_quant_x_px   = 2.0;    // ступенька волны по X (пиксель-арт)
uniform float u_foam_px      = 2.0;

// --- рефракция ---
uniform float u_refract_px      = 3.0;
uniform float u_refract_fade_px = 40.0;  // на какой глубине рефракция выходит на полную

// --- отражение ---
uniform float u_reflect_alpha : hint_range(0.0, 1.0) = 0.20;
uniform float u_reflect_fade_px = 48.0;  // глубина, на которой отражение гаснет

// --- рябь/каустика у поверхности ---
uniform float u_caustics : hint_range(0.0, 0.5) = 0.08;

// --- шторм: 0..1, поднимает амплитуду и рефракцию (crisis_started(STORM)) ---
uniform float u_storm : hint_range(0.0, 1.0) = 0.0;

const float TAU_ = 6.28318530718;

// Высота поверхности относительно u_surface_y, в пикселях. Три несоизмеримых
// синуса с разными знаками скорости — чтобы не читалась периодичность.
float wave_height(float x, float amp) {
	float k = TAU_ / u_wave_len_px;
	float t = sim_time * u_wave_speed * k;
	float w = sin(x * k + t);
	w += 0.5  * sin(x * k * 2.17 - t * 1.6 + 1.3);
	w += 0.25 * sin(x * k * 0.41 + t * 0.7 + 2.7);
	return w * (amp / 1.75); // 1.75 = 1 + 0.5 + 0.25, нормировка
}

void fragment() {
	float amp     = u_wave_amp_px * (1.0 + 1.6 * u_storm);
	float px_x    = SCREEN_UV.x * u_view_size.x;
	float px_y    = SCREEN_UV.y * u_view_size.y;

	// Волна квантуется по X ступенькой и по Y до целого пикселя — иначе кромка
	// дрожит на полпикселя и весь пиксель-арт разваливается.
	float qx      = floor(px_x / u_quant_x_px) * u_quant_x_px;
	float surf_y  = floor(u_surface_y + wave_height(qx, amp) + 0.5);
	float depth   = px_y - surf_y;   // >0 = под водой

	if (depth < 0.0) {
		COLOR = vec4(0.0);           // над водой шейдер не рисует ничего
	} else {
		float surf_uv_y = surf_y / u_view_size.y;
		vec2  texel     = 1.0 / u_view_size;

		// ---------- рефракция ----------
		// Смещение НИКОГДА не тянет вверх (dy <= 0) и гаснет у самой кромки —
		// иначе вода подсасывает небо/скалу над собой (в 2D нет depth-буфера).
		float fade   = smoothstep(0.0, 1.0, clamp(depth / u_refract_fade_px, 0.0, 1.0));
		float ramp   = u_refract_px * (1.0 + 1.5 * u_storm) * fade;
		float dx     = sin(px_y * 0.25 + sim_time * 2.0) * ramp;
		float dy     = -abs(sin(px_x * 0.05 + sim_time * 1.3)) * ramp * 0.5;
		vec2  off    = floor(vec2(dx, dy) + 0.5);           // целые пиксели источника
		vec2  suv    = SCREEN_UV + off * texel;
		suv.y        = max(suv.y, surf_uv_y + texel.y);      // не сэмплить выше кромки
		suv          = clamp(suv, vec2(0.0), vec2(1.0) - texel);
		vec3  under  = textureLod(screen_tex, suv, 0.0).rgb;

		// ---------- отражение (зеркалим тот же бэкбуфер) ----------
		float roff_x = floor(wave_height(px_x + 37.0, amp) * 0.6 + 0.5);
		vec2  ruv    = vec2(SCREEN_UV.x + roff_x * texel.x, surf_uv_y - (SCREEN_UV.y - surf_uv_y));
		vec3  refl   = vec3(0.0);
		float rmask  = 0.0;
		// ruv.y < surf_uv_y обязательно: иначе отражение рекурсивно сэмплит саму воду
		if (ruv.y > 0.0 && ruv.y < surf_uv_y) {
			refl  = textureLod(screen_tex, clamp(ruv, vec2(0.0), vec2(1.0) - texel), 0.0).rgb;
			rmask = 1.0 - clamp(depth / u_reflect_fade_px, 0.0, 1.0);
		}

		// ---------- толща воды ----------
		vec4  tint = mix(u_shallow, u_deep, clamp(depth / u_depth_range_px, 0.0, 1.0));
		vec3  col  = mix(under, tint.rgb, tint.a);
		col = mix(col, refl, u_reflect_alpha * rmask);

		// ---------- рябь у поверхности ----------
		// Частоты высокие намеренно: на низкой рябь читается не как блики на
		// поверхности, а как гигантские светлые ленты через пол-экрана
		// (проверено скриншотом на уровне −8).
		float band  = sin(px_x * 0.19 - sim_time * 1.5 + sin(px_y * 0.27 + sim_time) * 2.0)
		            + 0.6 * sin(px_x * 0.07 + px_y * 0.11 + sim_time * 0.8);
		float caust = smoothstep(0.88, 1.0, band) * (1.0 - clamp(depth / 80.0, 0.0, 1.0));
		col += caust * u_caustics;

		// ---------- пена ----------
		// 1-й пиксель — яркий, дальше до u_foam_px — приглушённый.
		float foam_hi = 1.0 - step(1.0, depth);
		float foam_lo = (1.0 - step(u_foam_px, depth)) - foam_hi;
		col = mix(col, u_foam.rgb, foam_hi);
		col = mix(col, u_foam.rgb, foam_lo * 0.45);

		COLOR = vec4(col, 1.0);
	}
}
