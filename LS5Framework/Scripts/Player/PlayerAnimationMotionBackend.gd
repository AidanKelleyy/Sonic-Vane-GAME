extends RefCounted
class_name PlayerAnimationMotionBackend

const BASE: String = "parameters/StateMachine/Motion"
const GROUND: String = BASE + "/Ground"
const AIR: String = BASE + "/Air"
const BALL: String = BASE + "/Ball"
const LANDING_STATES: Array[StringName] = [&"Land", &"LandMoving", &"LandHard"]

## Player state used to resolve movement presentation.
var _owner: Node
var _family: StringName = &""
var _fade_remaining: float = 0.0
var _tree_root: AnimationRootNode
var _pending_family: StringName = &""
var _pending_state: StringName = &""
var _landing_request: StringName = &""


func _init(owner: Node) -> void:
	_owner = owner


func dispose() -> void:
	_owner = null
	_tree_root = null


func clear_requests() -> void:
	_pending_family = &""
	_pending_state = &""
	_landing_request = &""


func is_enabled() -> bool:
	if not is_instance_valid(_owner) or not _owner.animation_profile or not _owner.animation_profile.hierarchical_motion or not _owner.anim_tree:
		return false
	var machine: AnimationNodeStateMachine = _owner._get_main_animation_state_machine()
	return machine and machine.has_node(&"Motion")


func ground_path() -> String:
	return GROUND if is_enabled() else PlayerAnimation.SM_GROUND


func map_parameter(path: String) -> String:
	if not is_enabled():
		return path
	if path.begins_with(PlayerAnimation.SM_GROUND + "/"):
		return path.replace(PlayerAnimation.SM_GROUND, GROUND)
	if path == PlayerAnimation.SM_BASE + "/FallBlend/blend_position":
		return AIR + "/FallBlend/blend_position"
	if has_local_landings() and path.begins_with(PlayerAnimation.SM_BASE + "/GAME_Land_Hard/"):
		return path.replace(PlayerAnimation.SM_BASE + "/GAME_Land_Hard", GROUND + "/LandHard")
	return path


func has_command(command: StringName) -> bool:
	if not is_enabled() or not _owner.animation_profile.motion_commands.has(command):
		return false
	var parts: PackedStringArray = String(_owner.animation_profile.motion_commands[command]).split("/", false, 1)
	if parts.is_empty() or StringName(parts[0]) not in [&"Ground", &"Air", &"Ball"]:
		return false
	var motion: AnimationNodeBlendTree = _owner._get_main_animation_state_machine().get_node(&"Motion")
	var machine: AnimationNodeStateMachine = motion.get_node(StringName(parts[0])) as AnimationNodeStateMachine
	return machine and (parts.size() == 1 or machine.has_node(StringName(parts[1])))


func apply_command(command: StringName) -> bool:
	if not has_command(command):
		return false
	_sync_tree()
	var presentation = _owner.get_animation_director().get_action_backend()
	if presentation.is_enabled() and not presentation.allows_body_request():
		return false
	var target: String = _owner.animation_profile.motion_commands[command]
	var parts: PackedStringArray = target.split("/", false, 1)
	var family: StringName = StringName(parts[0])
	var state: StringName = StringName(parts[1]) if parts.size() > 1 else &""
	if family == &"Ground" and state in LANDING_STATES:
		return request_landing(state)
	if command == &"CMD_JUMP" and _owner.uses_fall_blend_for_jump_animation():
		state = &"FallBlend"
	_request_family(family, state)
	_enter_motion()
	return true


func reset_playback() -> bool:
	if not is_enabled():
		return false
	_family = &""
	_fade_remaining = 0.0
	_pending_family = &""
	_pending_state = &""
	_landing_request = &""
	_tree_root = _owner.anim_tree.tree_root
	_select_family(_desired_family(), true)
	_owner.anim_state.start(&"Motion", true)
	var ground: AnimationNodeStateMachinePlayback = _owner.anim_tree.get(GROUND + "/playback")
	_restart_ground_entry()
	var air: AnimationNodeStateMachinePlayback = _owner.anim_tree.get(AIR + "/playback")
	air.start(&"FallBlend", true)
	_owner.ground_state = ground
	return true


func resume() -> void:
	var family: StringName = _desired_family()
	_request_family(family, &"FallBlend" if family == &"Air" else &"")
	_enter_motion()


func prepare_resume() -> void:
	if is_enabled() and _desired_family() == &"Ground":
		if _landing_request == &"" or _pending_family == &"":
			_restart_ground_entry(_landing_request)


func after_advance() -> void:
	if not is_enabled():
		return
	if is_landing() and _owner.ground_state.get_current_node() == _landing_request:
		_landing_request = &""


func _restart_ground_entry(entry: StringName = &"") -> void:
	_owner._pending_walk_stop = false
	var playback: AnimationNodeStateMachinePlayback = _owner.anim_tree.get(GROUND + "/playback")
	var state: StringName = entry if entry != &"" else (&"GroundMove" if _owner._get_lateral_speed_for_anim() > 1.5 else &"IDLE_ANIMATION")
	playback.start(state, true)


func has_local_landings() -> bool:
	if not is_enabled():
		return false
	var motion: AnimationNodeBlendTree = _owner._get_main_animation_state_machine().get_node(&"Motion")
	return motion.get_node(&"Ground").has_node(&"Land")


func is_landing() -> bool:
	return has_local_landings() and _owner.anim_state.get_current_node() == &"Motion" and get_family() == &"Ground" and _owner.ground_state and _owner.ground_state.get_current_node() in LANDING_STATES


func uses_landing_clock() -> bool:
	return is_landing() or (has_local_landings() and _owner.anim_state.get_current_node() == &"Motion" and get_family() == &"Ground" and _owner.ground_state and _owner.ground_state.get_fading_from_node() in LANDING_STATES)


func current_state() -> StringName:
	if is_landing():
		return _owner.animation_profile.presentation_state_names.get(StringName("Ground/" + String(_owner.ground_state.get_current_node())), &"Motion")
	return &"Motion"


func cancel_landing_request() -> void:
	_landing_request = &""
	_owner._landing_animation_pending = false
	if _pending_state in LANDING_STATES:
		_pending_family = &""
		_pending_state = &""


func request_landing(state: StringName) -> bool:
	var presentation = _owner.get_animation_director().get_action_backend()
	if not has_local_landings() or state not in LANDING_STATES or (presentation.is_enabled() and not presentation.allows_body_request()):
		return false
	_sync_tree()
	_owner._landing_animation_pending = false
	_owner._pending_walk_stop = false
	_landing_request = state
	_owner.anim_tree.set(GROUND + "/conditions/LandingIdle", false)
	_owner.anim_tree.set(GROUND + "/conditions/LandingMoving", false)
	_request_family(&"Ground", state)
	_enter_motion()
	return true


func _update_landing_conditions(speed: float) -> void:
	var ready: bool = false
	if is_landing() and _landing_request == &"":
		var playback: AnimationNodeStateMachinePlayback = _owner.ground_state
		var destination: StringName = &"IDLE_ANIMATION" if speed <= 1.5 else &"GroundMove"
		var overlap: float = _landing_recovery_overlap(playback.get_current_node(), destination)
		var length: float = playback.get_current_length()
		var recovering: bool = length > 0.001 and playback.get_current_play_position() >= maxf(length - overlap, 0.0) - 0.001
		var locked: bool = _owner.has_action_landing_animation_override()
		ready = recovering and not locked and float(_owner.anim_tree.get(BASE + "/Clock/scale")) > 0.0
		if playback.get_current_node() != &"LandMoving" and not locked:
			ready = ready or _owner._move_input.length_squared() > 0.000001 or speed >= 0.5
	_owner.anim_tree.set(GROUND + "/conditions/LandingIdle", ready and speed <= 1.5)
	_owner.anim_tree.set(GROUND + "/conditions/LandingMoving", ready and speed > 1.5)


func _landing_recovery_overlap(source: StringName, destination: StringName) -> float:
	var motion: AnimationNodeBlendTree = _owner._get_main_animation_state_machine().get_node(&"Motion")
	var ground: AnimationNodeStateMachine = motion.get_node(&"Ground")
	for index: int in ground.get_transition_count():
		if ground.get_transition_from(index) == source and ground.get_transition_to(index) == destination:
			return maxf(ground.get_transition(index).xfade_time, 0.0)
	return 0.0


func _sync_tree() -> void:
	var tree: AnimationTree = _owner.anim_tree
	if _tree_root != tree.tree_root:
		_tree_root = tree.tree_root
		_family = &""
		_fade_remaining = 0.0
		_pending_family = &""
		_pending_state = &""
		_landing_request = &""
	_owner.ground_state = tree.get(GROUND + "/playback")


func update(delta: float) -> void:
	if not is_enabled():
		return
	_sync_tree()
	var tree: AnimationTree = _owner.anim_tree
	var speed: float = _owner._get_lateral_speed_for_anim()
	var ground_conditions: Dictionary[StringName, bool] = {
		&"StartMoving": speed > 1.0,
		&"StartFast": speed > 1.5,
		&"StartIdle": speed <= 1.5,
		&"ResumeMoving": speed >= 1.5,
		&"Slow": speed < 1.0,
		&"StopLeft": not _owner._last_walk_foot_left and _owner._pending_walk_stop and speed < 1.0,
		&"StopRight": _owner._last_walk_foot_left and _owner._pending_walk_stop and speed < 1.0,
		&"Skidding": _owner.has_state(_owner.STATE_SKIDDING),
		&"NotSkidding": not _owner.has_state(_owner.STATE_SKIDDING),
	}
	for condition: StringName in ground_conditions:
		tree.set(GROUND + "/conditions/" + String(condition), ground_conditions[condition])
	var falling: bool = _owner._vertical_speed < -maxf(_owner.fall_vertical_speed_threshold, 0.0)
	tree.set(AIR + "/conditions/Falling", falling or _owner.has_state(_owner.STATE_JUMP_FALL_BLEND))
	var rate: float = maxf(float(tree.get(BASE + "/Clock/scale")) * float(tree.get("parameters/MoveTimeScale/scale")), 0.0)
	_fade_remaining = maxf(_fade_remaining - maxf(delta, 0.0) * rate, 0.0)
	var desired: StringName = _desired_family()
	if has_local_landings():
		var blocked: bool = not _owner.attached or desired != &"Ground" or _owner.has_action_landing_animation_override() or _owner._rail_active or _owner._rail_switch_active
		if blocked:
			_owner._landing_animation_pending = false
			_landing_request = &""
		elif _owner._landing_animation_pending:
			var state: StringName = &"LandHard" if _owner.is_ground_hit_hard() else (&"LandMoving" if _owner.should_play_moving_landing_animation() else &"Land")
			if not request_landing(state):
				_owner._landing_animation_pending = false
	if _pending_family != &"" and _pending_family != desired:
		_pending_family = &""
		_pending_state = &""
	if _pending_family != &"":
		_request_family(_pending_family, _pending_state)
	else:
		_select_family(desired)
	if has_local_landings():
		_update_landing_conditions(speed)
		if uses_landing_clock() or _landing_request != &"":
			var action_rate: float = maxf(_owner.animation_profile.action_playback_scale, 0.0)
			if _owner._active_action and is_instance_valid(_owner._active_action):
				action_rate *= maxf(_owner._active_action.get_animation_speed_multiplier(), 0.0)
			tree.set(BASE + "/Clock/scale", action_rate)
		if _owner.anim_state.get_current_node() in [&"Start", &""]:
			_owner.anim_state.start(&"Motion")
		return
	var current: StringName = _owner.get_animation_director().get_current_state()
	var landing_active: bool = current in [&"LAND", &"LAND_MOVING", &"GAME_Land_Hard", &"To_Any_Grounded_State"]
	if not _owner.attached or landing_active or _owner.has_action_landing_animation_override():
		_owner._landing_animation_pending = false
	var enter_landing: bool = _owner.attached and _owner._landing_animation_pending and not _owner.rolling and not _owner.has_action_landing_animation_override()
	var presentation = _owner.get_animation_director().get_action_backend()
	if presentation.is_enabled():
		if current in [&"Start", &""]:
			_owner.anim_state.start(&"Motion")
		elif current == &"Motion" and enter_landing:
			var command: StringName = &"GAME_Land_Hard" if _owner.is_ground_hit_hard() else (&"LAND_MOVING" if _owner.should_play_moving_landing_animation() else &"LAND")
			presentation.apply_command(command)
		return
	var gates: Dictionary[StringName, bool] = {
		&"EnterRail": _owner._rail_active or _owner._rail_switch_active,
		&"EnterSpindash": _owner._spindash_charging and not _owner._rail_active,
		&"EnterRailSpindash": _owner._rail_active and _owner._spindash_charging,
		&"EnterDrift": _owner.has_state(_owner.STATE_DRIFT),
		&"EnterBounce": _owner._bounce_state == _owner.BounceState.BOUNCE,
		&"EnterStomp": _owner._bounce_state == _owner.BounceState.STOMP,
		&"EnterDash": _owner._jump_dash_recent_timer > 0.0 and not _owner.has_state(_owner.STATE_JUMP_FALL_BLEND),
	}
	for condition: StringName in gates:
		tree.set(PlayerAnimation.SM_BASE + "/conditions/" + String(condition), not _owner._is_dead and gates[condition])
	if current == &"Start" or current == &"":
		_owner.anim_state.start(&"Motion")
	elif current == &"Motion" and enter_landing:
		var landing: StringName = &"GAME_Land_Hard" if _owner.is_ground_hit_hard() else (&"LAND_MOVING" if _owner.should_play_moving_landing_animation() else &"LAND")
		_owner.anim_state.travel(landing)
	if not _owner.attached:
		_owner._landing_animation_pending = false


func get_family() -> StringName:
	if not is_enabled():
		return &""
	return StringName(_owner.anim_tree.get(BASE + "/Select/current_state"))


func is_ground_moving() -> bool:
	return is_enabled() and _owner.anim_state.get_current_node() == &"Motion" and get_family() == &"Ground" and _owner.ground_state and _owner.ground_state.get_current_node() == &"GroundMove"


func get_active_node() -> AnimationNode:
	if not is_enabled() or _owner.anim_state.get_current_node() != &"Motion":
		return null
	var family: StringName = get_family()
	if family == &"":
		family = _desired_family()
	var motion: AnimationNodeBlendTree = _owner._get_main_animation_state_machine().get_node(&"Motion")
	var machine: AnimationNodeStateMachine = motion.get_node(family)
	var playback: AnimationNodeStateMachinePlayback = _owner.anim_tree.get(BASE + "/" + String(family) + "/playback")
	var state: StringName = playback.get_current_node()
	return machine.get_node(state) if state != &"" and machine.has_node(state) else null


func _desired_family() -> StringName:
	if _owner.rolling or _owner.has_state(_owner.STATE_ROLL):
		return &"Ball"
	return &"Ground" if _owner.attached else &"Air"


func _select_family(family: StringName, force: bool = false, entry: StringName = &"") -> bool:
	if family == _family:
		return true
	if not force and _fade_remaining > 0.0:
		return false
	var tree: AnimationTree = _owner.anim_tree
	if _family != &"":
		var motion: AnimationNodeBlendTree = _owner._get_main_animation_state_machine().get_node(&"Motion")
		var selector: AnimationNodeTransition = motion.get_node(&"Select")
		_fade_remaining = selector.xfade_time
	if family == &"Air" and _family != &"":
		var playback: AnimationNodeStateMachinePlayback = tree.get(AIR + "/playback")
		playback.start(&"FallBlend", true)
	if family == &"Ground":
		_restart_ground_entry(entry)
	_family = family
	tree.set(BASE + "/Select/transition_request", family)
	return true


func _request_family(family: StringName, state: StringName) -> void:
	if not _select_family(family, false, state):
		_pending_family = family
		_pending_state = state
		return
	_pending_family = &""
	_pending_state = &""
	if state == &"":
		return
	var playback: AnimationNodeStateMachinePlayback = _owner.anim_tree.get(BASE + "/" + String(family) + "/playback")
	if family == &"Ground" and state in LANDING_STATES:
		playback.start(state, true)
		return
	if _owner.anim_state.get_current_node() == &"Motion" and playback.get_current_node() != state and playback.get_current_node() not in [&"", &"Start"]:
		playback.travel(state)
	else:
		playback.start(state, true)


func _enter_motion() -> void:
	var presentation = _owner.get_animation_director().get_action_backend()
	if presentation.is_enabled():
		presentation.resume_motion(&"interrupted")
		return
	if _owner.anim_state.get_current_node() != &"Motion":
		_owner.anim_state.travel(&"Motion")
