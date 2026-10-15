shader_type canvas_item;

uniform float blend : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint_color : source_color = vec4(0.05, 0.2, 0.5, 0.35);
uniform float ripple_speed : hint_range(0.0, 10.0) = 1.2;
uniform float ripple_strength : hint_range(0.0, 0.05) = 0.008;
uniform float ripple_scale : hint_range(1.0, 40.0) = 8.0;
uniform float time_offset = 0.0;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
global uniform bool water_depth_effects_enabled;
global uniform bool water_refraction_enabled;
global uniform bool water_normal_maps_enabled;
uniform bool depth_absorption_active = false;

void fragment() {
	float t = time_offset * ripple_speed;
	vec2 uv = SCREEN_UV;

	float wave_x = sin(uv.y * ripple_scale + t) + sin(uv.y * ripple_scale * 1.7 + t * 1.3);
	float wave_y = sin(uv.x * ripple_scale * 0.9 + t * 0.8) + sin(uv.x * ripple_scale * 1.4 + t * 1.1);
	float distortion_strength = water_refraction_enabled && water_normal_maps_enabled ? ripple_strength : 0.0;
	vec2 distortion = vec2(wave_x, wave_y) * distortion_strength * blend;

	vec4 screen = texture(SCREEN_TEXTURE, uv + distortion);
	float tint_alpha = water_depth_effects_enabled && !depth_absorption_active ? tint_color.a : 0.0;
	vec3 tinted = mix(screen.rgb, tint_color.rgb, tint_alpha * blend);
	COLOR = vec4(tinted, blend);
}
