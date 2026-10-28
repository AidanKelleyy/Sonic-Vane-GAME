extends RefCounted
class_name AutomationSession

## Source supplying this player's route configuration.
var source_ref: WeakRef
var source_id: int = 0
var activation_frame: int = 0
var activation_sequence: int = 0
var sample: AutomationSample
var unwrapped_progress: float = 0.0
var signed_speed: float = 0.0
var direction: int = 1
var elapsed: float = 0.0
var previous_position: Vector3 = Vector3.ZERO
var release_reason: StringName = &""
var route_state: Dictionary = {}
var marker_states: Dictionary = {}


func get_source() -> Node3D:
	return source_ref.get_ref() as Node3D if source_ref else null


func update_tracking(value: AutomationSample, sampler: AutomationPathSampler, velocity: Vector3,
		intent: Vector3, delta: float, speed_deadband: float, input_deadband: float) -> void:
	var predicted: float = unwrapped_progress + signed_speed * maxf(delta, 0.0)
	if not sample or sample.revision != value.revision:
		unwrapped_progress = value.distance
	elif sampler.closed:
		unwrapped_progress = predicted + sampler.distance_delta(sampler.wrap_distance(predicted), value.distance)
	else:
		unwrapped_progress = value.distance
	sample = value
	signed_speed = velocity.dot(value.tangent)
	var input_speed: float = intent.dot(value.tangent)
	if absf(signed_speed) > speed_deadband:
		direction = 1 if signed_speed > 0.0 else -1
	elif absf(input_speed) > input_deadband:
		direction = 1 if input_speed > 0.0 else -1
	previous_position = value.position
	elapsed += maxf(delta, 0.0)


func get_travel_tangent() -> Vector3:
	return sample.tangent * float(direction) if sample and sample.valid else Vector3.ZERO
