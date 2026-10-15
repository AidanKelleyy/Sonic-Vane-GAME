extends Node
class_name ObjectMotionSafety3D

## Enables supplemental sweeps using the body's collision shapes.
@export var enabled: bool = true
## Maximum displacement treated as physical motion rather than teleportation.
@export var teleport_distance: float = 200.0
## Separation margin used by shape sweeps.
@export var skin: float = 0.02
## Minimum speed requiring supplemental sweeps. Zero checks all motion.
@export var minimum_speed: float = 0.0

var _body: RigidBody3D
var _previous_transform: Transform3D = Transform3D.IDENTITY

func _ready() -> void:
	_body = get_parent() as RigidBody3D
	process_physics_priority = 30
	reset_history()

func reset_history() -> void:
	if is_instance_valid(_body) and _body.is_inside_tree():
		_previous_transform = _body.global_transform

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_body):
		return
	var current: Transform3D = _body.global_transform
	var motion: Vector3 = current.origin - _previous_transform.origin
	if not enabled or _body.freeze or _body.sleeping or motion.is_zero_approx() or motion.length() > teleport_distance:
		_previous_transform = current
		return
	if motion.length_squared() < minimum_speed * minimum_speed * delta * delta:
		_previous_transform = current
		return
	var parameters: PhysicsTestMotionParameters3D = PhysicsTestMotionParameters3D.new()
	parameters.from = _previous_transform
	parameters.motion = motion
	parameters.margin = maxf(skin, 0.001)
	var result: PhysicsTestMotionResult3D = PhysicsTestMotionResult3D.new()
	if PhysicsServer3D.body_test_motion(_body.get_rid(), parameters, result):
		var normal: Vector3 = result.get_collision_normal()
		if _body.linear_velocity.dot(normal) < -0.01:
			if _body.has_method("record_object_impact"):
				_body.call("record_object_impact", result.get_collision_point(), normal, _body.linear_velocity, result.get_collider() as Node3D)
			current.origin = _previous_transform.origin + result.get_travel()
			_body.global_transform = current
			_body.linear_velocity = _body.linear_velocity.slide(normal)
	_previous_transform = current
