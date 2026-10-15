#include "res://LS5Framework/Shaders/adventure_water_tiling.gdshaderinc"

uniform sampler2D surface_image : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
/** Mirror alternating image columns along texture X. */
uniform bool mirror_x = false;
/** Mirror alternating image rows along texture Y. */
uniform bool mirror_y = false;
uniform vec4 water_color : source_color = vec4(0.035, 0.43, 0.65, 1.0);
uniform vec4 wave_color : source_color = vec4(0.65, 0.94, 1.0, 1.0);
uniform float transparency : hint_range(0.0, 1.0) = 0.6;
uniform float wave_opacity : hint_range(0.0, 1.0) = 0.55;
uniform float highlight_threshold = 0.65;
uniform float highlight_softness = 0.3;
uniform vec4 view_angle_color : source_color = vec4(0.22, 0.36, 0.45, 1.0);
uniform float view_angle_strength = 0.35;
uniform float surface_detail_distance = 1200.0;
uniform vec2 tile_size = vec2(20.0);
uniform float texture_rotation = 0.0;
uniform vec2 scroll_offset = vec2(0.0);
uniform bool top_only = true;
uniform float refraction_strength = 0.055;
varying vec3 local_position;
varying vec3 local_normal;

vec3 water_sample(vec3 position, vec3 normal) {
	vec3 weights = pow(abs(normal), vec3(8.0));
	weights /= max(dot(weights, vec3(1.0)), 0.0001);
	float c = cos(texture_rotation);
	float s = sin(texture_rotation);
	mat2 rotation = mat2(vec2(c, s), vec2(-s, c));
	bvec2 mirror_axes = bvec2(mirror_x, mirror_y);
	vec3 result = vec3(0.0);
	if (weights.x > 0.0) { result += water_tiled_image(surface_image, rotation * (position.zy / tile_size) + scroll_offset, mirror_axes).rgb * weights.x; }
	if (weights.y > 0.0) { result += water_tiled_image(surface_image, rotation * (position.xz / tile_size) + scroll_offset, mirror_axes).rgb * weights.y; }
	if (weights.z > 0.0) { result += water_tiled_image(surface_image, rotation * (position.xy / tile_size) + scroll_offset, mirror_axes).rgb * weights.z; }
	return result;
}

vec4 water_layer(vec3 sample_color, vec3 position, vec3 normal, vec3 direction, bool front) {
	float grazing = pow(1.0 - clamp(abs(dot(normalize(normal), normalize(direction))), 0.0, 1.0), 5.0);
	float distance_fade = surface_detail_distance > 0.0 ? 1.0 - smoothstep(surface_detail_distance * 0.25, surface_detail_distance, length(position)) : 1.0;
	vec3 tile_position = local_position / vec3(tile_size.x, min(tile_size.x, tile_size.y), tile_size.y);
	float footprint = max(length(dFdx(tile_position)), length(dFdy(tile_position)));
	float detail = distance_fade * (1.0 - smoothstep(0.02, 0.15, footprint)) * mix(1.0, 0.25, grazing);
	float brightness = dot(pow(max(sample_color, vec3(0.0)), vec3(1.0 / 2.2)), vec3(0.2126, 0.7152, 0.0722));
	float highlight = smoothstep(highlight_threshold, highlight_threshold + max(highlight_softness, 0.001), brightness);
	float wave_alpha = highlight * wave_opacity * wave_color.a * detail;
	float base_alpha = (1.0 - transparency) * water_color.a;
	float alpha = wave_alpha + base_alpha * (1.0 - wave_alpha);
	vec3 color = wave_color.rgb * wave_alpha + water_color.rgb * base_alpha * (1.0 - wave_alpha);
	float reflection = front ? grazing * view_angle_strength : 0.0;
	color = color * (1.0 - reflection) + view_angle_color.rgb * reflection;
	alpha = alpha + reflection * (1.0 - alpha);
	return vec4(color / max(alpha, 0.0001), alpha);
}
