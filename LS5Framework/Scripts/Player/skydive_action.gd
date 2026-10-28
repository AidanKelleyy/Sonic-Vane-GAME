class_name SkydiveAction
extends CharacterAbility

enum SkydiveState {
	NONE,
	DIVE,
	GLIDE,
}

@export_group("Skydive")

@export_subgroup("Activation")
## Enables the skydive ability.
@export var skydive_enabled: bool = true

@export_subgroup("Movement/Dive")
## Gravity multiplier while holding dive, including during ascent.
@export var dive_gravity_multiplier: float = 2.6
## Downward terminal speed approached through aerodynamic drag.
@export var dive_max_down_speed: float = 220.0
## Maximum dive steering rate in degrees per second.
@export var dive_turn_rate: float = 75.0

@export_subgroup("Movement/Glide")
## Speed producing full pullout and float strength.
@export var glide_full_effect_speed: float = 140.0
## Horizontal contribution to pullout strength relative to downward speed.
@export_range(0.0, 1.0) var glide_horizontal_support: float = 0.7
## Pullout acceleration at full strength, in multiples of gravity.
@export var glide_pullout_acceleration: float = 6.0
## Minimum downward gravity fraction at full glide strength.
@export_range(0.05, 1.0) var glide_gravity_scale: float = 0.25
## Minimum downward speed targeted by the initial pullout.
@export var glide_min_sink_speed: float = 8.0
## Duration of the initial momentum conversion after release.
@export var glide_pullout_duration: float = 0.9
## Duration over which glide influence smoothly fades into ordinary falling.
@export var glide_effect_duration: float = 2.8
## Fraction of removed vertical kinetic energy retained as forward travel.
@export_range(0.0, 1.0) var glide_conversion_efficiency: float = 0.82
## Rate at which directional input trades remaining ascent for travel.
@export var glide_ascent_conversion_rate: float = 2.0
## Maximum glide steering rate in degrees per second.
@export var glide_turn_rate: float = 55.0
## Speed lost per radian of steering, as an exponential drag coefficient.
@export var glide_turn_drag: float = 0.22
## Continuous glide drag coefficient per second.
@export var glide_drag: float = 0.12
## Support strength below which a descending glide returns to ordinary falling.
@export_range(0.0, 0.1) var glide_exit_strength: float = 0.025
## Roll-spindash lockout applied when rolling out of skydive.
@export var roll_spindash_lockout: float = 0.6

@export_subgroup("Glide Recovery")
## Uninterrupted downward dive distance required to restore the glide allowance. Release discards recovery progress.
@export_range(1.0, 200.0, 0.5, "or_greater", "suffix:m") var glide_recovery_distance: float = 24.0

@export_subgroup("Combo")
## Distance traveled while skydiving before another combo entry is registered.
@export_range(0.1, 100.0, 0.1, "or_greater", "suffix:m") var skydive_combo_distance_units: float = 12.0
## Base score awarded for each skydive interval.
@export_range(0.0, 10000.0, 1.0, "or_greater") var skydive_combo_score: float = 75.0
## Combo time added for each skydive interval.
@export_range(0.0, 5.0, 0.05, "suffix:s") var skydive_combo_timer_add_seconds: float = 0.25

@export_subgroup("Action Chain Routes")
@export_multiline var on_roll_action_tooltip: String = "Route used when roll is held during skydive."
## Roll action used when leaving skydive with the roll binding.
@export var on_roll_action: NodePath

var state: int = SkydiveState.NONE
var glide_lift_effect_strength: float = 0.0
var skydive_combo_distance_accum: float = 0.0
var glide_entered_ascending: bool = false
var glide_elapsed: float = 0.0
var glide_entry_strength: float = 0.0
var glide_allowance: float = 1.0
var recovery_previous_position: Vector3 = Vector3.ZERO
var recovery_position_valid: bool = false
var recovery_was_diving: bool = false
var recovery_dive_distance: float = 0.0


func blocks_shared_movement_integration() -> bool:
	return true


func _on_action_initialized() -> void:
	action_id = &"skydive"
	input_action = &"ability_slot_02"
	trigger_mode = ActionTrigger.HOLD
	allow_when_inactive = true
	continuous_update = true


func continuous_physics_update(_delta: float) -> void:
	if not owner_player:
		return
	var position: Vector3 = owner_player.global_position
	var diving: bool = state == SkydiveState.DIVE and owner_player.get_current_action_id() == action_id
	if owner_player.attached:
		glide_allowance = 1.0
		recovery_dive_distance = 0.0
	elif recovery_position_valid and recovery_was_diving and diving:
		var descended: float = maxf(-(position - recovery_previous_position).dot(_get_gravity_up()), 0.0)
		recovery_dive_distance += descended
		if recovery_dive_distance >= maxf(glide_recovery_distance, 1.0):
			glide_allowance = 1.0
	else:
		recovery_dive_distance = 0.0
	recovery_previous_position = position
	recovery_position_valid = true
	recovery_was_diving = diving


func receives_fast_fall_horizontal_drag_by_default() -> bool:
	return false


func can_execute(_context: Dictionary = {}) -> bool:
	if owner_player == null:
		return false
	if not enabled or not skydive_enabled:
		return false
	if owner_player.has_method("is_insta_shield_input_consumed") and owner_player.is_insta_shield_input_consumed():
		return false
	if owner_player.attached:
		return false
	if owner_player.rolling and not (bool(_context.get("input_prompt", false)) and bool(_context.get("input_prompt_clear_active", false))):
		return false
	if owner_player.has_method("get_current_action_id") and owner_player.get_current_action_id() == &"propeller_flight":
		return false
	if owner_player._hurt_active:
		return false
	if owner_player._rail_active or owner_player._spline_active:
		return false
	if owner_player._spring_align_timer > 0.0:
		return false
	if owner_player._spring_action_lock_timer > 0.0:
		return false
	if owner_player._spring_movement_lock_timer > 0.0:
		return false
	if owner_player._spindash_charging:
		return false
	if owner_player._homing_active:
		return false
	if owner_player._bounce_state != owner_player.BounceState.NONE:
		return false
	return true


func execute(context: Dictionary = {}) -> bool:
	if not can_execute(context):
		return false
	if not activate(context):
		return false
	return true


func is_flight_action() -> bool:
	return true


func process_input_event(input_name: StringName, mode: ActionTrigger) -> bool:
	if input_name != input_action:
		return false
	if should_trigger_from_input(input_name, mode):
		return execute({"reason": &"skydive_input"})
	if mode == ActionTrigger.PRESSED and _can_reenter_from_terminal_animation():
		return execute({"reason": &"skydive_terminal_reenter"})
	return false


func on_action_enter(_context: Dictionary = {}) -> void:
	skydive_combo_distance_accum = 0.0
	_end_airborne_torque_for_skydive()
	_start_dive()


func on_action_exit(_next_action: CharacterAction) -> void:
	recovery_was_diving = false
	recovery_dive_distance = 0.0
	state = SkydiveState.NONE
	glide_elapsed = 0.0
	glide_entry_strength = 0.0
	glide_lift_effect_strength = 0.0
	glide_entered_ascending = false
	skydive_combo_distance_accum = 0.0


func physics_update_action(delta: float) -> void:
	if owner_player == null:
		return
	if owner_player.attached:
		_clear_to_neutral_air()
		return
	if _try_route_roll():
		return
	_update_skydive_combo(delta)
	if state == SkydiveState.DIVE:
		_update_dive(delta)
		return
	if state == SkydiveState.GLIDE:
		_update_glide(delta)
		return
	_clear_to_neutral_air()


func _update_skydive_combo(delta: float) -> void:
	if state == SkydiveState.NONE:
		return
	var distance_delta: float = owner_player.velocity.length() * maxf(owner_player.get_movement_delta(delta), 0.0)
	skydive_combo_distance_accum += distance_delta
	var distance_interval: float = maxf(skydive_combo_distance_units, 0.1)
	if skydive_combo_distance_accum < distance_interval:
		return
	skydive_combo_distance_accum -= distance_interval
	if owner_player.has_method("register_combo_feat"):
		owner_player.register_combo_feat(
			&"skydive",
			"Skydive",
			skydive_combo_score,
			skydive_combo_timer_add_seconds
		)


func _start_dive() -> void:
	recovery_dive_distance = 0.0
	recovery_was_diving = false
	var anim_state_name: StringName = &"Skydive_Enter"
	var entering_from_glide: bool = state == SkydiveState.GLIDE
	if entering_from_glide:
		anim_state_name = &"Skydive_Glide_To_Dive"
	state = SkydiveState.DIVE
	glide_elapsed = 0.0
	glide_entry_strength = 0.0
	glide_lift_effect_strength = 0.0
	glide_entered_ascending = false
	if not entering_from_glide:
		_request_skydive_command()
	_request_skydive_anim(anim_state_name)
	if owner_player != null and owner_player.has_method("remove_coyote_jump_eligibility"):
		owner_player.remove_coyote_jump_eligibility()


func _update_dive(delta: float) -> void:
	var dive_input_held: bool = input_action != &"" and SettingsManager.is_gameplay_action_pressed(String(input_action))
	if owner_player != null and owner_player.has_method("is_ability_binding_pressed"):
		dive_input_held = bool(owner_player.call("is_ability_binding_pressed", action_id, input_action))
	if not dive_input_held:
		_start_glide()
		_update_glide(delta)
		return
	_request_skydive_anim(&"Skydive_Dive")
	var step: float = maxf(owner_player.get_movement_delta(delta), 0.0)
	var velocity: Vector3 = owner_player.velocity
	var vertical: float = get_gravity_vertical_component(velocity)
	var gravity: float = get_owner_gravity_acceleration_vector().length() * maxf(dive_gravity_multiplier, 0.0)
	var terminal: float = maxf(dive_max_down_speed, 0.001)
	var downward: float = maxf(-vertical, 0.0)
	var acceleration: float = gravity * (1.0 - pow(downward / terminal, 2.0))
	vertical -= acceleration * step
	# Terminal drag approaches the limit without truncating entry momentum.
	if downward > terminal:
		vertical = minf(vertical, -terminal)
	else:
		vertical = maxf(vertical, -terminal)
	velocity = compose_gravity_vector(get_gravity_planar_component(velocity), vertical)
	owner_player.velocity = _steer_toward(velocity, _get_owner_move_direction(), _get_input_strength(), step, dive_turn_rate, glide_turn_drag * 0.25)


func _start_glide() -> void:
	recovery_dive_distance = 0.0
	recovery_was_diving = false
	state = SkydiveState.GLIDE
	glide_elapsed = (1.0 - glide_allowance) * maxf(glide_effect_duration, 0.001)
	glide_entry_strength = _get_glide_support(owner_player.velocity)
	glide_entered_ascending = get_gravity_vertical_component(owner_player.velocity) > 0.0
	_request_skydive_anim(&"Skydive_Dive_To_Glide")


func _update_glide(delta: float) -> void:
	var dive_input_held: bool = SettingsManager.is_gameplay_action_pressed(String(input_action))
	if owner_player.has_method("is_ability_binding_pressed"):
		dive_input_held = bool(owner_player.call("is_ability_binding_pressed", action_id, input_action))
	if dive_input_held:
		_start_dive()
		_update_dive(delta)
		return
	_request_skydive_anim(&"Skydive_Glide")
	var step: float = maxf(owner_player.get_movement_delta(delta), 0.0)
	owner_player.velocity = _integrate_glide(owner_player.velocity, _get_owner_move_direction(), _get_input_strength(), step)
	if glide_elapsed >= maxf(glide_effect_duration, 0.001) or (glide_lift_effect_strength < maxf(glide_exit_strength, 0.0) and get_gravity_vertical_component(owner_player.velocity) <= 0.0):
		_clear_to_neutral_air()


func _get_glide_support(velocity: Vector3) -> float:
	var support_speed: float = absf(get_gravity_vertical_component(velocity)) + get_gravity_planar_component(velocity).length() * maxf(glide_horizontal_support, 0.0)
	return clampf(support_speed / maxf(glide_full_effect_speed, 0.001), 0.0, 1.0)


func _integrate_glide(velocity: Vector3, input_direction: Vector3, input_strength: float, step: float) -> Vector3:
	var duration: float = maxf(glide_effect_duration, 0.001)
	var progress: float = clampf(glide_elapsed / duration, 0.0, 1.0)
	var influence: float = 1.0 - smoothstep(0.0, 1.0, progress)
	var strength: float = minf(_get_glide_support(velocity), glide_entry_strength) * influence
	glide_lift_effect_strength = strength
	var vertical: float = get_gravity_vertical_component(velocity)
	var gravity: float = get_owner_gravity_acceleration_vector().length()
	var direction: Vector3 = get_gravity_planar_component(input_direction).normalized()
	var control: float = clampf(input_strength, 0.0, 1.0) if direction else 0.0
	var pullout_progress: float = clampf(glide_elapsed / maxf(glide_pullout_duration, 0.001), 0.0, 1.0)
	var pullout: float = 1.0 - smoothstep(0.0, 1.0, pullout_progress)
	if glide_entered_ascending and vertical <= 0.0:
		glide_entered_ascending = false
	var next_vertical: float = vertical
	if glide_entered_ascending:
		next_vertical *= exp(-maxf(glide_ascent_conversion_rate, 0.0) * control * influence * step)
	elif vertical < -maxf(glide_min_sink_speed, 0.0):
		next_vertical = move_toward(vertical, -maxf(glide_min_sink_speed, 0.0), gravity * maxf(glide_pullout_acceleration, 0.0) * strength * pullout * step)
	velocity = _convert_vertical_momentum(velocity, next_vertical, direction, control)
	velocity = _steer_toward(velocity, direction, control * influence, step, glide_turn_rate, glide_turn_drag)
	# Gravity follows pullout so lift cannot continuously cancel descent.
	var gravity_scale: float = lerpf(1.0, clampf(glide_gravity_scale, 0.05, 1.0), strength) if next_vertical <= 0.0 else 1.0
	var planar: Vector3 = get_gravity_planar_component(velocity) * exp(-maxf(glide_drag, 0.0) * influence * step)
	vertical = get_gravity_vertical_component(velocity) - gravity * gravity_scale * step
	glide_elapsed = minf(glide_elapsed + maxf(step, 0.0), duration)
	glide_allowance = clampf(1.0 - glide_elapsed / duration, 0.0, 1.0)
	return compose_gravity_vector(planar, vertical)


func _convert_vertical_momentum(velocity: Vector3, next_vertical: float, direction: Vector3, control: float) -> Vector3:
	var vertical: float = get_gravity_vertical_component(velocity)
	var planar: Vector3 = get_gravity_planar_component(velocity)
	var energy_change: float = vertical * vertical - next_vertical * next_vertical
	if energy_change >= 0.0:
		if control > 0.0:
			var retained_energy: float = energy_change * clampf(glide_conversion_efficiency, 0.0, 1.0) * control
			# Solve the forward addition against existing drift to preserve the energy bound.
			var along: float = planar.dot(direction)
			if along >= 0.0:
				var addition: float = -along + sqrt(along * along + retained_energy)
				planar += direction * addition
	else:
		var available: float = planar.length_squared()
		var spent: float = minf(-energy_change, available)
		next_vertical = signf(next_vertical) * sqrt(vertical * vertical + spent)
		if available > 0.000001:
			planar *= sqrt(maxf(available - spent, 0.0) / available)
	return compose_gravity_vector(planar, next_vertical)


func _steer_toward(velocity: Vector3, direction: Vector3, strength: float, step: float, turn_rate: float, turn_drag: float) -> Vector3:
	var up: Vector3 = _get_gravity_up()
	var planar: Vector3 = get_gravity_planar_component(velocity)
	direction = get_gravity_planar_component(direction).normalized()
	if not direction or planar.length_squared() < 0.000001:
		return velocity
	var angle: float = planar.normalized().signed_angle_to(direction, up)
	var limit: float = deg_to_rad(maxf(turn_rate, 0.0)) * clampf(strength, 0.0, 1.0) * step
	var turn: float = clampf(angle, -limit, limit)
	planar = planar.rotated(up, turn) * exp(-absf(turn) * maxf(turn_drag, 0.0))
	return compose_gravity_vector(planar, get_gravity_vertical_component(velocity))


func _get_owner_move_direction() -> Vector3:
	owner_player._update_control_basis(_get_gravity_up(), false, false, get_gravity_planar_component(owner_player.velocity))
	owner_player._compute_move_direction()
	return owner_player.get_move_direction()


func _get_input_strength() -> float:
	return clampf(owner_player._move_input.length(), 0.0, 1.0)


func _try_route_roll() -> bool:
	var roll_slot: StringName = &"ability_slot_04"
	if owner_player.has_method("get_ability_input_slot"):
		roll_slot = owner_player.get_ability_input_slot(&"roll", roll_slot)
	if owner_player.has_method("ability_binding_uses_slot") and owner_player.has_method("is_ability_binding_pressed"):
		var roll_contributes_to_dive: bool = bool(owner_player.call("ability_binding_uses_slot", action_id, roll_slot, input_action))
		if roll_contributes_to_dive and bool(owner_player.call("is_ability_binding_pressed", action_id, input_action)):
			return false
	if not SettingsManager.is_gameplay_action_pressed(String(roll_slot)):
		return false
	var roll_action: CharacterAction = _get_roll_action()
	if roll_action == null:
		return false
	if not roll_action.execute({"reason": &"skydive_roll", "source_action": action_id}):
		return false
	if owner_player.has_method("set_spindash_roll_route_lockout"):
		owner_player.set_spindash_roll_route_lockout(roll_spindash_lockout)
	return true


func _get_roll_action() -> CharacterAction:
	if on_roll_action != NodePath() and has_node(on_roll_action):
		var roll_node: Node = get_node(on_roll_action)
		if roll_node is CharacterAction:
			return roll_node
	for action in owner_player._actions:
		if action is RollAction:
			return action
	return null


func _get_gravity_up() -> Vector3:
	return get_owner_gravity_up()


func _clear_to_neutral_air() -> void:
	state = SkydiveState.NONE
	glide_elapsed = 0.0
	glide_entry_strength = 0.0
	glide_lift_effect_strength = 0.0
	if owner_player == null:
		return
	if owner_player.attached:
		_request_skydive_anim(&"Skydive_Exit")
		if owner_player.has_method("clear_active_action"):
			owner_player.clear_active_action()
		return
	_request_skydive_anim(&"Skydive_Exit")
	if owner_player.has_method("activate_neutral_air_action"):
		owner_player.activate_neutral_air_action({"reason": &"skydive_finished", "source_action": action_id})


func _request_skydive_anim(state_name: StringName) -> void:
	if owner_player == null:
		return
	if owner_player.has_method("request_skydive_animation_state"):
		owner_player.request_skydive_animation_state(state_name)


func _request_skydive_command() -> void:
	if owner_player == null:
		return
	if owner_player.has_method("play_action_command_if_exists"):
		owner_player.play_action_command_if_exists(action_id)


func _end_airborne_torque_for_skydive() -> void:
	if owner_player == null:
		return
	if owner_player.has_method("_gracefully_end_airborne_torque"):
		owner_player.call("_gracefully_end_airborne_torque")


func _can_reenter_from_terminal_animation() -> bool:
	if owner_player == null:
		return false
	if owner_player.attached:
		return false
	if owner_player.get_current_action_id() == action_id:
		return false
	var canceling: bool = owner_player.has_method("_is_skydive_anim_canceling") and bool(owner_player.call("_is_skydive_anim_canceling"))
	var exiting: bool = owner_player.has_method("_is_skydive_anim_exiting") and bool(owner_player.call("_is_skydive_anim_exiting"))
	if not canceling and not exiting:
		return false
	return can_execute({"reason": &"skydive_terminal_reenter"})
