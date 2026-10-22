extends RefCounted
class_name PlayerAnimationOverlayBackend

signal marker_consumed(generation: int, event_id: StringName, phase: StringName)
signal marker_rejected(generation: int, reason: StringName)

## Player carrying state and overlay playback references.
var _owner: Node
var _generation: int = 0
var _release_kind: StringName = &""
var _release_object: WeakRef
var _released: bool = false
var _pending_markers: Array[Dictionary] = []
var _gesture: StringName = &"Carry_Hold"
var _weight: float = 0.0
var _landing: bool = false


func _init(owner: Node) -> void:
	_owner = owner


func dispose() -> void:
	_pending_markers.clear()
	_release_object = null
	_owner = null


func is_enabled() -> bool:
	return is_instance_valid(_owner) and _owner.animation_profile and _owner.animation_profile.normalized_markers and _owner.get_animation_director().get_action_backend().is_enabled()


func reset() -> void:
	_generation += 1
	_pending_markers.clear()
	_release_kind = &""
	_release_object = null
	_released = false
	_landing = false
	_weight = 0.0
	_gesture = &"Carry_Hold"
	if is_enabled():
		_owner._carry_module._clear_pending_carry_put_down()
		_owner._carry_module._clear_pending_carry_throw()
		_owner.anim_tree.set("parameters/LandingRollOverride/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		_owner.anim_tree.set("parameters/CarryOverlay/blend_amount", 0.0)
		_playback().start(_gesture, true)


func request_carry(state: StringName) -> bool:
	if not is_enabled() or state not in [&"Carry_Hold", &"Carry_Pickup", &"Carry_PutDown", &"Carry_Throw"]:
		return false
	if state == &"Carry_Hold":
		_cancel_release(&"hold")
		return true
	if not _carry_allowed():
		_cancel_release(&"blocked")
		return false
	if state == _gesture and state == &"Carry_Pickup":
		return true
	_cancel_release(&"replaced")
	if state in [&"Carry_PutDown", &"Carry_Throw"]:
		if not _owner._carried_object or not is_instance_valid(_owner._carried_object):
			return false
		_generation += 1
		_release_kind = &"PutDown" if state == &"Carry_PutDown" else &"Throw"
		_owner._carry_put_down_pending_release = state == &"Carry_PutDown"
		_owner._carry_throw_pending_release = state == &"Carry_Throw"
		_release_object = weakref(_owner._carried_object)
		_released = false
	_gesture = state
	_playback().start(state, true)
	return true


func request_landing_roll() -> bool:
	if not is_enabled() or not _owner.get_animation_director().get_action_backend().allows_body_request():
		return false
	if _landing or bool(_owner.anim_tree.get("parameters/LandingRollOverride/active")):
		return true
	_cancel_release(&"landing")
	_owner.get_animation_director().get_action_backend().resume_motion(&"landing")
	_owner.get_animation_director().get_motion_backend().resume()
	var playback: AnimationNodeStateMachinePlayback = _owner.anim_tree.get("parameters/LandingRollAnimation/playback")
	playback.start(&"Roll", true)
	_owner.anim_tree.set("parameters/LandingRollOverride/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_landing = true
	return true


func landing_active() -> bool:
	return is_enabled() and (_landing or bool(_owner.anim_tree.get("parameters/LandingRollOverride/active")))


func interrupt(reason: StringName) -> void:
	if not is_enabled():
		return
	_cancel_release(reason)
	_landing = false
	_owner.anim_tree.set("parameters/LandingRollOverride/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT if reason in [&"reaction", &"reset"] else AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	if reason == &"reaction":
		_weight = 0.0
		_owner.anim_tree.set("parameters/CarryOverlay/blend_amount", 0.0)


func capture_marker(event_id: StringName, phase: StringName) -> void:
	if not is_enabled() or _owner.get_animation_director().is_remote_playback() or event_id != &"carry_release":
		return
	if _pending_markers.size() >= 2:
		return
	_pending_markers.append({"generation": _generation, "phase": phase, "object": _release_object.get_ref() if _release_object else null})


func update(delta: float) -> void:
	if not is_enabled():
		return
	var carrying: bool = _owner._carried_object and is_instance_valid(_owner._carried_object)
	if _release_kind != &"" and (not _carry_allowed() or not _release_object or _release_object.get_ref() != _owner._carried_object):
		_cancel_release(&"interrupted")
	if _landing and (not _owner.attached or _owner.rolling):
		_landing = false
		_owner.anim_tree.set("parameters/LandingRollOverride/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	var allowed: bool = carrying and _carry_allowed()
	var speed: float = maxf(_owner.carry_hold_blend_speed, 0.0)
	_weight = (1.0 if allowed else 0.0) if speed <= 0.0 or delta <= 0.0 else move_toward(_weight, 1.0 if allowed else 0.0, delta * speed)
	_owner.anim_tree.set("parameters/CarryOverlay/blend_amount", _weight)
	_owner.anim_tree.set("parameters/CarryClock/scale", maxf(_owner.animation_profile.carry_playback_scale, 0.0))
	_owner.anim_tree.set("parameters/LandingClock/scale", maxf(_owner.animation_profile.action_playback_scale, 0.0))
	_owner._carry_hold_blend_value = _weight


func after_advance() -> void:
	if not is_enabled():
		return
	var markers: Array[Dictionary] = _pending_markers.duplicate()
	_pending_markers.clear()
	for marker: Dictionary in markers:
		var generation: int = marker.generation
		if generation != _generation or marker.phase != _release_kind or marker.object != _owner._carried_object or not _release_kind or _released or not _carry_allowed():
			marker_rejected.emit(generation, &"stale_or_blocked")
			continue
		_released = true
		var kind: StringName = _release_kind
		_release_kind = &""
		_release_object = null
		if kind == &"PutDown":
			_owner._carry_module.release_carried_object_from_put_down_animation()
		else:
			_owner._carry_module.release_carried_object_from_throw_animation()
		marker_consumed.emit(generation, &"carry_release", kind)
	if _landing and not bool(_owner.anim_tree.get("parameters/LandingRollOverride/active")) and int(_owner.anim_tree.get("parameters/LandingRollOverride/request")) == AnimationNodeOneShot.ONE_SHOT_REQUEST_NONE:
		_landing = false
	var playback: AnimationNodeStateMachinePlayback = _playback()
	if _gesture != &"Carry_Hold" and playback.get_current_length() > 0.001 and playback.get_current_play_position() >= playback.get_current_length() - 0.001:
		if _release_kind != &"":
			_cancel_release(&"missing_marker")
		else:
			_gesture = &"Carry_Hold"
			playback.start(_gesture, true)


func _carry_allowed() -> bool:
	var state: StringName = _owner.get_animation_director().get_current_state()
	return not _owner._is_dead and not _owner._hurt_active and not landing_active() and state in [&"Motion", &"LAND", &"LAND_MOVING", &"GAME_Land_Hard", &"Start", &""]


func _cancel_release(reason: StringName) -> void:
	if _release_kind != &"":
		marker_rejected.emit(_generation, reason)
	_generation += 1
	_release_kind = &""
	_release_object = null
	_released = false
	_gesture = &"Carry_Hold"
	if is_enabled():
		_owner._carry_module._clear_pending_carry_put_down()
		_owner._carry_module._clear_pending_carry_throw()
		_playback().start(_gesture, true)


func _playback() -> AnimationNodeStateMachinePlayback:
	return _owner.anim_tree.get("parameters/CarryAnimation/playback")
