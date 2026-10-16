#[vertex]
#version 450
void main() {
	vec2 position = vec2(float((gl_VertexIndex << 1) & 2), float(gl_VertexIndex & 2));
	gl_Position = vec4(position * 2.0 - 1.0, 0.0, 1.0);
}

#[fragment]
#version 450
layout(set = 0, binding = 0) uniform sampler2D source_color;
layout(location = 0) out vec4 color;
void main() {
	color = texelFetch(source_color, ivec2(gl_FragCoord.xy), 0);
}
