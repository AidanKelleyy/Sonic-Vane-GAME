extends ObjectMotionSafety3D
class_name ObjectFracturePieceSafety

func setup(body: RigidBody3D, _collision_mask: int, _radius: float, separation: float, _step: float, _bounce: float, _friction: float, _up: Vector3) -> void:
	_body = body
	skin = maxf(separation, 0.001)
	reset_history()
