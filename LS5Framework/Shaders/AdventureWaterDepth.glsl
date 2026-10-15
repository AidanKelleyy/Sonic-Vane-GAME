#[vertex]
#version 450
void main() {
	vec2 position = vec2(float((gl_VertexIndex << 1) & 2), float(gl_VertexIndex & 2));
	gl_Position = vec4(position * 2.0 - 1.0, 0.0, 1.0);
}

#[fragment]
#version 450
layout(set = 0, binding = 0, std140) uniform DepthWater {
	mat4 inverse_projection;
	mat4 inverse_view;
	mat4 world_to_volume;
	mat4 projection;
	vec4 bounds_min;
	vec4 bounds_size;
	vec4 color;
	vec4 parameters;
	vec4 viewport;
} water;
layout(set = 0, binding = 1) uniform sampler2D scene_depth;
layout(set = 0, binding = 2) uniform sampler2D custom_integral;
layout(set = 0, binding = 3) uniform sampler2D custom_entry;
layout(location = 0) out vec4 optical_layer;

vec3 view_position(vec2 uv, float depth) {
	vec4 position = water.inverse_projection * vec4(uv * 2.0 - 1.0, depth, 1.0);
	return position.xyz / position.w;
}

bool radial_interval(float a, float b, float c, out vec2 interval) {
	if (a < 0.00000000000000000001) {
		interval = vec2(-1e20, 1e20);
		return c <= 0.0;
	}
	float discriminant = b * b - a * c;
	if (discriminant < 0.0) { return false; }
	float root = sqrt(discriminant);
	interval = vec2(-b - root, -b + root) / a;
	return true;
}

bool slab_interval(float origin, float direction, inout vec2 interval) {
	if (abs(direction) < 0.000000000001) { return abs(origin) <= 1.0; }
	vec2 pair = (vec2(-1.0, 1.0) - origin) / direction;
	interval = vec2(max(interval.x, min(pair.x, pair.y)), min(interval.y, max(pair.x, pair.y)));
	return interval.x < interval.y;
}

void main() {
	vec2 uv = gl_FragCoord.xy / water.viewport.xy;
	float length_in_water;
	float entry_depth;
	bool inside;
	if (water.parameters.z > 2.5) {
		vec2 integral = textureLod(custom_integral, uv, 0.0).rg;
		length_in_water = max(integral.x, 0.0);
		inside = integral.y > 0.5;
		entry_depth = inside ? 1.0 : textureLod(custom_entry, uv, 0.0).r;
	} else {
		vec3 near_position = view_position(uv, 1.0);
		vec3 far_position = view_position(uv, 0.0);
		vec3 view_origin = abs(water.projection[3].w) < 0.5 ? vec3(0.0) : vec3(near_position.xy, 0.0);
		vec3 view_direction = normalize(far_position - near_position);
		vec3 world_origin = (water.inverse_view * vec4(view_origin, 1.0)).xyz;
		vec3 world_direction = mat3(water.inverse_view) * view_direction;
		vec3 center = water.bounds_min.xyz + water.bounds_size.xyz * 0.5;
		vec3 origin = ((water.world_to_volume * vec4(world_origin, 1.0)).xyz - center) * 2.0 / water.bounds_size.xyz;
		vec3 direction = (mat3(water.world_to_volume) * world_direction) * 2.0 / water.bounds_size.xyz;
		vec2 interval = vec2(-1e20, 1e20);
		if (water.parameters.z < 0.5) {
			if (!slab_interval(origin.x, direction.x, interval) || !slab_interval(origin.y, direction.y, interval) || !slab_interval(origin.z, direction.z, interval)) { discard; }
		} else if (water.parameters.z < 1.5) {
			if (!radial_interval(dot(direction, direction), dot(origin, direction), dot(origin, origin) - 1.0, interval)) { discard; }
		} else {
			if (!radial_interval(dot(direction.xz, direction.xz), dot(origin.xz, direction.xz), dot(origin.xz, origin.xz) - 1.0, interval) || !slab_interval(origin.y, direction.y, interval)) { discard; }
		}
		float receiver_depth = textureLod(scene_depth, uv, 0.0).r;
		float receiver_distance = receiver_depth > 0.0 ? dot(view_position(uv, receiver_depth) - view_origin, view_direction) : 1e20;
		float start = max(interval.x, 0.0);
		length_in_water = max(min(interval.y, receiver_distance) - start, 0.0);
		inside = interval.x <= 0.0 && interval.y > 0.0;
		vec4 entry_clip = water.projection * vec4(view_origin + view_direction * start, 1.0);
		entry_depth = inside ? 1.0 : entry_clip.z / entry_clip.w;
	}
	if (length_in_water < 0.0001 || (inside && water.parameters.w < 0.5)) { discard; }
	gl_FragDepth = clamp(entry_depth, 0.0000000001, 1.0);
	float absorption = 1.0 - exp(-3.0 * length_in_water * water.parameters.y / max(water.parameters.x, 0.1));
	optical_layer = vec4(water.color.rgb * absorption, absorption);
}
