extends RefCounted
class_name AutomationRibbonState

var config: AutomationRibbonTrait
## Route supplying geometry and profile ownership.
var source_ref: WeakRef
var state: Dictionary = {}
var profiles: Dictionary = {}
var sample: AutomationSample
var adherence: float = 0.0
var last_correction: Vector3 = Vector3.ZERO
var offset_state: Dictionary = {}


func _init(component: AutomationRibbonTrait, source: AutomationSplineCore) -> void:
	config = component
	source_ref = weakref(source)


func update(body: Node3D, value: AutomationSample, delta: float, weight: float, advance: bool = true) -> void:
	var source: AutomationSplineCore = source_ref.get_ref() as AutomationSplineCore
	if not source or not value or not value.valid:
		return
	if config.cubic_path_sampling:
		value = source.sampler.smooth_sample(value, config.tangent_lookahead)
	var tangent: Vector3 = value.tangent
	var normal: Vector3 = value.normal
	match config.plane_frame_mode:
		AutomationRibbonTrait.PlaneFrameMode.GRAVITY_RIBBON:
			normal = tangent.cross(_get_body_gravity_up(body))
		AutomationRibbonTrait.PlaneFrameMode.PLAYER_RIBBON:
			normal = tangent.cross(_get_body_player_up(body))
		AutomationRibbonTrait.PlaneFrameMode.FIXED_PATH_AXIS:
			normal = source.get_node(source.path_path).global_basis.x
	normal = normal.slide(tangent)
	if normal.length_squared() < 0.000001:
		normal = state.get("plane_normal", value.normal) if config.preserve_frame_through_degenerate_segments else value.normal
	normal = normal.normalized() * (-1.0 if config.reverse_plane_normal else 1.0)
	var previous: Vector3 = state.get("plane_normal", Vector3.ZERO)
	if previous and normal.dot(previous) < 0.0:
		normal = -normal
	var frame: Dictionary = _get_surface_cooperative_frame(body, tangent, normal, state)
	tangent = frame.tangent
	normal = frame.normal
	adherence = _get_adherence_weight(source.sampler.closed, value.distance, source.sampler.length) * weight
	if advance or offset_state.is_empty():
		offset_state = _get_adaptive_plane_offset_state(body, value.position, normal, state, adherence, delta)
		state.merge(offset_state, true)
		state["plane_offset"] = offset_state.offset
		state["plane_offset_initialized"] = true
		state["terrain_orientation_sign"] = frame.orientation_sign
	adherence = maxf(adherence, float(offset_state.get("minimum_constraint_adherence", 0.0)) * weight)
	state["terrain_adjusted"] = frame.adjusted
	state["plane_normal"] = normal
	sample = AutomationSample.new()
	sample.valid = true
	sample.distance = value.distance
	sample.position = value.position + normal * float(offset_state.get("offset", 0.0))
	sample.tangent = tangent
	sample.normal = normal
	sample.up = frame.up.normalized()


func _get_depth_offset_profile_target(body: Node3D, point: Vector3, normal: Vector3) -> Dictionary:
	var source: AutomationSplineCore = source_ref.get_ref() as AutomationSplineCore
	if not config.depth_offset_splines_enabled or not source:
		return {}
	var best: Dictionary = {}
	var candidates: Array[Node] = source.get_tree().get_nodes_in_group(&"AutomationDepthProfiles")
	candidates.sort_custom(func(a: Node, b: Node) -> bool: return String(a.get_path()) < String(b.get_path()))
	var live: Dictionary = {}
	for candidate: Node in candidates:
		var profile: AutomationDepthProfile = candidate as AutomationDepthProfile
		if not profile:
			continue
		var id: int = profile.get_instance_id()
		live[id] = true
		var tracking: Dictionary = profiles.get_or_add(id, {})
		var result: Dictionary = profile.evaluate(body, source, point, normal, tracking)
		if result.is_empty():
			continue
		if best.is_empty() or int(result.priority) > int(best.priority) or (int(result.priority) == int(best.priority) and float(result.profile_distance) < float(best.profile_distance)):
			best = result
	for id: int in profiles.keys():
		if not live.has(id):
			profiles.erase(id)
	return best


func _get_body_gravity_up(body: Node3D) -> Vector3:
	if body.has_method("get_gravity_up"):
		var gravity_value: Variant = body.call("get_gravity_up")
		if gravity_value is Vector3 and (gravity_value as Vector3).length() > 0.001:
			return (gravity_value as Vector3).normalized()
	return Vector3.UP


func _get_body_player_up(body: Node3D) -> Vector3:
	if body.has_method("get_up_vector"):
		var player_up_value: Variant = body.call("get_up_vector")
		if player_up_value is Vector3 and (player_up_value as Vector3).length() > 0.001:
			return (player_up_value as Vector3).normalized()
	return _get_body_gravity_up(body)


func _body_is_attached(body: Node3D) -> bool:
	if body.has_method("is_attached_for_movement"):
		var attached_value: Variant = body.call("is_attached_for_movement")
		if attached_value is bool:
			return bool(attached_value)
	var attached_property: Variant = body.get("attached")
	return attached_property is bool and bool(attached_property)


func _get_body_surface_normal(body: Node3D) -> Vector3:
	var surface_value: Variant = body.get("surface_normal")
	if surface_value is Vector3 and (surface_value as Vector3).length() > 0.001:
		return (surface_value as Vector3).normalized()
	return Vector3.ZERO


func _get_body_velocity(body: Node3D) -> Vector3:
	var velocity_value: Variant = body.get("velocity")
	return velocity_value as Vector3 if velocity_value is Vector3 else Vector3.ZERO


func _get_surface_cooperative_frame(
	body: Node3D,
	curve_tangent: Vector3,
	curve_normal: Vector3,
	progress_state: Dictionary
) -> Dictionary:
	var orientation_sign: float = float(progress_state.get("terrain_orientation_sign", 0.0))
	var fallback_frame: Dictionary = {
		"tangent": curve_tangent,
		"normal": curve_normal,
		"up": curve_normal.cross(curve_tangent),
		"adjusted": false,
		"orientation_sign": orientation_sign,
	}
	if not config.surface_frame_enabled or not _body_is_attached(body):
		return fallback_frame
	var surface_normal: Vector3 = _get_body_surface_normal(body)
	if config.surface_frame_preserve_ribbon_normal:
		surface_normal -= curve_normal * surface_normal.dot(curve_normal)
	if surface_normal.length() < 0.001:
		return fallback_frame
	surface_normal = surface_normal.normalized()

	var surface_tangent: Vector3 = Vector3.ZERO
	match config.surface_traversal_mode:
		AutomationRibbonTrait.SurfaceTraversalMode.PROJECT_PATH_ON_SURFACE:
			surface_tangent = curve_tangent - surface_normal * curve_tangent.dot(surface_normal)
		AutomationRibbonTrait.SurfaceTraversalMode.RIBBON_SURFACE_TANGENT:
			surface_tangent = surface_normal.cross(curve_normal)
			if abs(orientation_sign) < 0.5:
				var reference_up: Vector3 = _get_body_gravity_up(body)
				reference_up -= curve_normal * reference_up.dot(curve_normal)
				var reference_tangent: Vector3 = reference_up.cross(curve_normal)
				if (
					reference_tangent.length() > 0.001
					and abs(reference_tangent.normalized().dot(curve_tangent)) > 0.001
				):
					orientation_sign = (
						1.0 if reference_tangent.dot(curve_tangent) >= 0.0 else -1.0
					)
				else:
					orientation_sign = 1.0
			surface_tangent *= orientation_sign
	if surface_tangent.length() < 0.001:
		return fallback_frame
	surface_tangent = surface_tangent.normalized()

	if config.surface_frame_uses_velocity:
		var body_velocity: Vector3 = _get_body_velocity(body)
		var surface_velocity: Vector3 = body_velocity
		surface_velocity -= surface_normal * surface_velocity.dot(surface_normal)
		if config.surface_frame_preserve_ribbon_normal:
			surface_velocity -= curve_normal * surface_velocity.dot(curve_normal)
		if surface_velocity.length() >= config.surface_frame_min_speed:
			surface_velocity = surface_velocity.normalized()
			if surface_velocity.dot(surface_tangent) < 0.0:
				surface_velocity = -surface_velocity
			surface_tangent = surface_velocity

	var frame_weight: float = clamp(config.surface_frame_influence, 0.0, 1.0)
	var turn_angle: float = curve_tangent.signed_angle_to(surface_tangent, curve_normal)
	var tangent: Vector3 = curve_tangent.rotated(curve_normal, turn_angle * frame_weight)
	if tangent.length() < 0.001:
		tangent = surface_tangent
	tangent = tangent.normalized()

	var normal: Vector3 = curve_normal
	if not config.surface_frame_preserve_ribbon_normal:
		var surface_plane_normal: Vector3 = tangent.cross(surface_normal)
		if surface_plane_normal.length() > 0.001:
			surface_plane_normal = surface_plane_normal.normalized()
			if surface_plane_normal.dot(curve_normal) < 0.0:
				surface_plane_normal = -surface_plane_normal
			normal = curve_normal.slerp(surface_plane_normal, frame_weight)
	normal -= tangent * normal.dot(tangent)
	if normal.length() < 0.001:
		normal = curve_normal
	normal = normal.normalized()
	var terrain_up: Vector3 = normal.cross(tangent)
	if terrain_up.length() < 0.001:
		terrain_up = surface_normal
	else:
		terrain_up = terrain_up.normalized()
	return {
		"tangent": tangent,
		"normal": normal,
		"up": terrain_up,
		"adjusted": true,
		"orientation_sign": orientation_sign,
	}


func _get_terrain_piece_anchor_offset(
	body: Node3D,
	path_point: Vector3,
	plane_normal: Vector3,
	current_offset: float
) -> Dictionary:
	if (
		not config.terrain_piece_anchors_enabled
		or config.terrain_piece_anchor_metadata == &""
		or not _body_is_attached(body)
		or not body.has_method("get_slide_collision_count")
		or not body.has_method("get_slide_collision")
	):
		return {}

	var collision_count_value: Variant = body.call("get_slide_collision_count")
	if not collision_count_value is int:
		return {}
	var collision_count: int = int(collision_count_value)
	var best_offset: float = 0.0
	var best_distance: float = INF
	var found: bool = false
	for collision_index: int in range(collision_count):
		var collision_value: Variant = body.call("get_slide_collision", collision_index)
		if not collision_value is KinematicCollision3D:
			continue
		var collision: KinematicCollision3D = collision_value as KinematicCollision3D
		var collider_node: Node = collision.get_collider() as Node
		var search_node: Node = collider_node
		for _parent_index: int in range(config.terrain_piece_anchor_parent_search + 1):
			if search_node == null:
				break
			if search_node.has_meta(config.terrain_piece_anchor_metadata):
				var anchor_value: Variant = search_node.get_meta(config.terrain_piece_anchor_metadata)
				var candidate_offset: float = 0.0
				var valid_anchor: bool = false
				if anchor_value is bool and bool(anchor_value) and search_node is Node3D:
					var anchor_node: Node3D = search_node as Node3D
					candidate_offset = (anchor_node.global_position - path_point).dot(plane_normal)
					valid_anchor = true
				elif anchor_value is Vector3 and search_node is Node3D:
					var local_anchor_node: Node3D = search_node as Node3D
					var anchor_position: Vector3 = local_anchor_node.to_global(anchor_value as Vector3)
					candidate_offset = (anchor_position - path_point).dot(plane_normal)
					valid_anchor = true
				elif anchor_value is float or anchor_value is int:
					candidate_offset = float(anchor_value)
					valid_anchor = true
				if valid_anchor:
					var candidate_distance: float = abs(candidate_offset - current_offset)
					if candidate_distance < best_distance:
						best_offset = candidate_offset
						best_distance = candidate_distance
						found = true
				break
			search_node = search_node.get_parent()
	if not found:
		return {}
	return {"found": true, "offset": best_offset}


func _get_adaptive_plane_offset_state(
	body: Node3D,
	path_point: Vector3,
	plane_normal: Vector3,
	progress_state: Dictionary,
	influence: float,
	delta: float
) -> Dictionary:
	var body_offset: float = (body.global_position - path_point).dot(plane_normal)
	var initialized: bool = bool(progress_state.get("plane_offset_initialized", false))
	var current_offset: float = float(progress_state.get("plane_offset", 0.0))
	var captured_depth_offset: float = float(
		progress_state.get("captured_depth_offset", current_offset)
	)
	if not initialized:
		captured_depth_offset = body_offset if config.capture_entry_depth_offset else 0.0
		if config.adaptive_centerline_max_offset > 0.0:
			captured_depth_offset = clamp(
				captured_depth_offset,
				-config.adaptive_centerline_max_offset,
				config.adaptive_centerline_max_offset
			)
		current_offset = captured_depth_offset

	var target_offset: float = body_offset
	var depth_source_active: bool = false
	var depth_profile: Dictionary = _get_depth_offset_profile_target(
		body,
		path_point,
		plane_normal
	)
	var depth_profile_found: bool = bool(depth_profile.get("found", false))
	var centerline_max_offset_limit: float = config.adaptive_centerline_max_offset
	if (
		depth_profile_found
		and bool(depth_profile.get("override_centerline_offset_limit", false))
	):
		centerline_max_offset_limit = max(
			float(depth_profile.get("centerline_max_offset", 0.0)),
			0.0
		)
	if depth_profile_found:
		target_offset = float(depth_profile.get("offset", body_offset))
		depth_source_active = true
	else:
		var terrain_anchor: Dictionary = _get_terrain_piece_anchor_offset(
			body,
			path_point,
			plane_normal,
			current_offset
		)
		if bool(terrain_anchor.get("found", false)):
			target_offset = float(terrain_anchor.get("offset", body_offset))
			depth_source_active = true
		elif not config.follow_unanchored_surface_depth:
			target_offset = captured_depth_offset
			if config.captured_depth_transition_enabled:
				target_offset = lerp(
					captured_depth_offset,
					0.0,
					clamp(influence, 0.0, 1.0)
				)

	if centerline_max_offset_limit > 0.0:
		target_offset = clamp(
			target_offset,
			-centerline_max_offset_limit,
			centerline_max_offset_limit
		)

	var previous_source_active: bool = bool(progress_state.get("depth_source_active", false))
	var depth_release_active: bool = bool(progress_state.get("depth_release_active", false))
	if depth_source_active:
		depth_release_active = false
	elif previous_source_active:
		depth_release_active = true

	var direct_transition_rebase: bool = (
		not depth_source_active
		and not depth_release_active
		and not config.follow_unanchored_surface_depth
	)
	var response_strength: float = config.adaptive_centerline_strength
	var response_max_speed: float = config.adaptive_centerline_max_speed
	var response_deadzone: float = config.adaptive_centerline_deadzone
	var response_mode: int = int(depth_profile.get("centerline_response_mode", 0))
	if depth_profile_found and response_mode == 1:
		response_strength = max(float(depth_profile.get("centerline_strength", response_strength)), 0.0)
		response_max_speed = max(float(depth_profile.get("centerline_max_speed", response_max_speed)), 0.0)

	var may_adapt: bool = config.adaptive_centerline_enabled
	var profile_allows_airborne: bool = bool(depth_profile.get("allow_airborne", false))
	if (
		config.adaptive_centerline_grounded_only
		and not _body_is_attached(body)
		and not (depth_profile_found and profile_allows_airborne)
	):
		may_adapt = false
	if direct_transition_rebase:
		current_offset = target_offset
	elif depth_profile_found and response_mode == 2 and may_adapt:
		current_offset = target_offset
	else:
		if may_adapt and abs(target_offset - current_offset) > response_deadzone:
			var follow_weight: float = 1.0
			if response_strength > 0.0:
				follow_weight = 1.0 - exp(-response_strength * max(delta, 0.0))
			var followed_offset: float = lerp(current_offset, target_offset, follow_weight)
			if response_max_speed > 0.0:
				followed_offset = move_toward(
					current_offset,
					followed_offset,
					response_max_speed * max(delta, 0.0)
				)
			current_offset = followed_offset
		if depth_release_active and abs(target_offset - current_offset) <= response_deadzone:
			current_offset = target_offset
			depth_release_active = false

	if centerline_max_offset_limit > 0.0 and not depth_release_active:
		current_offset = clamp(
			current_offset,
			-centerline_max_offset_limit,
			centerline_max_offset_limit
		)
	return {
		"offset": current_offset,
		"captured_depth_offset": captured_depth_offset,
		"depth_source_active": depth_source_active,
		"depth_release_active": depth_release_active,
		"minimum_constraint_adherence": float(
			depth_profile.get("minimum_constraint_adherence", 0.0)
		) if depth_profile_found else 0.0,
		"override_position_constraint": bool(
			depth_profile.get("override_position_constraint", false)
		) if depth_profile_found else false,
		"strict_position_lock": bool(
			depth_profile.get("strict_position_lock", config.strict_position_lock)
		),
		"position_lock_strength": float(
			depth_profile.get("position_lock_strength", config.position_lock_strength)
		),
		"max_position_correction_speed": float(
			depth_profile.get(
				"max_position_correction_speed",
				config.max_position_correction_speed
			)
		),
		"position_lock_deadzone": float(
			depth_profile.get("position_lock_deadzone", config.position_lock_deadzone)
		),
	}


func _get_adherence_weight(closed: bool, offset: float, length: float) -> float:
	if closed:
		return 1.0
	var entry_weight: float = 1.0
	var exit_weight: float = 1.0
	if config.entry_blend_distance > 0.001:
		entry_weight = _ease_transition(offset / config.entry_blend_distance)
	if config.exit_blend_distance > 0.001:
		exit_weight = _ease_transition((length - offset) / config.exit_blend_distance)
	return clamp(min(entry_weight, exit_weight), 0.0, 1.0)


func _ease_transition(value: float) -> float:
	var weight: float = clamp(value, 0.0, 1.0)
	match config.transition_ease:
		AutomationRibbonTrait.TransitionEase.SMOOTHSTEP:
			return weight * weight * (3.0 - 2.0 * weight)
		AutomationRibbonTrait.TransitionEase.SMOOTHERSTEP:
			return weight * weight * weight * (weight * (weight * 6.0 - 15.0) + 10.0)
	return weight




func constrain_velocity(velocity: Vector3, delta: float, post_slide: bool = false) -> Vector3:
	if not sample or adherence <= 0.0:
		return velocity
	if bool(state.get("terrain_adjusted", false)) and not post_slide:
		var response: float = clampf(config.terrain_tangent_alignment_strength * maxf(delta, 0.0) * adherence, 0.0, 1.0)
		velocity -= sample.normal * velocity.dot(sample.normal) * response
	var weight: float = adherence
	if not config.strict_velocity_lock or adherence < 0.999:
		weight *= 1.0 - exp(-config.velocity_lock_strength * maxf(delta, 0.0)) if config.velocity_lock_strength > 0.0 else 1.0
	if post_slide and (not config.strict_velocity_lock or adherence < 0.999):
		return velocity
	var constrained: Vector3 = velocity - sample.normal * velocity.dot(sample.normal)
	if config.sideways_removal_speed_preservation > 0.0 and constrained.length() > 0.001:
		constrained *= lerpf(constrained.length(), velocity.length(), config.sideways_removal_speed_preservation) / constrained.length()
	return velocity.lerp(constrained, clampf(weight, 0.0, 1.0))


func constrain_position(body: CharacterBody3D, delta: float) -> bool:
	last_correction = Vector3.ZERO
	if not sample or adherence <= 0.0:
		return false
	var error: float = (sample.position - body.global_position).dot(sample.normal)
	var strict: bool = bool(offset_state.get("strict_position_lock", config.strict_position_lock)) and adherence >= 0.999
	var deadzone: float = float(offset_state.get("position_lock_deadzone", config.position_lock_deadzone))
	if not strict and absf(error) <= deadzone:
		return false
	var strength: float = float(offset_state.get("position_lock_strength", config.position_lock_strength))
	var fraction: float = 1.0 if strict else adherence * (1.0 - exp(-strength * maxf(delta, 0.0)) if strength > 0.0 else 1.0)
	var correction: Vector3 = sample.normal * error * fraction
	var maximum: float = float(offset_state.get("max_position_correction_speed", config.max_position_correction_speed))
	if maximum > 0.0:
		correction = correction.limit_length(maximum * maxf(delta, 0.0))
	if not correction:
		return false
	var collision: KinematicCollision3D = body.move_and_collide(correction, true)
	last_correction = collision.get_travel() if collision else correction
	body.global_position += last_correction
	return collision != null
