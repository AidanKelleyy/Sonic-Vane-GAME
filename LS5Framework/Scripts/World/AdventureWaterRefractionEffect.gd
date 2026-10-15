@tool
extends CompositorEffect

const MASK_SHADER: RDShaderFile = preload("res://LS5Framework/Shaders/AdventureWaterMask.glsl")
const COMPOSITE_SHADER: RDShaderFile = preload("res://LS5Framework/Shaders/AdventureWaterComposite.glsl")
const DEPTH_SHADER: RDShaderFile = preload("res://LS5Framework/Shaders/AdventureWaterDepth.glsl")
const INTEGRAL_SHADER: RDShaderFile = preload("res://LS5Framework/Shaders/AdventureWaterDepthIntegral.glsl")
const BUFFER_CONTEXT: StringName = &"adventure_water"

var _mutex: Mutex = Mutex.new()
var _water_data: Array[Dictionary] = []
var _rd: RenderingDevice
var _mask_shader: RID
var _composite_shader: RID
var _compute_pipeline: RID
var _mask_pipeline: RID
var _framebuffer: RID
var _framebuffer_textures: Array[RID] = []
var _linear_sampler: RID
var _nearest_sampler: RID
var _surface_sampler: RID
var _geometry: Dictionary = {}
var _draws: Dictionary = {}
var _depth_draws: Dictionary = {}
var _depth_shader: RID
var _integral_shader: RID
var _depth_pipeline: RID
var _integral_pipeline: RID
var _depth_framebuffers: Dictionary = {}


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	access_resolved_depth = true


func set_water_data(data: Array[Dictionary]) -> void:
	_mutex.lock()
	_water_data = data
	_mutex.unlock()


func _render_callback(_callback_type: int, render_data: RenderData) -> void:
	_mutex.lock()
	var water_data: Array[Dictionary] = _water_data.duplicate()
	_mutex.unlock()
	if water_data.is_empty():
		return
	var buffers: RenderSceneBuffersRD = render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if not buffers:
		return
	var size: Vector2i = buffers.get_internal_size()
	if size.x < 1 or size.y < 1:
		return
	if not _rd:
		_initialize_device()
	if not _compute_pipeline.is_valid() or not _mask_shader.is_valid():
		return
	var usage: int = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT
	var mask: RID = buffers.create_texture(BUFFER_CONTEXT, &"mask", RenderingDevice.DATA_FORMAT_R16G16_SFLOAT, usage, RenderingDevice.TEXTURE_SAMPLES_1, size, 1, 1, false, false)
	var layer: RID = buffers.create_texture(BUFFER_CONTEXT, &"layer", RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, usage, RenderingDevice.TEXTURE_SAMPLES_1, size, 1, 1, false, false)
	var water_depth: RID = buffers.create_texture(BUFFER_CONTEXT, &"depth", RenderingDevice.DATA_FORMAT_D32_SFLOAT, RenderingDevice.TEXTURE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT, RenderingDevice.TEXTURE_SAMPLES_1, size, 1, 1, false, false)
	var scene_copy: RID = buffers.create_texture(BUFFER_CONTEXT, &"scene", RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT, RenderingDevice.TEXTURE_SAMPLES_1, size, 1, 1, false, false)
	var textures: Array[RID] = [mask, layer, water_depth]
	if textures != _framebuffer_textures or not _rd.framebuffer_is_valid(_framebuffer):
		if _framebuffer.is_valid() and _rd.framebuffer_is_valid(_framebuffer):
			_rd.free_rid(_framebuffer)
		_framebuffer_textures = textures
		_framebuffer = _rd.framebuffer_create(textures)
		_create_mask_pipeline()
	var scene: RenderSceneData = render_data.get_render_scene_data()
	for view: int in range(buffers.get_view_count()):
		var color: RID = buffers.get_color_layer(view)
		var depth: RID = buffers.get_depth_layer(view)
		var camera_transform: Transform3D = scene.get_cam_transform()
		camera_transform.origin += camera_transform.basis * scene.get_view_eye_offset(view)
		var view_transform: Transform3D = camera_transform.affine_inverse()
		var projection: Projection = scene.get_view_projection(view)
		var draws: Array[Dictionary] = _prepare_draws(water_data, view_transform, projection, depth, size)
		if draws.is_empty():
			continue
		var draw_list: int = _rd.draw_list_begin(_framebuffer, RenderingDevice.DRAW_CLEAR_ALL, PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0)]), 0.0)
		_rd.draw_list_bind_render_pipeline(draw_list, _mask_pipeline)
		for draw: Dictionary in draws:
			_rd.draw_list_bind_uniform_set(draw_list, draw.uniform_set, 0)
			_rd.draw_list_draw(draw_list, false, 1, draw.count)
		_rd.draw_list_end()
		var absorption: RID = _render_absorption(water_data, buffers, camera_transform, projection, depth, mask, water_depth, size)
		var has_absorption: bool = absorption.is_valid()
		_dispatch(scene_copy, color, mask, layer, depth, water_depth, absorption if has_absorption else layer, size, 0.0, has_absorption)
		_dispatch(color, scene_copy, mask, layer, depth, water_depth, absorption if has_absorption else layer, size, 1.0, has_absorption)
	_prune_buffers(water_data)


func _dispatch(output: RID, source: RID, mask: RID, layer: RID, depth: RID, water_depth: RID, absorption: RID, size: Vector2i, composite: float, has_absorption: bool) -> void:
	var uniforms: Array[RDUniform] = [
		_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 0, [output]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, [_linear_sampler, source]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, [_nearest_sampler, mask]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 3, [_nearest_sampler, layer]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 4, [_nearest_sampler, depth]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 5, [_nearest_sampler, water_depth]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 6, [_nearest_sampler, absorption]),
	]
	var uniform_set: RID = UniformSetCacheRD.get_cache(_composite_shader, 0, uniforms)
	var compute_list: int = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _compute_pipeline)
	_rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	var push_constants: PackedByteArray = PackedFloat32Array([size.x, size.y, composite, float(has_absorption)]).to_byte_array()
	_rd.compute_list_set_push_constant(compute_list, push_constants, push_constants.size())
	_rd.compute_list_dispatch(compute_list, ceili(float(size.x) / 8.0), ceili(float(size.y) / 8.0), 1)
	_rd.compute_list_end()


func _initialize_device() -> void:
	_rd = RenderingServer.get_rendering_device()
	_mask_shader = _rd.shader_create_from_spirv(MASK_SHADER.get_spirv())
	_composite_shader = _rd.shader_create_from_spirv(COMPOSITE_SHADER.get_spirv())
	_compute_pipeline = _rd.compute_pipeline_create(_composite_shader)
	var sampler: RDSamplerState = RDSamplerState.new()
	sampler.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_linear_sampler = _rd.sampler_create(sampler)
	sampler.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	_nearest_sampler = _rd.sampler_create(sampler)
	sampler.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler.use_anisotropy = true
	sampler.anisotropy_max = 4.0
	_surface_sampler = _rd.sampler_create(sampler)


func _create_mask_pipeline() -> void:
	if _mask_pipeline.is_valid():
		return
	var raster: RDPipelineRasterizationState = RDPipelineRasterizationState.new()
	raster.cull_mode = RenderingDevice.POLYGON_CULL_DISABLED
	var depth: RDPipelineDepthStencilState = RDPipelineDepthStencilState.new()
	depth.enable_depth_test = true
	depth.enable_depth_write = true
	depth.depth_compare_operator = RenderingDevice.COMPARE_OP_GREATER
	var blend: RDPipelineColorBlendState = RDPipelineColorBlendState.new()
	blend.attachments = [RDPipelineColorBlendStateAttachment.new(), RDPipelineColorBlendStateAttachment.new()]
	_mask_pipeline = _rd.render_pipeline_create(_mask_shader, _rd.framebuffer_get_format(_framebuffer), -1, RenderingDevice.RENDER_PRIMITIVE_TRIANGLES, raster, RDPipelineMultisampleState.new(), depth, blend)


func _prepare_draws(data: Array[Dictionary], view: Transform3D, projection: Projection, depth: RID, size: Vector2i) -> Array[Dictionary]:
	var draws: Array[Dictionary] = []
	for water: Dictionary in data:
		var mesh_id: int = water.mesh_id
		if not _geometry.has(mesh_id):
			_geometry[mesh_id] = _rd.storage_buffer_create(water.vertices.size(), water.vertices)
		var id: int = water.id
		if not _draws.has(id):
			_draws[id] = _rd.uniform_buffer_create(320)
		var uniform_buffer: RID = _draws[id]
		var values: PackedFloat32Array = PackedFloat32Array()
		_append_projection(values, projection * Projection(view * water.transform))
		_append_projection(values, Projection(view * water.transform))
		var axes: Basis = water.transform.basis
		axes = Basis(axes.x.normalized(), axes.y.normalized(), axes.z.normalized())
		_append_projection(values, Projection(Transform3D(view.basis * axes, Vector3.ZERO)))
		var params: Dictionary = water.parameters
		var tile: Vector2 = params.tile_size
		var scroll: Vector2 = params.scroll_offset
		values.append_array(PackedFloat32Array([tile.x, tile.y, scroll.x, scroll.y]))
		_append_color(values, params.water_color.srgb_to_linear())
		_append_color(values, params.wave_color.srgb_to_linear())
		values.append_array(PackedFloat32Array([params.transparency, params.wave_opacity, params.highlight_threshold, params.highlight_softness, params.texture_rotation, float(params.top_only), params.refraction_strength, float(absf(projection.w.w) > 0.5), float(params.mirror_x), float(params.mirror_y), size.x, size.y]))
		_append_color(values, params.view_angle_color.srgb_to_linear())
		values.append_array(PackedFloat32Array([params.view_angle_strength, params.surface_detail_distance, 0.0, 0.0]))
		var bytes: PackedByteArray = values.to_byte_array()
		_rd.buffer_update(uniform_buffer, 0, bytes.size(), bytes)
		var texture: RID = RenderingServer.texture_get_rd_texture(params.surface_image.get_rid(), true)
		if not texture.is_valid():
			continue
		var uniforms: Array[RDUniform] = [
			_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0, [_geometry[mesh_id]]),
			_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 1, [uniform_buffer]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, [_surface_sampler, texture]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 3, [_nearest_sampler, depth]),
		]
		draws.append({"uniform_set": UniformSetCacheRD.get_cache(_mask_shader, 0, uniforms), "count": water.count})
	return draws


func _prune_buffers(data: Array[Dictionary]) -> void:
	var meshes: Dictionary = {}
	var users: Dictionary = {}
	for water: Dictionary in data:
		meshes[water.mesh_id] = true
		users[water.id] = true
	for id: int in _geometry.keys():
		if not meshes.has(id):
			_rd.free_rid(_geometry[id])
			_geometry.erase(id)
	for id: int in _draws.keys():
		if not users.has(id):
			_rd.free_rid(_draws[id])
			_draws.erase(id)
	for id: int in _depth_draws.keys():
		if not users.has(id):
			_rd.free_rid(_depth_draws[id])
			_depth_draws.erase(id)


func _render_absorption(data: Array[Dictionary], buffers: RenderSceneBuffersRD, camera: Transform3D, projection: Projection, scene_depth: RID, mask: RID, water_depth: RID, size: Vector2i) -> RID:
	var active: Array[Dictionary] = []
	for water: Dictionary in data:
		if water.parameters.get("depth_enabled", false):
			active.append(water)
	if active.is_empty():
		return RID()
	if not _depth_shader.is_valid():
		_depth_shader = _rd.shader_create_from_spirv(DEPTH_SHADER.get_spirv())
	var usage: int = RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var absorption: RID = buffers.create_texture(BUFFER_CONTEXT, &"absorption", RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, usage, RenderingDevice.TEXTURE_SAMPLES_1, size, 1, 1, false, false)
	var selection_depth: RID = buffers.create_texture(BUFFER_CONTEXT, &"absorption_depth", RenderingDevice.DATA_FORMAT_D32_SFLOAT, RenderingDevice.TEXTURE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT, RenderingDevice.TEXTURE_SAMPLES_1, size, 1, 1, false, false)
	var framebuffer: RID = _get_depth_framebuffer(&"absorption", [absorption, selection_depth])
	if not _depth_pipeline.is_valid():
		var raster: RDPipelineRasterizationState = RDPipelineRasterizationState.new()
		raster.cull_mode = RenderingDevice.POLYGON_CULL_DISABLED
		var depth_state: RDPipelineDepthStencilState = RDPipelineDepthStencilState.new()
		depth_state.enable_depth_test = true
		depth_state.enable_depth_write = true
		depth_state.depth_compare_operator = RenderingDevice.COMPARE_OP_GREATER
		var blend: RDPipelineColorBlendState = RDPipelineColorBlendState.new()
		blend.attachments = [RDPipelineColorBlendStateAttachment.new()]
		_depth_pipeline = _rd.render_pipeline_create(_depth_shader, _rd.framebuffer_get_format(framebuffer), -1, RenderingDevice.RENDER_PRIMITIVE_TRIANGLES, raster, RDPipelineMultisampleState.new(), depth_state, blend)
	_rd.draw_list_begin(framebuffer, RenderingDevice.DRAW_CLEAR_ALL, PackedColorArray([Color(0, 0, 0, 0)]), 0.0)
	_rd.draw_list_end()
	var view: Transform3D = camera.affine_inverse()
	for water: Dictionary in active:
		var scissor: Rect2i = _depth_scissor(water, view, projection, size)
		if not scissor.has_area():
			continue
		var buffer: RID = _depth_uniform_buffer(water, camera, projection, size)
		var integral: RID = mask
		var entry: RID = water_depth
		if water.geometry == 3:
			integral = buffers.create_texture(BUFFER_CONTEXT, &"custom_integral", RenderingDevice.DATA_FORMAT_R32G32_SFLOAT, usage, RenderingDevice.TEXTURE_SAMPLES_1, size, 1, 1, false, false)
			entry = buffers.create_texture(BUFFER_CONTEXT, &"custom_entry", RenderingDevice.DATA_FORMAT_R32_SFLOAT, usage, RenderingDevice.TEXTURE_SAMPLES_1, size, 1, 1, false, false)
			_render_custom_integral(water, buffer, scene_depth, integral, entry)
		var uniforms: Array[RDUniform] = [
			_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 0, [buffer]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, [_nearest_sampler, scene_depth]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, [_nearest_sampler, integral]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 3, [_nearest_sampler, entry]),
		]
		var draw_list: int = _rd.draw_list_begin(framebuffer)
		_rd.draw_list_bind_render_pipeline(draw_list, _depth_pipeline)
		_rd.draw_list_bind_uniform_set(draw_list, UniformSetCacheRD.get_cache(_depth_shader, 0, uniforms), 0)
		_rd.draw_list_enable_scissor(draw_list, scissor)
		_rd.draw_list_draw(draw_list, false, 1, 3)
		_rd.draw_list_end()
	return absorption


func _depth_uniform_buffer(water: Dictionary, camera: Transform3D, projection: Projection, size: Vector2i) -> RID:
	if not _depth_draws.has(water.id):
		_depth_draws[water.id] = _rd.uniform_buffer_create(336)
	var buffer: RID = _depth_draws[water.id]
	var values: PackedFloat32Array = PackedFloat32Array()
	_append_projection(values, projection.inverse())
	_append_projection(values, Projection(camera))
	_append_projection(values, Projection(water.transform.affine_inverse()))
	_append_projection(values, projection)
	var bounds: AABB = water.bounds
	values.append_array(PackedFloat32Array([bounds.position.x, bounds.position.y, bounds.position.z, 0.0, bounds.size.x, bounds.size.y, bounds.size.z, 0.0]))
	_append_color(values, water.parameters.depth_color.srgb_to_linear())
	values.append_array(PackedFloat32Array([water.parameters.depth_visibility, water.parameters.depth_strength, water.geometry, float(water.parameters.underwater_depth), size.x, size.y, 0.0, 0.0]))
	var bytes: PackedByteArray = values.to_byte_array()
	_rd.buffer_update(buffer, 0, bytes.size(), bytes)
	return buffer


func _depth_scissor(water: Dictionary, view: Transform3D, projection: Projection, size: Vector2i) -> Rect2i:
	var minimum: Vector2 = Vector2(size)
	var maximum: Vector2 = Vector2.ZERO
	var bounds: AABB = water.bounds
	for corner: int in range(8):
		var point: Vector3 = view * (water.transform * bounds.get_endpoint(corner))
		if point.z >= -0.01:
			return Rect2i(Vector2i.ZERO, size)
		var clip: Vector4 = projection * Vector4(point.x, point.y, point.z, 1.0)
		var screen: Vector2 = (Vector2(clip.x, clip.y) / clip.w * 0.5 + Vector2.ONE * 0.5) * Vector2(size)
		minimum = minimum.min(screen)
		maximum = maximum.max(screen)
	var start: Vector2i = Vector2i(minimum.floor()).clamp(Vector2i.ZERO, size)
	var end: Vector2i = Vector2i(maximum.ceil()).clamp(Vector2i.ZERO, size)
	return Rect2i(start, end - start)


func _get_depth_framebuffer(key: StringName, textures: Array[RID]) -> RID:
	var cached: Dictionary = _depth_framebuffers.get(key, {})
	if cached.get("textures") == textures and _rd.framebuffer_is_valid(cached.get("framebuffer", RID())):
		return cached.framebuffer
	if cached.has("framebuffer") and _rd.framebuffer_is_valid(cached.framebuffer):
		_rd.free_rid(cached.framebuffer)
	var framebuffer: RID = _rd.framebuffer_create(textures)
	_depth_framebuffers[key] = {"textures": textures, "framebuffer": framebuffer}
	return framebuffer


func _render_custom_integral(water: Dictionary, buffer: RID, scene_depth: RID, integral: RID, entry: RID) -> void:
	if not _integral_shader.is_valid():
		_integral_shader = _rd.shader_create_from_spirv(INTEGRAL_SHADER.get_spirv())
	var framebuffer: RID = _get_depth_framebuffer(&"integral", [integral, entry])
	if not _integral_pipeline.is_valid():
		var raster: RDPipelineRasterizationState = RDPipelineRasterizationState.new()
		raster.cull_mode = RenderingDevice.POLYGON_CULL_DISABLED
		var sum: RDPipelineColorBlendStateAttachment = RDPipelineColorBlendStateAttachment.new()
		sum.enable_blend = true
		sum.src_color_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
		sum.dst_color_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
		var nearest: RDPipelineColorBlendStateAttachment = RDPipelineColorBlendStateAttachment.new()
		nearest.enable_blend = true
		nearest.src_color_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
		nearest.dst_color_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
		nearest.color_blend_op = RenderingDevice.BLEND_OP_MAXIMUM
		var blend: RDPipelineColorBlendState = RDPipelineColorBlendState.new()
		blend.attachments = [sum, nearest]
		_integral_pipeline = _rd.render_pipeline_create(_integral_shader, _rd.framebuffer_get_format(framebuffer), -1, RenderingDevice.RENDER_PRIMITIVE_TRIANGLES, raster, RDPipelineMultisampleState.new(), RDPipelineDepthStencilState.new(), blend)
	var uniforms: Array[RDUniform] = [
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0, [_geometry[water.mesh_id]]),
		_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 1, [_draws[water.id]]),
		_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 2, [buffer]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 3, [_nearest_sampler, scene_depth]),
	]
	var draw_list: int = _rd.draw_list_begin(framebuffer, RenderingDevice.DRAW_CLEAR_ALL, PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0)]))
	_rd.draw_list_bind_render_pipeline(draw_list, _integral_pipeline)
	_rd.draw_list_bind_uniform_set(draw_list, UniformSetCacheRD.get_cache(_integral_shader, 0, uniforms), 0)
	_rd.draw_list_draw(draw_list, false, 1, water.count)
	_rd.draw_list_end()


func _uniform(type: int, binding: int, ids: Array[RID]) -> RDUniform:
	var uniform: RDUniform = RDUniform.new()
	uniform.uniform_type = type
	uniform.binding = binding
	for id: RID in ids:
		uniform.add_id(id)
	return uniform


func _append_projection(values: PackedFloat32Array, projection: Projection) -> void:
	for column: Vector4 in [projection.x, projection.y, projection.z, projection.w]:
		values.append_array(PackedFloat32Array([column.x, column.y, column.z, column.w]))


func _append_color(values: PackedFloat32Array, color: Color) -> void:
	values.append_array(PackedFloat32Array([color.r, color.g, color.b, color.a]))


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd:
		for buffer: RID in _geometry.values() + _draws.values() + _depth_draws.values():
			_rd.free_rid(buffer)
		for resource: RID in [_mask_shader, _composite_shader, _depth_shader, _integral_shader, _linear_sampler, _nearest_sampler, _surface_sampler]:
			if resource.is_valid():
				_rd.free_rid(resource)
		if _framebuffer.is_valid() and _rd.framebuffer_is_valid(_framebuffer):
			_rd.free_rid(_framebuffer)
		for cached: Dictionary in _depth_framebuffers.values():
			if _rd.framebuffer_is_valid(cached.framebuffer):
				_rd.free_rid(cached.framebuffer)
