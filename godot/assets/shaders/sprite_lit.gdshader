// TIDEBOUND — базовый материал для спрайтов и тайлмапов мира,
// освещаемых PointLight2D (промпт 18 п.2).
//
// ЗАЧЕМ: документация Godot прямо предупреждает — «Nearest texture filtering
// will not achieve pixelated lighting». Свет считается в непрерывных
// координатах, поэтому пятно света имеет гладкий градиент и разрушает
// пиксельную сетку. Лечится снапом LIGHT_VERTEX/SHADOW_VERTEX.
//
// У нас мир рендерится в 640×360, то есть внутренний пиксель = 1.0, и
// u_light_px = 1.0. Значение 2.0 даёт нарочито грубый ретро-свет — вопрос вкуса,
// решается на этапе 18 глазами.
//
// В Godot 4 CanvasItem освещается ПО УМОЛЧАНИЮ. `render_mode unshaded` —
// это opt-OUT. Поэтому здесь unshaded НЕТ (в отличие от оверлеев).

shader_type canvas_item;

uniform float u_light_px : hint_range(1.0, 8.0) = 1.0;

void fragment() {
	// Снап освещения и теней на пиксельную сетку мира.
	LIGHT_VERTEX.xy = floor(LIGHT_VERTEX.xy / u_light_px) * u_light_px;
	SHADOW_VERTEX = floor(SHADOW_VERTEX / u_light_px) * u_light_px;
	// ⚠️ COLOR трогать не надо: на входе он УЖЕ texture(TEXTURE, UV) * modulate.
	// Строка `COLOR = texture(TEXTURE, UV) * COLOR` возводила спрайт в квадрат —
	// та же ошибка, что жила в wet_tiles. Здесь она ещё не выстрелила только
	// потому, что материал пока никому не назначен.
}
