shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float edge_start = 0.12;
uniform float edge_end = 0.5;

void fragment() {
	float edge = 1.0 - smoothstep(edge_start, edge_end, length(UV - vec2(0.5)));
	COLOR.a *= edge;
}
