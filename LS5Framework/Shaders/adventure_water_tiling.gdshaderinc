vec4 water_tiled_image(sampler2D image, vec2 uv, bvec2 mirror_axes) {
	vec2 gradient_x = dFdx(uv);
	vec2 gradient_y = dFdy(uv);
	vec2 dimensions = vec2(textureSize(image, 0));
	float footprint = max(length(gradient_x * dimensions), length(gradient_y * dimensions));
	float mip_scale = exp2(ceil(max(log2(max(footprint, 1.0)), 0.0)));
	vec2 edge_inset = min(vec2(0.5), vec2(0.5) * mip_scale / dimensions);
	vec2 tile = floor(uv);
	vec2 direction = vec2(1.0) - vec2(2.0) * mod(tile, vec2(2.0));
	vec2 mirrored_uv = vec2(1.0) - abs(mod(uv, vec2(2.0)) - vec2(1.0));
	if (mirror_axes.x) {
		uv.x = clamp(mirrored_uv.x, edge_inset.x, 1.0 - edge_inset.x);
		gradient_x.x *= direction.x;
		gradient_y.x *= direction.x;
	}
	if (mirror_axes.y) {
		uv.y = clamp(mirrored_uv.y, edge_inset.y, 1.0 - edge_inset.y);
		gradient_x.y *= direction.y;
		gradient_y.y *= direction.y;
	}
	return textureGrad(image, uv, gradient_x, gradient_y);
}

vec4 water_tiled_image_lod(sampler2D image, vec2 uv, bvec2 mirror_axes, float lod) {
	vec2 dimensions = vec2(textureSize(image, 0));
	vec2 edge_inset = min(vec2(0.5), vec2(0.5) * exp2(lod) / dimensions);
	vec2 mirrored_uv = vec2(1.0) - abs(mod(uv, vec2(2.0)) - vec2(1.0));
	if (mirror_axes.x) { uv.x = clamp(mirrored_uv.x, edge_inset.x, 1.0 - edge_inset.x); }
	if (mirror_axes.y) { uv.y = clamp(mirrored_uv.y, edge_inset.y, 1.0 - edge_inset.y); }
	return textureLod(image, uv, lod);
}
