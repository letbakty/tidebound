// TIDEBOUND — мокрые тайлы (промпт 18 п.5, правило docs/00 §5:
// «после ухода воды тайлы, побывавшие под водой, помечаются мокрыми на 1 цикл»).
//
// Вешается материалом на TileMapLayer Ground (и при желании на Ladders).
// Граница «мокрого» задаётся в МИРОВЫХ координатах, а не экранных — поэтому
// мировой Y тянем через varying из vertex(). В fragment() CANVAS_MATRIX
// недоступен (см. research/00-godot-4.7-api-facts.md §2), это частая ошибка.
//
// u_wet_world_y — мировой Y последнего максимума воды за прошлый цикл.
// Всё НИЖЕ него (y больше) — мокрое.

shader_type canvas_item;
render_mode blend_mix;

global uniform float sim_time;

varying float v_world_y;
varying float v_world_x;

uniform float u_wet_world_y = 99999.0;               // 99999 = сухо везде
uniform float u_wet_amount : hint_range(0.0, 1.0) = 1.0;  // гаснет к концу цикла
uniform vec4  u_wet_tint : source_color = vec4(0.102, 0.227, 0.290, 1.0);
uniform float u_darken : hint_range(0.0, 1.0) = 0.35;
uniform float u_sheen  : hint_range(0.0, 1.0) = 0.22;  // блик
uniform float u_edge_px = 8.0;                          // мягкость границы, мировые px

void vertex() {
	vec2 w = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	v_world_x = w.x;
	v_world_y = w.y;
}

void fragment() {
	// ⚠️ COLOR на входе — это УЖЕ texture(TEXTURE, UV) * modulate (док Godot 4.7,
	// canvas_item, встроенные fragment). Здесь стояло `texture(TEXTURE, UV)` и
	// в конце `COLOR = tex * COLOR` — то есть цвет тайла возводился в КВАДРАТ:
	// #c9a15e приезжал на экран как #9e6623, весь Ground был на 40% темнее и
	// заметно кислотнее. На однотонных заглушках это читалось как «атмосферно».
	vec4 tex = COLOR;

	float wet = smoothstep(u_wet_world_y - u_edge_px, u_wet_world_y + u_edge_px, v_world_y);
	wet *= u_wet_amount;

	if (wet > 0.001) {
		vec3 col = tex.rgb;
		// затемнение + сдвиг в холод
		col = mix(col, mix(col * (1.0 - u_darken), u_wet_tint.rgb, 0.35), wet);
		// Узкий медленный блик — «ещё блестит». Частоты высокие и полоса
		// узкая намеренно: на низкой частоте блик читается не как влага,
		// а как диагональные полосы поверх всего утёса (проверено скриншотом).
		float sh = sin(v_world_x * 0.31 + v_world_y * 0.52 - sim_time * 0.6);
		sh = smoothstep(0.965, 1.0, sh);
		col += sh * u_sheen * wet;
		tex.rgb = col;
	}

	COLOR = tex;
}
