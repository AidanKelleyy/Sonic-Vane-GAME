#[vertex]
#version 450
struct WaterVertex { vec4 position; vec4 normal; };
layout(set = 0, binding = 0, std430) readonly buffer Vertices { WaterVertex vertices[]; };
layout(set = 0, binding = 1, std140) uniform Water {
	mat4 mvp;
	mat4 model_view;
	mat4 model_axes;
	vec4 tile_scroll;
	vec4 water_color;
	vec4 wave_color;
	vec4 appearance;
	vec4 mapping;
	vec4 mirror_size;
} water;
layout(location = 0) out vec3 local_position;
layout(location = 1) out vec3 local_normal;
void main() {
	WaterVertex vertex = vertices[gl_VertexIndex];
	local_position = vertex.position.xyz;
	local_normal = vertex.normal.xyz;
	gl_Position = water.mvp * vertex.position;
}

#[fragment]
#version 450
layout(set = 0, binding = 1, std140) uniform Water {
	mat4 mvp;
	mat4 model_view;
	mat4 model_axes;
	vec4 tile_scroll;
	vec4 water_color;
	vec4 wave_color;
	vec4 appearance;
	vec4 mapping;
	vec4 mirror_size;
} water;
layout(set = 0, binding = 2) uniform sampler2D surface_image;
layout(set = 0, binding = 3) uniform sampler2D scene_depth;
layout(location = 0) in vec3 local_position;
layout(location = 1) in vec3 local_normal;
layout(location = 0) out vec2 surface_distortion;
layout(location = 1) out vec4 surface_layer;

vec2 mirror_uv(vec2 uv, float lod) {
	vec2 inset = min(vec2(0.5), vec2(0.5) * exp2(lod) / vec2(textureSize(surface_image, 0)));
	vec2 mirrored = vec2(1.0) - abs(mod(uv, vec2(2.0)) - vec2(1.0));
	if (water.mirror_size.x > 0.5) { uv.x = clamp(mirrored.x, inset.x, 1.0 - inset.x); }
	if (water.mirror_size.y > 0.5) { uv.y = clamp(mirrored.y, inset.y, 1.0 - inset.y); }
	return uv;
}

vec3 tiled_image(vec2 uv) {
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	vec2 dimensions = vec2(textureSize(surface_image, 0));
	float lod = ceil(max(log2(max(max(length(dx * dimensions), length(dy * dimensions)), 1.0)), 0.0));
	vec2 direction = vec2(1.0) - vec2(2.0) * mod(floor(uv), vec2(2.0));
	if (water.mirror_size.x > 0.5) { dx.x *= direction.x; dy.x *= direction.x; }
	if (water.mirror_size.y > 0.5) { dx.y *= direction.y; dy.y *= direction.y; }
	return textureGrad(surface_image, mirror_uv(uv, lod), dx, dy).rgb;
}

vec2 wave_gradient(vec2 uv) {
	vec2 texel = vec2(2.0) / vec2(textureSize(surface_image, 0));
	vec3 right = textureLod(surface_image, mirror_uv(uv + vec2(texel.x, 0.0), 1.0), 1.0).rgb;
	vec3 left = textureLod(surface_image, mirror_uv(uv - vec2(texel.x, 0.0), 1.0), 1.0).rgb;
	vec3 down = textureLod(surface_image, mirror_uv(uv + vec2(0.0, texel.y), 1.0), 1.0).rgb;
	vec3 up = textureLod(surface_image, mirror_uv(uv - vec2(0.0, texel.y), 1.0), 1.0).rgb;
	return vec2(dot(right - left, vec3(0.2126, 0.7152, 0.0722)), dot(down - up, vec3(0.2126, 0.7152, 0.0722)));
}

void main() {
	if (water.mapping.y > 0.5 && local_normal.y < 0.99) { discard; }
	vec2 screen_uv = gl_FragCoord.xy / water.mirror_size.zw;
	if (textureLod(scene_depth, screen_uv, 0.0).r > gl_FragCoord.z + 0.000001) { discard; }
	vec3 weights = pow(abs(normalize(local_normal)), vec3(8.0));
	weights /= max(dot(weights, vec3(1.0)), 0.0001);
	float c = cos(water.mapping.x);
	float s = sin(water.mapping.x);
	mat2 rotation = mat2(vec2(c, s), vec2(-s, c));
	vec2 uv_x = rotation * (local_position.zy / water.tile_scroll.xy) + water.tile_scroll.zw;
	vec2 uv_y = rotation * (local_position.xz / water.tile_scroll.xy) + water.tile_scroll.zw;
	vec2 uv_z = rotation * (local_position.xy / water.tile_scroll.xy) + water.tile_scroll.zw;
	vec3 sample_color = vec3(0.0);
	vec3 gradient = vec3(0.0);
	if (weights.x > 0.001) {
		sample_color += tiled_image(uv_x) * weights.x;
		vec2 slope = transpose(rotation) * wave_gradient(uv_x);
		gradient += vec3(0.0, slope.y, slope.x) * weights.x;
	}
	if (weights.y > 0.001) {
		sample_color += tiled_image(uv_y) * weights.y;
		vec2 slope = transpose(rotation) * wave_gradient(uv_y);
		gradient += vec3(slope.x, 0.0, slope.y) * weights.y;
	}
	if (weights.z > 0.001) {
		sample_color += tiled_image(uv_z) * weights.z;
		vec2 slope = transpose(rotation) * wave_gradient(uv_z);
		gradient += vec3(slope.x, slope.y, 0.0) * weights.z;
	}
	vec3 view_gradient = mat3(water.model_axes) * gradient;
	vec2 distortion = vec2(view_gradient.x, -view_gradient.y) * 4.0 * water.mapping.z;
	distortion.x *= water.mirror_size.w / water.mirror_size.z;
	surface_distortion = distortion;
	float brightness = dot(pow(max(sample_color, vec3(0.0)), vec3(1.0 / 2.2)), vec3(0.2126, 0.7152, 0.0722));
	float highlight = smoothstep(water.appearance.z, water.appearance.z + max(water.appearance.w, 0.001), brightness);
	float wave_alpha = highlight * water.appearance.y * water.wave_color.a;
	float base_alpha = (1.0 - water.appearance.x) * water.water_color.a;
	float alpha = wave_alpha + base_alpha * (1.0 - wave_alpha);
	vec3 color = water.wave_color.rgb * wave_alpha + water.water_color.rgb * base_alpha * (1.0 - wave_alpha);
	surface_layer = vec4(color, alpha);
}
