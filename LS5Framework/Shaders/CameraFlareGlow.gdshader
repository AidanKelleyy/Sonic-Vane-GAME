shader_type canvas_item;
render_mode unshaded, blend_add;

uniform float edge_start = 0.12;
uniform float edge_end = 0.5;

void fragment() {
	float edge = 1.0 - smoothstep(edge_start, edge_end, length(UV - vec2(0.5)));
	float border_distance = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	COLOR.a *= edge * smoothstep(0.0, 0.02, border_distance);
}
