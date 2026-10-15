@tool
extends CompositorEffect

const MASK_SHADER: RDShaderFile = preload("res://LS5Framework/Shaders/AdventureWaterMask.glsl")
const COMPOSITE_SHADER: RDShaderFile = preload("res://LS5Framework/Shaders/AdventureWaterComposite.glsl")
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
		_dispatch(scene_copy, color, mask, layer, depth, water_depth, size, 0.0)
		_dispatch(color, scene_copy, mask, layer, depth, water_depth, size, 1.0)
	_prune_buffers(water_data)


func _dispatch(output: RID, source: RID, mask: RID, layer: RID, depth: RID, water_depth: RID, size: Vector2i, composite: float) -> void:
	var uniforms: Array[RDUniform] = [
		_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 0, [output]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, [_linear_sampler, source]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, [_nearest_sampler, mask]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 3, [_nearest_sampler, layer]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 4, [_nearest_sampler, depth]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 5, [_nearest_sampler, water_depth]),
	]
	var uniform_set: RID = UniformSetCacheRD.get_cache(_composite_shader, 0, uniforms)
	var compute_list: int = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _compute_pipeline)
	_rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	var push_constants: PackedByteArray = PackedFloat32Array([size.x, size.y, composite, 0.0]).to_byte_array()
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
			_draws[id] = _rd.uniform_buffer_create(288)
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
		values.append_array(PackedFloat32Array([params.transparency, params.wave_opacity, params.highlight_threshold, params.highlight_softness, params.texture_rotation, float(params.top_only), params.refraction_strength, 0.0, float(params.mirror_x), float(params.mirror_y), size.x, size.y]))
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
		for buffer: RID in _geometry.values() + _draws.values():
			_rd.free_rid(buffer)
		for resource: RID in [_mask_shader, _composite_shader, _linear_sampler, _nearest_sampler, _surface_sampler]:
			if resource.is_valid():
				_rd.free_rid(resource)
		if _framebuffer.is_valid() and _rd.framebuffer_is_valid(_framebuffer):
			_rd.free_rid(_framebuffer)
