shader_type spatial;
render_mode unshaded, blend_add, cull_front, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://LS5Framework/Shaders/adventure_water_tiling.gdshaderinc"

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D caustic_image : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler3D occupancy : filter_nearest, repeat_disable;
uniform bool has_occupancy = false;
uniform mat4 world_to_volume;
uniform vec3 bounds_min;
uniform vec3 bounds_size;
uniform int geometry_kind = 0;
uniform vec2 tile_size = vec2(20.0);
/** Caustic scrolling offset in image tiles. */
uniform vec2 scroll_offset = vec2(0.0);
/** Mirror alternating caustic image columns along texture X. */
uniform bool mirror_x = false;
/** Mirror alternating caustic image rows along texture Y. */
uniform bool mirror_y = false;
uniform vec4 caustic_color : source_color = vec4(0.35, 0.85, 1.0, 1.0);
uniform float intensity = 0.45;
/** Minimum caustic filtering width in texture pixels. */
uniform float edge_softness = 4.0;
uniform float fade_depth = 300.0;
uniform float normal_fade = 0.8;
/** Maximum receiver distance in world units. Zero disables distance culling. */
uniform float max_distance = 300.0;
/** Fade width before the maximum receiver distance. */
uniform float distance_fade = 175.0;

void vertex() {
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	// Retain projection coverage when the volume extends beyond the far plane.
	POSITION.z = max(POSITION.z, CLIP_SPACE_FAR * POSITION.w);
}

void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).r;
	if (depth <= 0.0) { discard; }
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	float distance_attenuation = 1.0;
	if (max_distance > 0.0) {
		float distance_squared = dot(view.xyz, view.xyz);
		if (distance_squared >= max_distance * max_distance) { discard; }
		if (distance_fade > 0.0) {
			distance_attenuation = 1.0 - smoothstep(max(max_distance - distance_fade, 0.0), max_distance, sqrt(distance_squared));
		}
	}
	vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	vec3 local = (world_to_volume * vec4(world, 1.0)).xyz;
	vec3 uvw = (local - bounds_min) / bounds_size;
	if (any(lessThan(uvw, vec3(0.0))) || any(greaterThan(uvw, vec3(1.0)))) { discard; }
	vec3 centered = uvw * 2.0 - 1.0;
	if (geometry_kind == 1 && dot(centered, centered) > 1.0) { discard; }
	if (geometry_kind == 2 && dot(centered.xz, centered.xz) > 1.0) { discard; }
	float attenuation = distance_attenuation * (1.0 - smoothstep(0.0, fade_depth, bounds_min.y + bounds_size.y - local.y));
	if (attenuation <= 0.0) { discard; }
	if (geometry_kind == 3 && (!has_occupancy || texture(occupancy, uvw).r < 0.5)) { discard; }
	float facing = 1.0;
	if (normal_fade > 0.0) {
		vec3 receiver_normal = normalize(cross(dFdy(local), dFdx(local)));
		facing = mix(1.0, max(receiver_normal.y, 0.0), normal_fade);
	}
	vec2 uv = local.xz / tile_size + scroll_offset;
	vec4 pattern_sample;
	if (edge_softness > 1.0) {
		vec2 dimensions = vec2(textureSize(caustic_image, 0));
		float footprint = max(length(dFdx(uv) * dimensions), length(dFdy(uv) * dimensions));
		float lod = log2(max(footprint, edge_softness));
		pattern_sample = water_tiled_image_lod(caustic_image, uv, bvec2(mirror_x, mirror_y), lod);
	} else {
		pattern_sample = water_tiled_image(caustic_image, uv, bvec2(mirror_x, mirror_y));
	}
	vec3 pattern = pattern_sample.rgb * pattern_sample.a;
	ALBEDO = pattern * caustic_color.rgb * intensity * attenuation * facing;
	ALPHA = caustic_color.a;
}
