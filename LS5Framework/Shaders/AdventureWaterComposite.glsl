#[compute]
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform restrict writeonly image2D output_color;
layout(set = 0, binding = 1) uniform sampler2D scene_color;
layout(set = 0, binding = 2) uniform sampler2D water_mask;
layout(set = 0, binding = 3) uniform sampler2D water_layer;
layout(set = 0, binding = 4) uniform sampler2D scene_depth;
layout(set = 0, binding = 5) uniform sampler2D water_depth;
layout(set = 0, binding = 6) uniform sampler2D water_absorption;
layout(push_constant, std430) uniform Params { vec2 size; vec2 reserved; } params;
void main() {
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(pixel, ivec2(params.size)))) { return; }
	if (params.reserved.x < 0.5) {
		imageStore(output_color, pixel, texelFetch(scene_color, pixel, 0));
		return;
	}
	float boundary_depth = texelFetch(water_depth, pixel, 0).r;
	vec2 uv = (vec2(pixel) + 0.5) / params.size;
	vec4 absorption = params.reserved.y > 0.5 ? textureLod(water_absorption, uv, 0.0) : vec4(0.0);
	if (boundary_depth <= 0.0 && absorption.a <= 0.0) { return; }
	vec2 distortion = boundary_depth > 0.0 ? texelFetch(water_mask, pixel, 0).xy : vec2(0.0);
	vec2 refracted_uv = clamp(uv + distortion, vec2(0.5) / params.size, vec2(1.0) - vec2(0.5) / params.size);
	if (boundary_depth > 0.0 && textureLod(scene_depth, refracted_uv, 0.0).r > boundary_depth + 0.000001) { refracted_uv = uv; }
	vec4 background = textureLod(scene_color, refracted_uv, 0.0);
	vec3 transmission = pow(vec3(max(1.0 - absorption.a, 0.0)), vec3(1.2, 1.0, 0.85));
	vec3 depth_color = absorption.rgb / max(absorption.a, 0.00001);
	background.rgb = background.rgb * transmission + depth_color * (vec3(1.0) - transmission);
	vec4 layer = boundary_depth > 0.0 ? texelFetch(water_layer, pixel, 0) : vec4(0.0);
	imageStore(output_color, pixel, vec4(background.rgb * (1.0 - layer.a) + layer.rgb, background.a));
}
