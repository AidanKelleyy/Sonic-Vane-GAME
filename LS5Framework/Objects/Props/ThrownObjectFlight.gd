extends RefCounted

const Targeting = preload("res://LS5Framework/Scripts/Player/ThrownObjectTargeting.gd")

## Prop receiving flight corrections through its active physics mode.
var _prop: ObjectPhysicsBody3D
## Target committed at release; flight never acquires another target.
var _target: WeakRef
var _remaining: float = 0.0
var _budget: float = 0.0
var _acceleration: float = 0.0
var _max_deviation: float = 0.0
var _lead_max_speed: float = 0.0
var _lead_enabled: bool = true
var _intercept: Vector3 = Vector3.ZERO
var _refresh: float = 0.0
var _desired_acceleration: Vector3 = Vector3.ZERO


func _init(prop: ObjectPhysicsBody3D) -> void:
	_prop = prop


func start(target: Node3D, solution: Dictionary, settings: Dictionary) -> void:
	_target = weakref(target)
	_remaining = float(solution["time"])
	_intercept = solution["destination"]
	_budget = maxf(float(settings["budget"]), 0.0)
	_acceleration = maxf(float(settings["acceleration"]), 0.0)
	_max_deviation = maxf(float(settings["max_deviation"]), 0.0)
	_lead_max_speed = maxf(float(settings["lead_max_speed"]), 0.0)
	_lead_enabled = bool(settings["lead_enabled"])
	_refresh = 0.0
	_desired_acceleration = Vector3.ZERO
	Targeting.target_velocity(target, _lead_max_speed)


func stop() -> void:
	_target = null
	_remaining = 0.0
	_desired_acceleration = Vector3.ZERO


func is_active() -> bool:
	return _target and _remaining > 0.0 and _budget > 0.0


func update_velocity(velocity: Vector3, delta: float) -> Vector3:
	if not is_active():
		return velocity
	var target: Node3D = _target.get_ref() as Node3D
	if not Targeting.is_target_available(target, _prop) or _prop.is_carried() or _prop.anchored:
		stop()
		return velocity
	var prediction_time: float = _remaining
	_remaining -= delta
	if _prop.carry_physics_mode == ObjectPhysicsBody3D.CarryPhysicsMode.RIGID_BODY:
		prediction_time = _remaining
	if _remaining <= maxf(delta, 0.04):
		stop()
		return velocity
	var point: Vector3 = Targeting.target_position(target, _prop.global_position)
	var lead: Vector3 = Targeting.target_velocity(target, _lead_max_speed) if _lead_enabled else Vector3.ZERO
	var destination: Vector3 = point + lead * prediction_time
	if destination.distance_to(_intercept) > _max_deviation:
		stop()
		return velocity
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.05
		var motion: Dictionary = _prop.get_throw_prediction_parameters()
		if motion.is_empty():
			stop()
			return velocity
		var frames: int = maxi(roundi(prediction_time / float(motion["step"])), 1)
		var prediction_velocity: Vector3 = velocity
		if bool(motion.get("gravity_after_motion", false)):
			prediction_velocity += _prop.get_prop_gravity_vector() * delta
		var path: PackedVector3Array = Targeting.predict_path(_prop.global_position, prediction_velocity, frames, motion)
		var error: Vector3 = destination - path[path.size() - 1]
		_desired_acceleration = (error / maxf(prediction_time * 0.15, 0.03)).limit_length(_acceleration) if error.length() > 0.1 else Vector3.ZERO
	var correction: Vector3 = (_desired_acceleration * delta).limit_length(_budget)
	_budget = maxf(_budget - correction.length(), 0.0)
	return velocity + correction
