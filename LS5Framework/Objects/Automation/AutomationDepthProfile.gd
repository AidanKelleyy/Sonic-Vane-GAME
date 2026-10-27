@tool
extends AutomationSplineCore
class_name AutomationDepthProfile

enum CenterlineResponseMode { INHERIT, OVERRIDE, IMMEDIATE }

## Uses cubic positions after connected profile branch selection.
@export var cubic_profile_sampling: bool = true

## Lets endpoint volumes activate in either travel direction. Disabled uses Start to enter and End to release.
@export var bidirectional_endpoint_areas: bool = true

## Main route receiving this depth profile. Empty uses the parent.
@export_node_path("Node3D") var automation_spline_path: NodePath = NodePath("")
## Distance that releases profile tracking. Zero disables the limit.
@export_range(0.0, 10000.0, 0.1) var failsafe_exit_distance: float = 0.0

@export_group("Depth Curve")
## Additional signed depth applied to the sampled profile.
@export_range(-10000.0, 10000.0, 0.1, "suffix:m") var depth_bias: float = 0.0
## Reverses the sampled depth around the main spline centerline.
@export var reverse_depth: bool = false
## Allows the profile target to continue updating while the body is airborne.
@export var follow_while_airborne: bool = false

@export_group("Adherence")
## Selects whether this profile inherits, overrides, or bypasses adaptive centerline smoothing.
@export var centerline_response_mode: CenterlineResponseMode = CenterlineResponseMode.INHERIT
## Centerline response speed used in Override mode. Zero follows the profile immediately.
@export_range(0.0, 1000.0, 0.1, "or_greater") var centerline_strength: float = 40.0
## Maximum centerline movement speed used in Override mode. Zero removes the limit.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m/s") var centerline_max_speed: float = 40.0
## Uses this profile's centerline offset limit instead of the main 2.5D spline limit.
@export var override_centerline_offset_limit: bool = false
## Maximum absolute profile offset when its limit override is enabled. Zero removes the limit.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m") var centerline_max_offset: float = 0.0
## Minimum main-section adherence applied while this profile is active.
@export_range(0.0, 1.0, 0.01) var minimum_constraint_adherence: float = 0.0
## Uses this profile's position constraint settings instead of the main 2.5D spline settings.
@export var override_position_constraint: bool = false
## Snaps final sideways error to the active profile plane at full adherence.
@export var strict_position_lock: bool = true
## Position response speed used when Override Position Constraint is enabled.
@export_range(0.0, 1000.0, 0.1, "or_greater") var position_lock_strength: float = 40.0
## Maximum position correction speed used when Override Position Constraint is enabled. Zero removes the limit.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m/s") var max_position_correction_speed: float = 0.0
## Position error ignored outside the strict core when Override Position Constraint is enabled.
@export_range(0.0, 1.0, 0.001, "or_greater", "suffix:m") var position_lock_deadzone: float = 0.005



func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group(&"AutomationDepthProfiles")
	_setup_live_edit()
	_bind_path()
	process_physics_priority = -100


func evaluate(body: Node3D, source: AutomationSplineCore, main_path_point: Vector3, main_plane_normal: Vector3, state: Dictionary) -> Dictionary:
	var target: Node = get_node_or_null(automation_spline_path) if automation_spline_path else get_parent()
	if target != source or not accepts(body):
		state.clear()
		return {}
	if int(state.get("revision", -1)) != activation_revision:
		state.clear()
		state["revision"] = activation_revision
	var previous: Vector3 = state.get("previous", body.global_position)
	var initialized: bool = state.has("previous")
	if activation_mode == ActivationMode.ENDPOINTS:
		_update_endpoint_activation(body, previous, state, initialized)
	elif activation_mode == ActivationMode.OCCUPANCY:
		state["active"] = is_occupied(body)
	else:
		state["active"] = true
	state["previous"] = body.global_position
	if not bool(state.get("active", false)):
		state.erase("distance")
		return {}
	var window: float = tracking_span(previous.distance_to(body.global_position))
	var value: AutomationSample = sampler.closest(body.global_position, float(state.get("distance", -1.0)), window, -1.0, recovery_distance)
	if not value.valid or (failsafe_exit_distance > 0.0 and value.spatial_error > failsafe_exit_distance):
		state.erase("distance")
		state["active"] = false
		return {}
	if cubic_profile_sampling:
		value = sampler.smooth_sample(value)
	state["distance"] = value.distance
	var target_offset: float = (value.position - main_path_point).dot(main_plane_normal)
	if reverse_depth:
		target_offset = -target_offset
	target_offset += depth_bias
	var profile_distance: float = value.spatial_error
	return {
		"found": true,
		"offset": target_offset,
		"priority": priority,
		"allow_airborne": follow_while_airborne,
		"profile_distance": profile_distance,
		"centerline_response_mode": int(centerline_response_mode),
		"centerline_strength": centerline_strength,
		"centerline_max_speed": centerline_max_speed,
		"override_centerline_offset_limit": override_centerline_offset_limit,
		"centerline_max_offset": centerline_max_offset,
		"minimum_constraint_adherence": minimum_constraint_adherence,
		"override_position_constraint": override_position_constraint,
		"strict_position_lock": strict_position_lock,
		"position_lock_strength": position_lock_strength,
		"max_position_correction_speed": max_position_correction_speed,
		"position_lock_deadzone": position_lock_deadzone,
	}


func _update_endpoint_activation(body: Node3D, previous: Vector3, state: Dictionary, initialized: bool) -> void:
	var events: Array[Dictionary] = []
	for index: int in 2:
		var gate: Area3D = get_node_or_null(start_gate_path if index == 0 else end_gate_path) as Area3D
		if not gate or (body is CollisionObject3D and not (body as CollisionObject3D).collision_layer & gate.collision_mask):
			continue
		var key: String = "inside_%d" % index
		var inside: bool = contains_gate_point(gate, body.global_position)
		var fraction: float = _gate_entry(gate, previous, body.global_position)
		if initialized and not bool(state.get(key, false)) and fraction >= 0.0:
			events.append({"fraction": fraction, "index": index})
		state[key] = inside
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.fraction) < float(b.fraction))
	for event: Dictionary in events:
		if not bidirectional_endpoint_areas:
			state["active"] = int(event.index) == 0
		else:
			var crossing: Vector3 = previous.lerp(body.global_position, float(event.fraction))
			var value: AutomationSample = sampler.closest(crossing, float(state.get("distance", -1.0)), tracking_window)
			var signed_travel: float = (body.global_position - previous).dot(value.tangent)
			if absf(signed_travel) > 0.000001:
				state["active"] = signed_travel > 0.0 if int(event.index) == 0 else signed_travel < 0.0


func _gate_entry(gate: Area3D, from: Vector3, to: Vector3) -> float:
	return preload("res://LS5Framework/Scripts/Player/Automation/AutomationGateSweep.gd")._gate_entry(gate, from, to)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = super._get_configuration_warnings()
	var target: Node = get_node_or_null(automation_spline_path) if automation_spline_path else get_parent()
	if not target is AutomationSplineCore or target is AutomationDepthProfile:
		warnings.append("A main automation route is required as the profile target.")
	return warnings


func _validate_property(property: Dictionary) -> void:
	if property.name in ["steering_traits", "position_traits", "speed_traits", "surface_traits", "input_traits", "transition_traits", "influence_traits", "camera_traits", "release_at_path_ends", "direction_policy", "capture_distance"]:
		property.usage = PROPERTY_USAGE_NO_EDITOR
