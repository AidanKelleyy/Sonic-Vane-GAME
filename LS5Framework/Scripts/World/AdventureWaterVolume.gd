@tool
extends Node3D
class_name AdventureWaterVolume

enum Geometry { BOX, SPHERE, CYLINDER, CUSTOM }
enum VisibleSurface { TOP, CLOSED }
enum RunnableSurface { LOCAL_TOP, ALL, NONE }

const SURFACE_SHADER: Shader = preload("res://LS5Framework/Shaders/AdventureWater.gdshader")
const REFRACTION_SHADER: Shader = preload("res://LS5Framework/Shaders/AdventureWaterRefraction.gdshader")
const CAUSTICS_SHADER: Shader = preload("res://LS5Framework/Shaders/AdventureWaterCaustics.gdshader")
const REFRACTION_CAPTURE: Script = preload("res://LS5Framework/Scripts/World/AdventureWaterRefractionCapture.gd")
const SURFACE_LAYER: int = 32
const CONTAINMENT_DIRECTION: Vector3 = Vector3(0.873421, 0.371923, 0.312711)

@export_group("Geometry")
## Primitive geometry or a baked closed custom mesh.
@export var geometry: Geometry = Geometry.BOX:
	set(value):
		geometry = value
		_queue_rebuild()
## Box dimensions or sphere/cylinder diameters and height. Resize here; keep node scale uniform.
@export var size: Vector3 = Vector3(300.0, 60.0, 300.0):
	set(value):
		size = value.max(Vector3.ONE * 0.01)
		_queue_rebuild()
## Local Y position of the primitive's upper boundary.
@export var surface_y_offset: float = 0.0:
	set(value):
		surface_y_offset = value
		_queue_rebuild()
## Top-only rendering applies to boxes. Closed rendering displays the entire boundary.
@export var visible_surface: VisibleSurface = VisibleSurface.TOP:
	set(value):
		visible_surface = value
		_queue_rebuild()
## Faces eligible for water running. Local top uses the volume's rotated up axis.
@export var runnable_surface: RunnableSurface = RunnableSurface.LOCAL_TOP
## Maximum angle between a runnable top face and the volume's local up axis.
@export_range(0.0, 89.0, 1.0) var top_face_angle: float = 45.0
## Maximum angle between the player's current up direction and a face when entering a water-run.
@export_range(0.0, 89.0, 1.0) var run_alignment_angle: float = 55.0
## Closed MeshInstance3D or root CSGShape3D used by Rebuild Custom Geometry.
@export var geometry_source: NodePath
## Saved custom geometry in volume-local coordinates. Rebuild after editing the source.
@export var baked_mesh: ArrayMesh:
	set(value):
		baked_mesh = value
		_queue_rebuild()
## Bake the source into saved mesh data, then rebuild surface and interior detection.
@export var rebuild_custom_geometry: bool = false:
	set(value):
		if value and is_inside_tree():
			call_deferred("bake_custom_geometry")
## Voxel resolution for custom-shape caustic clipping. Gameplay containment uses the exact mesh.
@export_range(8, 48, 1) var caustic_clip_resolution: int = 20
## Saved custom-shape caustic occupancy data generated with the custom mesh.
@export var baked_caustic_mask: Texture3D
## Retain authoring nodes during play for runtime rebaking. Disabled for static level water.
@export var keep_source_at_runtime: bool = false

@export_group("Surface Animation")
## Surface images for wave highlights and refraction. Empty uses the bundled 32-frame WaterSurface sequence.
@export var surface_frames: Array[Texture2D] = []:
	set(value):
		surface_frames = value
		if is_inside_tree():
			_load_frames()
## Discrete surface frames per second. Zero pauses on the first frame.
@export_range(0.0, 60.0, 0.5) var surface_fps: float = 18.5
## Animation offset in seconds, shared by the surface and caustics.
@export var animation_offset: float = 0.0
## World units covered by one image tile in volume-local coordinates.
@export var surface_tile_size: Vector2 = Vector2(20.0, 20.0)
## Mirror alternating surface image columns along texture X, after rotation and scrolling.
@export var surface_mirror_x: bool = false
## Mirror alternating surface image rows along texture Y, after rotation and scrolling.
@export var surface_mirror_y: bool = false
## Texture rotation in degrees around each face's projection axis.
@export_range(-180.0, 180.0, 1.0) var surface_rotation: float = 0.0
## Texture scrolling in tiles per second.
@export var surface_scroll: Vector2 = Vector2.ZERO
## Updates surface scrolling and wind drift with animation frames. Zero animation FPS pauses scrolling; disabled scrolls smoothly.
@export var surface_scroll_match_animation: bool = true

@export_group("Surface Appearance")
## Solid water colour beneath the animated wave highlights.
@export var water_color: Color = Color(0.035, 0.43, 0.65, 1.0)
## Wave highlight colour.
@export var wave_color: Color = Color(0.65, 0.94, 1.0, 1.0)
## Removes the solid colour at one while retaining bright wave highlights.
@export_range(0.0, 1.0, 0.01) var transparency: float = 0.6
## Independent opacity of the wave highlights.
@export_range(0.0, 1.0, 0.01) var wave_opacity: float = 0.85
## Image brightness where wave highlights begin.
@export_range(0.0, 1.0, 0.01) var highlight_threshold: float = 0.65
## Brightness interval over which highlights reach full opacity.
@export_range(0.001, 1.0, 0.01) var highlight_softness: float = 0.2
## Distortion of the scene, including transparent character effects. Shares one additional render per viewport.
@export var refraction_enabled: bool = true
## Wave-slope distortion strength relative to viewport height.
@export_range(0.0, 0.1, 0.001) var refraction_strength: float = 0.055

@export_group("Caustics")
## Project animated caustics onto opaque geometry inside the volume.
@export var caustics_enabled: bool = true
## Caustic images in playback order. Black adds no light. Empty uses the bundled 32-frame sequence.
@export var caustic_frames: Array[Texture2D] = []:
	set(value):
		caustic_frames = value
		if is_inside_tree():
			_load_frames()
## Discrete caustic frames per second. Zero pauses on the first frame.
@export_range(0.0, 60.0, 0.5) var caustic_fps: float = 18.5
## Caustic texture scrolling in tiles per second. Texture Y maps to local Z.
@export var caustic_scroll: Vector2 = Vector2.ZERO
## Updates caustic scrolling with animation frames. Zero animation FPS pauses scrolling; disabled scrolls smoothly.
@export var caustic_scroll_match_animation: bool = true
## World units covered by one caustic image tile.
@export var caustic_tile_size: Vector2 = Vector2(20.0, 20.0)
## Mirror alternating caustic image columns along texture X.
@export var caustic_mirror_x: bool = false
## Mirror alternating caustic image rows along texture Y.
@export var caustic_mirror_y: bool = false
## Projected caustic colour.
@export var caustic_color: Color = Color(0.35, 0.85, 1.0, 1.0)
## Additive caustic brightness. Zero disables projection.
@export_range(0.0, 4.0, 0.01) var caustic_intensity: float = 0.45
## Minimum filtering width in texture pixels. Zero retains the original caustic edges.
@export_range(0.0, 32.0, 0.5) var caustic_edge_softness: float = 0.0
## Local depth where caustics fade out below the upper boundary.
@export_range(1.0, 10000.0, 1.0) var caustic_depth: float = 300.0
## Attenuation on faces angled away from the volume's local up direction.
@export_range(0.0, 1.0, 0.01) var caustic_normal_fade: float = 0.8

@export_group("Rendering Performance")
## Serialized scene-capture setting retained for compatibility.
var refraction_resolution_scale: float = 0.75
## Maximum camera distance for caustic receivers in world units. Zero disables distance culling.
@export_range(0.0, 20000.0, 50.0, "or_greater") var caustic_max_distance: float = 300.0
## Distance over which caustics fade before the maximum distance. Zero uses a hard cutoff.
@export_range(0.0, 10000.0, 25.0, "or_greater") var caustic_distance_fade: float = 175.0

@export_group("Weather Influence")
## Applies the scene's time-of-day lighting and sky colours, with optional wind and rain responses.
@export var weather_influence_enabled: bool = true
## Optional weather source. Empty selects the nearest EnvironmentWeatherSystem in the same scene branch.
@export_node_path("EnvironmentWeatherSystem") var weather_system_path: NodePath
## Weather response weight. Zero retains the configured water values.
@export_range(0.0, 1.0, 0.01) var weather_influence_strength: float = 1.0
## Seconds used to smooth abrupt weather changes. Zero applies the current weather immediately.
@export_range(0.0, 10.0, 0.1) var weather_response_seconds: float = 1.5
## Applies wind drift, wave scale, and animation speed changes.
@export var weather_affects_motion: bool = false
## Applies ambient brightness and sky colour to the water and wave highlights.
@export var weather_affects_surface: bool = true
## Applies sunlight, moonlight, and sky colour to projected caustics.
@export var weather_affects_caustics: bool = true
## Applies rain and wind changes to highlight opacity, transparency, refraction, and caustic softness.
@export var weather_affects_roughness: bool = false
## Blend of sky colour into authored surface, wave, and caustic colours.
@export_range(0.0, 1.0, 0.01) var weather_sky_color_strength: float = 0.6
## Minimum surface brightness retained in dark environments.
@export_range(0.0, 1.0, 0.01) var weather_minimum_surface_brightness: float = 0.08
## Sky luminance at full authored water brightness.
@export_range(0.01, 4.0, 0.01) var weather_reference_sky_luminance: float = 0.45
## Ambient luminance at full authored water brightness.
@export_range(0.01, 4.0, 0.01) var weather_reference_ambient_luminance: float = 0.6
## Combined sun and moon energy at full authored caustic intensity.
@export_range(0.01, 20.0, 0.01) var weather_reference_light_energy: float = 1.35
## World wind speed that reaches the maximum water response.
@export_range(0.1, 100.0, 0.1) var weather_reference_wind_speed: float = 20.0
## Converts procedural cloud travel speed to world wind speed for water.
@export_range(0.0, 5000.0, 10.0) var weather_sky_wind_scale: float = 1000.0
## Fraction of world wind velocity applied to surface texture travel.
@export_range(0.0, 1.0, 0.01) var weather_wind_drift: float = 0.12


@export_group("Underwater Tint")
## Override the underwater camera tint inside this volume.
@export var override_tint: bool = false
## Camera tint used when the override is enabled.
@export var tint_color_override: Color = Color(0.04, 0.3, 0.5, 0.25)

@export_group("Environmental Hazards")
## Physics layers containing enemies affected by this water.
@export_flags_3d_physics var enemy_collision_mask: int = 128

var _visual: MeshInstance3D
var _caustics: MeshInstance3D
var _surface: StaticBody3D
var _area: Area3D
var _material: ShaderMaterial
var _caustic_material: ShaderMaterial
var _bounds: AABB = AABB()
var _faces: PackedVector3Array = PackedVector3Array()
var _surface_images: Array[Texture2D] = []
var _caustic_images: Array[Texture2D] = []
var _elapsed: float = 0.0
## Scene weather source used for live water modulation.
var _weather_system: Node
var _weather_resolved_path: NodePath
var _weather_lookup_elapsed: float = 1.0
var _weather_wind: Vector2 = Vector2.ZERO
var _weather_rain: float = 0.0
var _weather_light: float = 1.0
var _weather_lighting_active: bool = false
var _weather_sampled: bool = false
var _weather_sky_color: Color = Color.WHITE
var _weather_light_color: Color = Color.WHITE
var _weather_surface_brightness: float = 1.0
var _weather_caustic_brightness: float = 1.0
var _weather_scroll_offset: Vector2 = Vector2.ZERO
var _surface_scroll_time: float = INF
var _surface_sampled_animation_fps: float = -1.0
var _surface_scroll_was_matched: bool = false
var _surface_weather_scroll_sample: Vector2 = Vector2.ZERO
var _surface_weather_frames: float = 0.0
var _caustic_weather_frames: float = 0.0
var _rebuild_pending: bool = false
var _hazard_inside: Dictionary = {}
var _refraction_capture: Node
var _refraction_captures: Array[Node] = []
var _surface_parameter_cache: Dictionary = {}
var _caustic_parameter_cache: Dictionary = {}
## Viewports used for water visibility and shared refraction requests.
var _render_sources: Array[Viewport] = []
var _render_bounds_dirty: bool = true
var _render_bounds_transform: Transform3D
var _world_bounds: AABB
var _surface_world_bounds: AABB
var _pending_weather_delta: float = 0.0


func _ready() -> void:
	_load_frames()
	_rebuild()
	if geometry == Geometry.CUSTOM and not baked_mesh:
		await bake_custom_geometry()
	if not Engine.is_editor_hint() and not keep_source_at_runtime and geometry_source:
		var source: Node = get_node_or_null(geometry_source)
		if source:
			source.queue_free()


func _queue_rebuild() -> void:
	if not is_inside_tree() or _rebuild_pending:
		return
	_rebuild_pending = true
	call_deferred("_rebuild")


func _load_frames() -> void:
	_surface_images.assign(surface_frames)
	_caustic_images.assign(caustic_frames)
	if _surface_images.is_empty():
		for index: int in range(1, 33):
			_surface_images.append(load("res://LS5Framework/Images/Water/Surface/WaterSurface_%04d.png" % index))
	if _caustic_images.is_empty():
		for index: int in range(1, 33):
			_caustic_images.append(load("res://LS5Framework/Images/Water/Caustics/caustic_%04d.png" % index))


func bake_custom_geometry() -> void:
	var source: Node3D = get_node_or_null(geometry_source) as Node3D
	if not source:
		push_warning("Water geometry source is missing.")
		return
	var source_mesh: Mesh
	if source is CSGShape3D:
		await get_tree().process_frame
		source_mesh = (source as CSGShape3D).bake_static_mesh()
	elif source is MeshInstance3D:
		source_mesh = (source as MeshInstance3D).mesh
	if not source_mesh or not source_mesh.get_surface_count():
		push_warning("Water source must be a closed mesh or root CSG shape.")
		return
	var builder: SurfaceTool = SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var local_transform: Transform3D = global_transform.affine_inverse() * source.global_transform
	for index: int in range(source_mesh.get_surface_count()):
		builder.append_from(source_mesh, index, local_transform)
	baked_mesh = builder.commit()
	source.set("visible", false)
	if source is CSGShape3D:
		(source as CSGShape3D).use_collision = false
	_rebuild()
	baked_caustic_mask = _make_caustic_mask()
	_update_materials()
	notify_property_list_changed()
	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()


func _primitive_mesh() -> ArrayMesh:
	var primitive: PrimitiveMesh
	match geometry:
		Geometry.SPHERE:
			var sphere: SphereMesh = SphereMesh.new()
			sphere.radius = 1.0
			sphere.height = 2.0
			sphere.radial_segments = 32
			sphere.rings = 16
			primitive = sphere
		Geometry.CYLINDER:
			var cylinder: CylinderMesh = CylinderMesh.new()
			cylinder.top_radius = 1.0
			cylinder.bottom_radius = 1.0
			cylinder.height = 2.0
			cylinder.radial_segments = 48
			primitive = cylinder
		_:
			var box: BoxMesh = BoxMesh.new()
			box.size = Vector3.ONE * 2.0
			primitive = box
	var builder: SurfaceTool = SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mesh_transform: Transform3D = Transform3D(Basis.from_scale(size * 0.5), Vector3(0.0, surface_y_offset - size.y * 0.5, 0.0))
	builder.append_from(primitive, 0, mesh_transform)
	return builder.commit()


func _rebuild() -> void:
	_rebuild_pending = false
	if not is_inside_tree():
		return
	if Engine.is_editor_hint():
		_restore_scroll_defaults()
	for node_name: String in ["Water_Visual", "Water_Caustics", "WaterSurface", "Area3D"]:
		var previous: Node = get_node_or_null(node_name)
		if previous:
			remove_child(previous)
			previous.queue_free()
	var mesh: ArrayMesh = baked_mesh if geometry == Geometry.CUSTOM else _primitive_mesh()
	_faces = PackedVector3Array()
	if not mesh:
		return
	_bounds = mesh.get_aabb()
	_render_bounds_dirty = true
	_surface_parameter_cache.clear()
	_caustic_parameter_cache.clear()
	_faces = mesh.get_faces()
	_visual = MeshInstance3D.new()
	_visual.name = "Water_Visual"
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_visual.mesh = mesh
	_material = ShaderMaterial.new()
	_visual.material_override = _material
	add_child(_visual)
	_surface = StaticBody3D.new()
	_surface.name = "WaterSurface"
	_surface.collision_layer = SURFACE_LAYER
	_surface.collision_mask = 0
	_surface.add_to_group("water_surface")
	add_child(_surface)
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.shape = mesh.create_trimesh_shape()
	_surface.add_child(collider)
	_area = Area3D.new()
	_area.name = "Area3D"
	_area.collision_layer = 1
	_area.collision_mask = enemy_collision_mask
	_area.add_to_group("water")
	add_child(_area)
	var detection: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = _bounds.size
	detection.shape = box
	detection.position = _bounds.get_center()
	_area.add_child(detection)
	_caustics = MeshInstance3D.new()
	_caustics.name = "Water_Caustics"
	var projection: BoxMesh = BoxMesh.new()
	projection.size = _bounds.size
	_caustics.mesh = projection
	_caustics.position = _bounds.get_center()
	_caustics.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_caustics.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_caustic_material = ShaderMaterial.new()
	_caustic_material.shader = CAUSTICS_SHADER
	_caustic_material.render_priority = 1
	_caustics.material_override = _caustic_material
	add_child(_caustics)
	_update_materials()
	update_configuration_warnings()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() and get("_pending_weather_delta") == null:
		_pending_weather_delta = 0.0
	_elapsed += delta
	_pending_weather_delta += delta
	_update_materials()


func _exit_tree() -> void:
	_release_refraction_captures()
	if _render_sources != null:
		_render_sources.clear()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or not is_instance_valid(_area):
		return
	var inside: Dictionary = {}
	for body: Node3D in _area.get_overlapping_bodies():
		if body.has_method("apply_environmental_hazard") and contains_water_point(body.global_position):
			inside[body.get_instance_id()] = true
			if not _hazard_inside.has(body.get_instance_id()):
				body.call("apply_environmental_hazard", &"water", self)
	_hazard_inside = inside


func _resolve_weather_system() -> Node:
	if weather_system_path:
		return get_node_or_null(weather_system_path)
	var candidates: Array[Node] = get_tree().get_nodes_in_group(&"environment_weather_system")
	var branch: Node = get_parent()
	while branch and branch != get_tree().root:
		for candidate: Node in candidates:
			if (candidate == branch or branch.is_ancestor_of(candidate)) and candidate.has_method("get_environment_influence_state"):
				return candidate
		branch = branch.get_parent()
	return null


func _update_weather(delta: float) -> void:
	_weather_lookup_elapsed += delta
	if weather_system_path != _weather_resolved_path:
		_weather_system = null
		_weather_lookup_elapsed = 1.0
		_weather_resolved_path = weather_system_path
	if weather_influence_enabled and (not is_instance_valid(_weather_system) or not _weather_system.is_inside_tree()) and _weather_lookup_elapsed >= 1.0:
		_weather_system = _resolve_weather_system()
		_weather_lookup_elapsed = 0.0
	var state: Dictionary = {}
	if weather_influence_enabled and weather_influence_strength > 0.0 and is_instance_valid(_weather_system) and _weather_system.is_inside_tree() and _weather_system.has_method("get_environment_influence_state"):
		state = _weather_system.call("get_environment_influence_state")
	if state.is_empty():
		_weather_wind = Vector2.ZERO
		_weather_rain = 0.0
		_weather_light = 1.0
		_weather_lighting_active = false
		_weather_sampled = false
		_weather_sky_color = Color.WHITE
		_weather_light_color = Color.WHITE
		_weather_surface_brightness = 1.0
		_weather_caustic_brightness = 1.0
		_weather_scroll_offset = Vector2.ZERO
		_surface_weather_frames = 0.0
		_caustic_weather_frames = 0.0
		return
	var direction: Vector2 = state.get("sky_wind_direction", Vector2.ZERO)
	var wind: Vector2 = direction.normalized() * float(state.get("sky_wind_speed", 0.0)) * weather_sky_wind_scale
	var rain_wind: Vector2 = state.get("rain_wind_velocity", Vector2.ZERO)
	if rain_wind.length_squared() > wind.length_squared():
		wind = rain_wind
	var response: float = 1.0 if not _weather_sampled or weather_response_seconds <= 0.0 else 1.0 - exp(-delta / weather_response_seconds)
	_weather_sampled = true
	_weather_wind = _weather_wind.lerp(wind, response)
	_weather_rain = lerpf(_weather_rain, clampf(float(state.get("rain_intensity", 0.0)), 0.0, 1.0), response)
	_weather_light = lerpf(_weather_light, clampf(float(state.get("direct_light_multiplier", 1.0)), 0.0, 1.0), response)
	_weather_lighting_active = state.get("lighting_available", false)
	if _weather_lighting_active:
		var sky_color: Color = state.get("sky_color", Color.WHITE)
		var ambient: Color = state.get("ambient_color", Color.WHITE)
		var sky_luminance: float = maxf(_color_luminance(sky_color) * float(state.get("sky_energy", 1.0)), 0.0)
		var ambient_luminance: float = maxf(_color_luminance(ambient) * float(state.get("ambient_energy", 1.0)), 0.0)
		var brightness: float = sky_luminance / maxf(weather_reference_sky_luminance, 0.01) * 0.75 + ambient_luminance / maxf(weather_reference_ambient_luminance, 0.01) * 0.25
		_weather_surface_brightness = lerpf(_weather_surface_brightness, clampf(brightness, weather_minimum_surface_brightness, 1.0), response)
		_weather_caustic_brightness = lerpf(_weather_caustic_brightness, clampf(float(state.get("direct_light_energy", 1.35)) / maxf(weather_reference_light_energy, 0.01), 0.0, 1.0), response)
		_weather_sky_color = _weather_sky_color.lerp(_normalized_weather_color(sky_color), response)
		_weather_light_color = _weather_light_color.lerp(_normalized_weather_color(state.get("light_color", sky_color)), response)
	if weather_affects_motion:
		var agitation: float = _get_weather_agitation()
		_surface_weather_frames += delta * surface_fps * agitation * 0.6
		_caustic_weather_frames += delta * caustic_fps * agitation * 0.35
		var local_wind: Vector3 = global_basis.orthonormalized().inverse() * Vector3(_weather_wind.x, 0.0, _weather_wind.y)
		var tile: Vector2 = surface_tile_size.max(Vector2.ONE * 0.01) * lerpf(1.0, 1.25, agitation)
		_weather_scroll_offset -= (Vector2(local_wind.x, local_wind.z) / tile).rotated(deg_to_rad(surface_rotation)) * weather_wind_drift * weather_influence_strength * delta
	else:
		_weather_scroll_offset = Vector2.ZERO
		_surface_weather_frames = 0.0
		_caustic_weather_frames = 0.0


func _color_luminance(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722


func _normalized_weather_color(color: Color) -> Color:
	var peak: float = maxf(maxf(color.r, color.g), color.b)
	return Color(color.r / peak, color.g / peak, color.b / peak, 1.0) if peak > 0.0001 else Color.WHITE


func _weather_tinted_color(base: Color, tint: Color, weight: float, brightness: float) -> Color:
	var peak: float = maxf(maxf(base.r, base.g), base.b)
	var result: Color = base.lerp(Color(tint.r * peak, tint.g * peak, tint.b * peak, base.a), weight)
	return Color(result.r * brightness, result.g * brightness, result.b * brightness, base.a)


func _get_weather_agitation() -> float:
	if not weather_influence_enabled:
		return 0.0
	var wind: float = clampf(_weather_wind.length() / maxf(weather_reference_wind_speed, 0.01), 0.0, 1.0)
	return maxf(wind, _weather_rain) * weather_influence_strength


func _update_materials() -> void:
	if not is_instance_valid(_visual) or not _material:
		return
	if Engine.is_editor_hint():
		_restore_scroll_defaults()
	if not is_visible_in_tree():
		_release_refraction_captures()
		return
	_update_render_bounds()
	var has_camera: bool = false
	var surface_in_view: bool = false
	var caustics_in_view: bool = false
	var surface_sources: Array[Viewport] = []
	for source: Viewport in _get_render_sources():
		var camera: Camera3D = source.get_camera_3d()
		if not is_instance_valid(camera):
			continue
		has_camera = true
		if not _is_render_source_visible(source):
			continue
		var planes: Array[Plane] = camera.get_frustum()
		if _bounds_in_frustum(_surface_world_bounds, planes):
			surface_in_view = true
			surface_sources.append(source)
		if caustics_enabled and caustic_intensity > 0.0 and _bounds_in_frustum(_world_bounds, planes):
			caustics_in_view = caustics_in_view or not caustic_max_distance or _distance_to_volume_squared(camera.get_camera_transform().origin) < caustic_max_distance * caustic_max_distance
	if not has_camera:
		surface_in_view = true
		caustics_in_view = true
	_caustics.visible = caustics_enabled and caustic_intensity > 0.0 and caustics_in_view
	if not surface_in_view and not _caustics.visible:
		_release_refraction_captures()
		return
	if _pending_weather_delta > 0.0:
		_update_weather(_pending_weather_delta)
		_pending_weather_delta = 0.0
	var desired_shader: Shader = REFRACTION_SHADER if refraction_enabled else SURFACE_SHADER
	if _material.shader != desired_shader:
		_material.shader = desired_shader
		_surface_parameter_cache.clear()
	if refraction_enabled:
		_visual.layers = REFRACTION_CAPTURE.WATER_RENDER_LAYER
		_material.render_priority = 120
		_update_refraction_captures(surface_sources)
	else:
		_visual.layers = 1
		_material.render_priority = 0
		_release_refraction_captures()
	_visual.visible = not refraction_enabled or not REFRACTION_CAPTURE.is_supported()
	var agitation: float = _get_weather_agitation()
	var motion: float = agitation if weather_affects_motion else 0.0
	var appearance: float = agitation if weather_affects_surface and weather_affects_roughness else 0.0
	var caustics: float = agitation if weather_affects_caustics and weather_affects_roughness else 0.0
	var rain: float = _weather_rain * weather_influence_strength if weather_influence_enabled else 0.0
	var surface_light: float = lerpf(1.0, _weather_surface_brightness if _weather_lighting_active else _weather_light, weather_influence_strength) if weather_influence_enabled and weather_affects_surface else 1.0
	var caustic_light: float = lerpf(1.0, _weather_caustic_brightness if _weather_lighting_active else _weather_light, weather_influence_strength) if weather_influence_enabled and weather_affects_caustics else 1.0
	var tint: float = weather_sky_color_strength * weather_influence_strength if weather_influence_enabled and _weather_lighting_active else 0.0
	var current_water_color: Color = _weather_tinted_color(water_color, _weather_sky_color, tint if weather_affects_surface else 0.0, surface_light)
	var current_wave_color: Color = _weather_tinted_color(wave_color, _weather_sky_color, tint if weather_affects_surface else 0.0, surface_light)
	var current_caustic_color: Color = _weather_tinted_color(caustic_color, _weather_light_color.lerp(_weather_sky_color, 0.3), tint if weather_affects_caustics else 0.0, 1.0)
	var current_transparency: float = transparency * lerpf(1.0, 0.85, appearance)
	var time: float = _elapsed + animation_offset
	var surface_frame: int = int(floor(time * surface_fps + (_surface_weather_frames if weather_affects_motion and weather_influence_enabled and surface_fps > 0.0 else 0.0)))
	var caustic_frame: int = int(floor(time * caustic_fps + (_caustic_weather_frames if weather_affects_motion and weather_influence_enabled and caustic_fps > 0.0 else 0.0)))
	var surface_scroll_time: float = (float(surface_frame) / surface_fps if surface_fps > 0.0 else 0.0) if surface_scroll_match_animation else time
	var caustic_scroll_time: float = (float(caustic_frame) / caustic_fps if caustic_fps > 0.0 else 0.0) if caustic_scroll_match_animation else time
	if not surface_scroll_match_animation or not _surface_scroll_was_matched or surface_scroll_time != _surface_scroll_time or surface_fps != _surface_sampled_animation_fps:
		_surface_weather_scroll_sample = _weather_scroll_offset
		_surface_scroll_time = surface_scroll_time
		_surface_sampled_animation_fps = surface_fps
	_surface_scroll_was_matched = surface_scroll_match_animation
	var params: Dictionary = {
		"water_color": current_water_color, "wave_color": current_wave_color,
		"transparency": current_transparency, "wave_opacity": minf(wave_opacity * lerpf(1.0, 1.2, appearance), 1.0),
		"highlight_threshold": maxf(highlight_threshold - appearance * 0.1, 0.0), "highlight_softness": highlight_softness + appearance * 0.1,
		"tile_size": surface_tile_size.max(Vector2.ONE * 0.01) * lerpf(1.0, 1.25, motion),
		"mirror_x": surface_mirror_x, "mirror_y": surface_mirror_y,
		"texture_rotation": deg_to_rad(surface_rotation), "scroll_offset": surface_scroll * surface_scroll_time + (_surface_weather_scroll_sample if weather_affects_motion and weather_influence_enabled else Vector2.ZERO),
		"top_only": visible_surface == VisibleSurface.TOP and geometry == Geometry.BOX,
		"refraction_strength": minf(refraction_strength * lerpf(1.0, 1.5, appearance), 0.1),
	}
	if not _surface_images.is_empty():
		params["surface_image"] = _surface_images[posmod(surface_frame, _surface_images.size())]
	_set_material_parameters(_material, _surface_parameter_cache, params)
	if not _caustics.visible:
		return
	var caustic_params: Dictionary = {
		"world_to_volume": global_transform.affine_inverse(), "bounds_min": _bounds.position,
		"bounds_size": _bounds.size, "geometry_kind": geometry,
		"occupancy": baked_caustic_mask, "has_occupancy": baked_caustic_mask != null,
		"tile_size": caustic_tile_size.max(Vector2.ONE * 0.01) * lerpf(1.0, 1.15, motion),
		"mirror_x": caustic_mirror_x, "mirror_y": caustic_mirror_y,
		"scroll_offset": caustic_scroll * caustic_scroll_time,
		"caustic_color": current_caustic_color, "intensity": caustic_intensity * caustic_light * lerpf(1.0, 0.65, caustics) * (1.0 - (1.0 - (current_transparency if weather_affects_caustics else transparency)) * water_color.a),
		"edge_softness": caustic_edge_softness + (rain * 4.0 if weather_affects_caustics and weather_affects_roughness else 0.0),
		"fade_depth": maxf(caustic_depth * lerpf(1.0, 0.65, caustics), 0.01), "normal_fade": caustic_normal_fade,
		"max_distance": caustic_max_distance, "distance_fade": caustic_distance_fade,
	}
	if not _caustic_images.is_empty():
		caustic_params["caustic_image"] = _caustic_images[posmod(caustic_frame, _caustic_images.size())]
	_set_material_parameters(_caustic_material, _caustic_parameter_cache, caustic_params)


func _set_material_parameters(material: ShaderMaterial, cache: Dictionary, parameters: Dictionary) -> void:
	if cache == parameters:
		return
	for parameter: String in parameters:
		var value: Variant = parameters[parameter]
		if cache.has(parameter) and cache[parameter] == value:
			continue
		cache[parameter] = value
		material.set_shader_parameter(parameter, value)
	for parameter: String in cache.keys():
		if not parameters.has(parameter):
			cache.erase(parameter)


func _get_render_sources() -> Array[Viewport]:
	if Engine.is_editor_hint():
		if _render_sources.is_empty() or not is_instance_valid(_render_sources[0]):
			_render_sources.clear()
			for index: int in range(4):
				var source: SubViewport = EditorInterface.get_editor_viewport_3d(index)
				if is_instance_valid(source):
					_render_sources.append(source)
	elif _render_sources.is_empty() or _render_sources[0] != get_viewport():
		_render_sources.assign([get_viewport()])
	return _render_sources


func _is_render_source_visible(source: Viewport) -> bool:
	return not Engine.is_editor_hint() or not source.get_parent() is Control or (source.get_parent() as Control).is_visible_in_tree()


func _update_render_bounds() -> void:
	if not _render_bounds_dirty and _render_bounds_transform == global_transform:
		return
	_render_bounds_transform = global_transform
	_render_bounds_dirty = false
	_world_bounds = global_transform * _bounds
	var surface_bounds: AABB = _bounds
	if geometry == Geometry.BOX and visible_surface == VisibleSurface.TOP:
		surface_bounds.position.y = _bounds.end.y
		surface_bounds.size.y = 0.0
	_surface_world_bounds = global_transform * surface_bounds


func _bounds_in_frustum(bounds: AABB, planes: Array[Plane]) -> bool:
	var center: Vector3 = bounds.get_center()
	var half_size: Vector3 = bounds.size * 0.5
	for plane: Plane in planes:
		if plane.distance_to(center) > plane.normal.abs().dot(half_size):
			return false
	return true


func _distance_to_volume_squared(camera_position: Vector3) -> float:
	var local: Vector3 = global_transform.affine_inverse() * camera_position
	var closest: Vector3 = local.clamp(_bounds.position, _bounds.end)
	return camera_position.distance_squared_to(global_transform * closest)


func is_refraction_visible_from(camera: Camera3D) -> bool:
	if not refraction_enabled or not is_visible_in_tree() or not is_instance_valid(camera):
		return false
	_update_render_bounds()
	return _bounds_in_frustum(_surface_world_bounds, camera.get_frustum())


func _restore_scroll_defaults() -> void:
	if get("refraction_resolution_scale") == null:
		refraction_resolution_scale = 0.75
	if get("caustic_max_distance") == null:
		caustic_max_distance = 300.0
	if get("caustic_distance_fade") == null:
		caustic_distance_fade = 175.0
	if get("_surface_parameter_cache") == null:
		_surface_parameter_cache = {}
	if get("_caustic_parameter_cache") == null:
		_caustic_parameter_cache = {}
	if get("_render_sources") == null:
		_render_sources = []
	if get("_render_bounds_dirty") == null:
		_render_bounds_dirty = true
	if get("_pending_weather_delta") == null:
		_pending_weather_delta = 0.0
	if get("surface_scroll_match_animation") == null:
		surface_scroll_match_animation = true
	if get("caustic_scroll_match_animation") == null:
		caustic_scroll_match_animation = true
	if get("caustic_scroll") == null:
		caustic_scroll = Vector2.ZERO
	if get("_surface_scroll_time") == null:
		_surface_scroll_time = INF
	if get("_surface_sampled_animation_fps") == null:
		_surface_sampled_animation_fps = -1.0
	if get("_surface_scroll_was_matched") == null:
		_surface_scroll_was_matched = false
	if get("_surface_weather_scroll_sample") == null:
		_surface_weather_scroll_sample = Vector2.ZERO


func _release_refraction_captures() -> void:
	for capture: Node in _refraction_captures:
		if is_instance_valid(capture):
			capture.unregister(self)
	_refraction_captures.clear()
	_refraction_capture = null


func _update_refraction_captures(sources: Array[Viewport]) -> void:
	var captures: Array[Node] = []
	for source: Viewport in sources:
		var existing: Node
		for capture: Node in _refraction_captures:
			if is_instance_valid(capture) and capture.get_source_viewport() == source:
				existing = capture
				break
		captures.append(existing if existing else REFRACTION_CAPTURE.acquire(source, self))
	for previous: Node in _refraction_captures:
		if is_instance_valid(previous) and not captures.has(previous):
			previous.unregister(self)
	_refraction_captures = captures
	_refraction_capture = captures[0] if not captures.is_empty() else null


func contains_water_point(world_point: Vector3) -> bool:
	var point: Vector3 = to_local(world_point)
	if not _bounds.has_point(point):
		return false
	var normalized_point: Vector3 = (point - _bounds.get_center()) / (_bounds.size * 0.5)
	match geometry:
		Geometry.BOX:
			return true
		Geometry.SPHERE:
			return normalized_point.length_squared() <= 1.0
		Geometry.CYLINDER:
			return Vector2(normalized_point.x, normalized_point.z).length_squared() <= 1.0
	return _mesh_contains_point(point)


func _mesh_contains_point(point: Vector3) -> bool:
	var crossings: Array[float] = []
	for index: int in range(0, _faces.size(), 3):
		var a: Vector3 = _faces[index]
		var edge1: Vector3 = _faces[index + 1] - a
		var edge2: Vector3 = _faces[index + 2] - a
		var h: Vector3 = CONTAINMENT_DIRECTION.cross(edge2)
		var determinant: float = edge1.dot(h)
		if absf(determinant) < 0.000001:
			continue
		var inverse: float = 1.0 / determinant
		var offset: Vector3 = point - a
		var u: float = offset.dot(h) * inverse
		if u < -0.00001 or u > 1.00001:
			continue
		var q: Vector3 = offset.cross(edge1)
		var v: float = CONTAINMENT_DIRECTION.dot(q) * inverse
		if v < -0.00001 or u + v > 1.00001:
			continue
		var distance: float = edge2.dot(q) * inverse
		if absf(distance) < 0.00001:
			return true
		if distance > 0.0:
			crossings.append(distance)
	crossings.sort()
	var count: int = 0
	var previous: float = -INF
	for distance: float in crossings:
		if distance - previous > 0.0001:
			count += 1
			previous = distance
	return count % 2 == 1


func get_water_surface_normal(world_point: Vector3) -> Vector3:
	var point: Vector3 = to_local(world_point)
	var offset: Vector3 = point - _bounds.get_center()
	var half_size: Vector3 = _bounds.size * 0.5
	var normal: Vector3
	if geometry == Geometry.BOX:
		var gap: Vector3 = half_size - offset.abs()
		var axis: int = 1
		if gap.x < gap.y:
			axis = 0
		if gap.z < gap[axis]:
			axis = 2
		normal = Vector3.ZERO
		normal[axis] = 1.0 if offset[axis] >= 0.0 else -1.0
	elif geometry == Geometry.SPHERE and is_equal_approx(size.x, size.y) and is_equal_approx(size.x, size.z):
		normal = offset.normalized() if offset.length_squared() > 0.000001 else Vector3.UP
	elif geometry == Geometry.CYLINDER and is_equal_approx(size.x, size.z):
		var radial: Vector2 = Vector2(offset.x, offset.z)
		if half_size.y - absf(offset.y) <= half_size.x - radial.length():
			normal = Vector3.UP if offset.y >= 0.0 else Vector3.DOWN
		else:
			normal = Vector3(offset.x, 0.0, offset.z).normalized() if radial.length_squared() > 0.000001 else Vector3.RIGHT
	else:
		normal = _get_mesh_surface_normal(point)
	return (global_basis.inverse().transposed() * normal).normalized()


func _get_mesh_surface_normal(point: Vector3) -> Vector3:
	var closest_distance: float = INF
	var normal: Vector3 = Vector3.UP
	for index: int in range(0, _faces.size(), 3):
		var a: Vector3 = _faces[index]
		var b: Vector3 = _faces[index + 1]
		var c: Vector3 = _faces[index + 2]
		var closest: Vector3 = Geometry3D.get_closest_point_to_segment(point, a, b)
		var face_normal: Vector3 = (c - a).cross(b - a).normalized()
		var projected: Vector3 = point - face_normal * (point - a).dot(face_normal)
		if _point_in_triangle(projected, a, b, c):
			closest = projected
		else:
			for edge: Vector3 in [Geometry3D.get_closest_point_to_segment(point, b, c), Geometry3D.get_closest_point_to_segment(point, c, a)]:
				if edge.distance_squared_to(point) < closest.distance_squared_to(point):
					closest = edge
		var distance: float = closest.distance_squared_to(point)
		if distance < closest_distance:
			closest_distance = distance
			normal = face_normal
	return normal


func _point_in_triangle(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> bool:
	var edge0: Vector3 = b - a
	var edge1: Vector3 = c - a
	var offset: Vector3 = point - a
	var d00: float = edge0.dot(edge0)
	var d01: float = edge0.dot(edge1)
	var d11: float = edge1.dot(edge1)
	var denominator: float = d00 * d11 - d01 * d01
	if absf(denominator) < 0.000001:
		return false
	var u: float = (d11 * offset.dot(edge0) - d01 * offset.dot(edge1)) / denominator
	var v: float = (d00 * offset.dot(edge1) - d01 * offset.dot(edge0)) / denominator
	return u >= 0.0 and v >= 0.0 and u + v <= 1.0


func allows_water_running(normal: Vector3, player_up: Vector3, already_running: bool = false) -> bool:
	if runnable_surface == RunnableSurface.NONE:
		return false
	var up: Vector3 = global_basis.y.normalized()
	if runnable_surface == RunnableSurface.LOCAL_TOP and normal.dot(up) < cos(deg_to_rad(top_face_angle)):
		return false
	return already_running or normal.dot(player_up.normalized()) >= cos(deg_to_rad(run_alignment_angle))


func _make_caustic_mask() -> ImageTexture3D:
	var resolution: int = clampi(caustic_clip_resolution, 8, 48)
	var slices: Array[Image] = []
	for z: int in range(resolution):
		var slice: Image = Image.create(resolution, resolution, false, Image.FORMAT_R8)
		for y: int in range(resolution):
			for x: int in range(resolution):
				var fraction: Vector3 = (Vector3(x, y, z) + Vector3.ONE * 0.5) / float(resolution)
				var point: Vector3 = _bounds.position + fraction * _bounds.size
				var contained: bool = _mesh_contains_point(point)
				if contained:
					var half_cell: Vector3 = _bounds.size / float(resolution) * 0.499
					for corner: Vector3 in [Vector3(-1, -1, -1), Vector3(-1, -1, 1), Vector3(-1, 1, -1), Vector3(-1, 1, 1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(1, 1, -1), Vector3(1, 1, 1)]:
						if not _mesh_contains_point(point + corner * half_cell):
							contained = false
							break
				if contained:
					slice.set_pixel(x, y, Color.WHITE)
		slices.append(slice)
	var texture: ImageTexture3D = ImageTexture3D.new()
	texture.create(Image.FORMAT_R8, resolution, resolution, resolution, false, slices)
	return texture


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = PackedStringArray()
	if geometry == Geometry.CUSTOM and not baked_mesh:
		warnings.append("Assign a closed geometry source and enable Rebuild Custom Geometry.")
	if geometry != Geometry.BOX and visible_surface == VisibleSurface.TOP:
		warnings.append("Top-only rendering applies to boxes; this geometry renders its closed boundary.")
	if not is_equal_approx(scale.x, scale.y) or not is_equal_approx(scale.y, scale.z):
		warnings.append("Use Size or source geometry dimensions instead of nonuniform node scale.")
	if geometry == Geometry.CUSTOM and _faces.size() > 6000:
		warnings.append("Custom water containment scans mesh triangles. Use a simplified closed source for large meshes.")
	return warnings
