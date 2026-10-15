#[vertex]
#version 450
struct WaterVertex { vec4 position; vec4 normal; };
layout(set = 0, binding = 0, std430) readonly buffer Vertices { WaterVertex vertices[]; };
layout(set = 0, binding = 1, std140) uniform Water { mat4 mvp; mat4 model_view; } water;
layout(location = 0) out vec3 view_position;
layout(location = 1) out vec3 view_normal;
void main() {
	WaterVertex vertex = vertices[gl_VertexIndex];
	view_position = (water.model_view * vertex.position).xyz;
	view_normal = transpose(inverse(mat3(water.model_view))) * vertex.normal.xyz;
	gl_Position = water.mvp * vertex.position;
	gl_Position.z = max(gl_Position.z, 0.0);
	if (gl_Position.w > 0.0) { gl_Position.z = min(gl_Position.z, gl_Position.w); }
}

#[fragment]
#version 450
layout(set = 0, binding = 2, std140) uniform DepthWater {
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
layout(set = 0, binding = 3) uniform sampler2D scene_depth;
layout(location = 0) in vec3 view_position;
layout(location = 1) in vec3 view_normal;
layout(location = 0) out vec2 signed_interval;
layout(location = 1) out float nearest_entry;
void main() {
	vec2 uv = gl_FragCoord.xy / water.viewport.xy;
	vec4 near_position = water.inverse_projection * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
	near_position.xyz /= near_position.w;
	vec3 origin = abs(water.projection[3].w) < 0.5 ? vec3(0.0) : vec3(near_position.xy, 0.0);
	vec3 direction = normalize(view_position - origin);
	float depth = textureLod(scene_depth, uv, 0.0).r;
	float receiver_distance = 1e20;
	if (depth > 0.0) {
		vec4 receiver = water.inverse_projection * vec4(uv * 2.0 - 1.0, depth, 1.0);
		receiver_distance = max(dot(receiver.xyz / receiver.w - origin, direction), 0.0);
	}
	float crossing = dot(view_normal, direction) >= 0.0 ? 1.0 : -1.0;
	signed_interval = vec2(crossing * min(length(view_position - origin), receiver_distance), crossing);
	nearest_entry = crossing < 0.0 ? gl_FragCoord.z : 0.0;
}
