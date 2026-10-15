shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

#include "res://LS5Framework/Shaders/adventure_water_surface.gdshaderinc"

void vertex() {
	local_position = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	if (top_only && local_normal.y < 0.99) { discard; }
	vec4 layer = water_layer(water_sample(local_position, normalize(local_normal)), VERTEX, NORMAL, VIEW, FRONT_FACING);
	ALBEDO = layer.rgb;
	ALPHA = layer.a;
}
