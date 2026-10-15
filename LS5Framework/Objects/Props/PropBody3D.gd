extends ObjectPhysicsBody3D
class_name PropBody3D

signal damaged(hit: PropHit, remaining: float)
signal broken(stage: PropDamageStage)
signal destroyed(hit: PropHit)
signal restored

enum Outcome { REJECTED = 1, DAMAGED = 2, BROKEN = 4, DESTROYED = 8 }

@export_group("Destruction")
## Allows terminal removal after durability is exhausted.
@export var destroyable: bool = false
## Allows usable damage stages without requiring terminal destruction.
@export var breakable: bool = false
## Initial durability restored on respawn.
@export var maximum_durability: float = 1.0
## Ordered incoming attack rules. Empty accepts both player attack categories.
@export var hit_rules: Array[PropHitRule] = []
## Attack identities rejected before rule evaluation.
@export var blocked_attacks: Array[StringName] = []
## Usable stages entered as durability passes their thresholds.
@export var damage_stages: Array[PropDamageStage] = []
## Component emitting fragments on configured stages and destruction.
@export var fracture_emitter: ObjectFractureEmitter
## Emits fragments on terminal destruction.
@export var fracture_on_destroy: bool = true
## Visual roots hidden on destruction and replaced by damage stages. Empty discovers mesh instances.
@export var visual_roots: Array[NodePath] = []
## Scenes emitted once per destruction.
@export var contents: Array[PropContent] = []
## Additional outcome-filtered sound and effect profiles.
@export var feedback_profiles: Array[PropFeedbackProfile] = []
## Sounds selected on terminal destruction.
@export var destruction_sounds: Array[AudioStream] = []
## Sounds selected on entering a usable broken stage.
@export var break_sounds: Array[AudioStream] = []
## Sounds selected on rejected attacks.
@export var rejection_sounds: Array[AudioStream] = []
## Particle and effect scenes emitted on destruction.
@export var destruction_effects: Array[PackedScene] = []
## Lifetime of spawned destruction effects.
@export var effect_lifetime: float = 5.0
## Minimum interval between feedback sounds.
@export var feedback_cooldown: float = 0.1
## Time before automatic respawn. Zero retains the destroyed state until reset.
@export var respawn_delay: float = 0.0
## Removes surviving spawned contents when the source respawns.
@export var cleanup_contents_on_respawn: bool = true

@export_group("Attack Response")
## Ordered responses for rejected, damaged, broken, and destroyed contacts.
@export var bounce_responses: Array[PropBounceResponse] = []
## Allows targeting even when the chosen attack cannot damage this object.
@export var allow_immune_targeting: bool = false
## Time away from a contact before the same attack can hit again. Zero requires a new activation.
@export var rearm_after_separation: float = 0.0
## Minimum time between physical impact damage events.
@export var impact_cooldown: float = 0.2
## Enables damage from collisions with solid bodies and world geometry.
@export var impact_damage_enabled: bool = false
## Minimum closing speed for physical impact damage.
@export var impact_minimum_speed: float = 20.0
## Damage from a qualifying physical impact.
@export var impact_damage: float = 1.0

var durability: float = 1.0
var is_destroyed: bool = false
var targeting_allowed: bool = true
var _entered_stages: Array[int] = []
var _hits: Dictionary = {}
var _saved_collisions: Array[Dictionary] = []
var _stage_visual: Node3D
var _stage_shapes: Array[CollisionShape3D] = []
var _original_shapes: Array[Dictionary] = []
var _original_visuals: Array[Dictionary] = []
var _spawned_contents: Array[Node] = []
var _respawn_timer: float = 0.0
var _feedback_timer: float = 0.0
var _impact_timer: float = 0.0
var _initial_mass: float = 0.0
var _initial_volume: float = 0.0
var _initial_carry: bool = false

func _ready() -> void:
	super._ready()
	durability = maxf(maximum_durability, 0.001)
	_initial_mass = carry_mass
	_initial_volume = buoyancy_volume
	_initial_carry = carry_enabled
	_capture_collisions(self)
	_capture_visuals()
	for child: Node in get_children():
		if child is CollisionShape3D:
			_original_shapes.append({"node": child, "disabled": child.disabled})
	contact_monitor = true
	max_contacts_reported = maxi(max_contacts_reported, 16)

func _physics_process(delta: float) -> void:
	_feedback_timer = maxf(_feedback_timer - delta, 0.0)
	_impact_timer = maxf(_impact_timer - delta, 0.0)
	if is_destroyed:
		if _respawn_timer > 0.0:
			_respawn_timer -= delta
			if _respawn_timer <= 0.0:
				respawn_carryable()
		return
	super._physics_process(delta)

func can_be_carried_by(player: Node) -> bool:
	return not is_destroyed and super.can_be_carried_by(player)

func get_hit_rule(hit: PropHit) -> PropHitRule:
	if not hit.profile or hit.profile.attack_id in blocked_attacks:
		return null
	if hit_rules.is_empty():
		var rule: PropHitRule = PropHitRule.new()
		return rule if rule.accepts(hit, Vector3.ZERO if hit.profile.categories & PropAttackProfile.Category.IMPACT else get_dynamic_impact_velocity()) else null
	for rule: PropHitRule in hit_rules:
		if rule and rule.accepts(hit, Vector3.ZERO if hit.profile.categories & PropAttackProfile.Category.IMPACT else get_dynamic_impact_velocity()):
			return rule
	return null

func accepts_profile(profile: PropAttackProfile) -> bool:
	if is_destroyed or is_carried() or not targeting_allowed or not profile:
		return false
	if allow_immune_targeting:
		return true
	if profile.attack_id in blocked_attacks:
		return false
	if hit_rules.is_empty():
		return bool(profile.categories & 3)
	for rule: PropHitRule in hit_rules:
		if rule and rule.accepts_profile(profile):
			return true
	return false

func receive_prop_hit(hit: PropHit) -> int:
	if is_destroyed or not hit or not hit.profile:
		return Outcome.REJECTED
	if hit.normal.is_zero_approx():
		hit.normal = -hit.velocity.normalized() if not hit.velocity.is_zero_approx() else hit.up
	if hit.source and hit.source.has_method("_network_is_local_authority") and not hit.source.call("_network_is_local_authority"):
		return Outcome.REJECTED
	if is_release_contact_ignored(hit.source):
		return Outcome.REJECTED
	if is_carried() and hit.source == carry_holder:
		return Outcome.REJECTED
	var key: String = "%s:%s:%s" % [hit.source.get_instance_id() if is_instance_valid(hit.source) else 0, hit.profile.attack_id, hit.activation]
	var now: float = Time.get_ticks_msec() * 0.001
	if _hits.has(key):
		var previous: Dictionary = _hits[key]
		var separated: bool = rearm_after_separation > 0.0 and now - float(previous["seen"]) >= rearm_after_separation
		previous["seen"] = now
		if not separated and (hit.profile.repeat_interval <= 0.0 or now - float(previous["hit"]) < hit.profile.repeat_interval):
			return Outcome.REJECTED
	if _hits.size() >= 256:
		_hits.clear()
	_hits[key] = {"hit": now, "seen": now}
	var outcome: int = Outcome.REJECTED
	var rule: PropHitRule = get_hit_rule(hit)
	var source_velocity: Vector3 = get_dynamic_impact_velocity()
	if rule:
		outcome = Outcome.DAMAGED
		if not anchored and not is_carried():
			apply_kick_impulse(hit.impulse)
		if destroyable or breakable:
			durability = maxf(durability - maxf(hit.profile.damage * rule.damage_multiplier, 0.0), 0.0)
			if rule.instant_destroy:
				durability = 0.0
			damaged.emit(hit, durability)
			if destroyable and durability <= 0.0:
				outcome = Outcome.DESTROYED
				_destroy(hit, source_velocity)
			elif breakable:
				outcome = _enter_damage_stages(hit)
	else:
		_play_feedback(rejection_sounds)
	for feedback: PropFeedbackProfile in feedback_profiles:
		if feedback and feedback.outcomes & outcome and (feedback.attacks.is_empty() or hit.profile.attack_id in feedback.attacks):
			_play_feedback(feedback.sounds)
			for scene: PackedScene in feedback.effects:
				_spawn_effect(scene)
	_apply_player_response(hit, outcome, source_velocity)
	return outcome

func receive_kick_attack(player: Node3D) -> bool:
	if not player.is_attack_active() or not player.has_method("claim_kick_contact") or not player.claim_kick_contact(self):
		return false
	var contacts: Node = player.get_node_or_null("KickContacts")
	var id: StringName = &"spin_kick"
	if not contacts:
		for child: Node in player.get_children():
			if child is KickContactController:
				contacts = child
				break
	if contacts:
		id = {&"spin": &"spin_kick", &"tornado": &"tornado_kick", &"uppercut": &"uppercut_kick"}.get(contacts.get("_kick_kind"), &"spin_kick")
	var hit: PropHit = PropHit.from_player(player, id)
	if not hit.profile:
		return false
	hit.normal = (player.global_position - global_position).normalized()
	var direction: Vector3 = -hit.normal.slide(hit.up).normalized()
	var lift: float = 0.85 if id == &"uppercut_kick" else 0.2
	hit.impulse = (direction * (1.0 - lift) + hit.up * lift).normalized() * hit.profile.impulse
	return receive_prop_hit(hit) != Outcome.REJECTED

func _enter_damage_stages(hit: PropHit) -> int:
	var outcome: int = Outcome.DAMAGED
	for index: int in range(damage_stages.size()):
		var stage: PropDamageStage = damage_stages[index]
		if not stage or index in _entered_stages or durability > stage.durability_threshold:
			continue
		_entered_stages.append(index)
		carry_enabled = _initial_carry and stage.carry_allowed
		targeting_allowed = stage.targeting_allowed
		if not carry_enabled and is_carried():
			clear_carry_owner()
			_configure_physics_mode()
		if stage.mass_override > 0.0:
			carry_mass = stage.mass_override
			_apply_physics_attributes()
		if stage.volume_override > 0.0:
			buoyancy_volume = stage.volume_override
			buoyancy_component.displaced_volume = buoyancy_volume
		if stage.visual_scene:
			_set_visuals(false)
			if is_instance_valid(_stage_visual):
				_stage_visual.queue_free()
			_stage_visual = stage.visual_scene.instantiate() as Node3D
			if _stage_visual:
				add_child(_stage_visual)
		if not stage.collision_parts.is_empty():
			for state: Dictionary in _original_shapes:
				state["node"].set_deferred("disabled", true)
			for shape: CollisionShape3D in _stage_shapes:
				shape.queue_free()
			_stage_shapes.clear()
			for part: PropCollisionPart in stage.collision_parts:
				if part and part.shape and not part.shape is ConcavePolygonShape3D:
					var collision: CollisionShape3D = CollisionShape3D.new()
					collision.shape = part.shape
					collision.transform = part.transform
					add_child(collision)
					_stage_shapes.append(collision)
			call_deferred("_refresh_buoyancy_samples")
		if stage.emit_fractures:
			_emit_fragments(hit, get_dynamic_impact_velocity())
		_play_feedback(break_sounds)
		broken.emit(stage)
		outcome = Outcome.BROKEN
	return outcome

func _destroy(hit: PropHit, source_velocity: Vector3) -> void:
	var source_spin: Vector3 = angular_velocity
	is_destroyed = true
	clear_carry_owner()
	_remove_collision_exception()
	_stop_surface_slide_sound()
	_set_visuals(false)
	if is_instance_valid(_stage_visual):
		_stage_visual.visible = false
	for state: Dictionary in _saved_collisions:
		var object: CollisionObject3D = state["node"]
		object.set_deferred("collision_layer", 0)
		object.set_deferred("collision_mask", 0)
	freeze = true
	linear_velocity = Vector3.ZERO
	if fracture_on_destroy:
		_emit_fragments(hit, source_velocity, source_spin)
	angular_velocity = Vector3.ZERO
	_spawn_contents(source_velocity)
	_play_feedback(destruction_sounds)
	for scene: PackedScene in destruction_effects:
		_spawn_effect(scene)
	_respawn_timer = maxf(respawn_delay, 0.0)
	destroyed.emit(hit)

func _emit_fragments(hit: PropHit, velocity: Vector3, spin: Vector3 = Vector3.INF) -> void:
	if fracture_emitter:
		fracture_emitter.emit_fractures(hit.position, {"velocity": velocity, "angular_velocity": angular_velocity if spin == Vector3.INF else spin, "source_position": global_position, "up": get_gravity_up(), "impulse": hit.impulse, "gravity": get_prop_gravity_vector()})

func _apply_player_response(hit: PropHit, outcome: int, target_velocity: Vector3) -> void:
	var player: Node3D = hit.source
	if not is_instance_valid(player) or not player.has_method("apply_prop_bounce_response"):
		return
	for response: PropBounceResponse in bounce_responses:
		if response and response.matches(hit, outcome):
			player.call("apply_prop_bounce_response", response, self, hit.up, target_velocity, hit.was_airborne)
			break

func _spawn_contents(velocity: Vector3) -> void:
	for entry: PropContent in contents:
		if not entry or not entry.scene or entry.probability <= 0.0 or (entry.probability < 1.0 and randf() > entry.probability):
			continue
		for index: int in range(clampi(entry.count, 0, 64)):
			var node: Node = entry.scene.instantiate()
			get_parent().add_child(node)
			_spawned_contents.append(node)
			if node is Node3D:
				node.global_transform = global_transform.translated_local(entry.offset)
			if node is RigidBody3D:
				node.linear_velocity = velocity * entry.inherit_velocity

func _play_feedback(sounds: Array[AudioStream]) -> void:
	if sounds.is_empty() or _feedback_timer > 0.0:
		return
	_feedback_timer = maxf(feedback_cooldown, 0.0)
	var audio: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	audio.stream = sounds.pick_random()
	audio.bus = &"SFX"
	get_parent().add_child(audio)
	audio.global_position = global_position
	audio.finished.connect(audio.queue_free)
	audio.play()

func _spawn_effect(scene: PackedScene) -> void:
	if not scene:
		return
	var effect: Node = scene.instantiate()
	get_parent().add_child(effect)
	if effect is Node3D:
		effect.global_transform = global_transform
	get_tree().create_timer(maxf(effect_lifetime, 0.05)).timeout.connect(func():
		if is_instance_valid(effect):
			effect.queue_free())

func _set_visuals(value: bool) -> void:
	for state: Dictionary in _original_visuals:
		var visual: Node3D = state["node"]
		if is_instance_valid(visual):
			visual.visible = value and bool(state["visible"])

func _capture_visuals() -> void:
	var nodes: Array[Node] = []
	if visual_roots.is_empty():
		nodes = find_children("*", "MeshInstance3D", true, false)
	else:
		for path: NodePath in visual_roots:
			var node: Node = get_node_or_null(path)
			if node:
				nodes.append(node)
	for node: Node in nodes:
		if node is Node3D:
			_original_visuals.append({"node": node, "visible": node.visible})

func _capture_collisions(root: Node) -> void:
	if root is CollisionObject3D and not (fracture_emitter and fracture_emitter.is_ancestor_of(root)):
		_saved_collisions.append({"node": root, "layer": root.collision_layer, "mask": root.collision_mask})
	for child: Node in root.get_children():
		_capture_collisions(child)

func respawn_carryable(source: Node = null) -> bool:
	if not super.respawn_carryable(source):
		return false
	is_destroyed = false
	targeting_allowed = true
	durability = maxf(maximum_durability, 0.001)
	_entered_stages.clear()
	_hits.clear()
	_respawn_timer = 0.0
	carry_enabled = _initial_carry
	carry_mass = _initial_mass
	buoyancy_volume = _initial_volume
	buoyancy_component.displaced_volume = buoyancy_volume
	_apply_physics_attributes()
	if is_instance_valid(_stage_visual):
		_stage_visual.queue_free()
	for shape: CollisionShape3D in _stage_shapes:
		shape.queue_free()
	_stage_shapes.clear()
	for state: Dictionary in _original_shapes:
		state["node"].set_deferred("disabled", state["disabled"])
	call_deferred("_refresh_buoyancy_samples")
	_set_visuals(true)
	for state: Dictionary in _saved_collisions:
		var object: CollisionObject3D = state["node"]
		object.set_deferred("collision_layer", state["layer"])
		object.set_deferred("collision_mask", state["mask"])
	if cleanup_contents_on_respawn:
		for node: Node in _spawned_contents:
			if is_instance_valid(node):
				node.queue_free()
	_spawned_contents.clear()
	restored.emit()
	return true

var _previous_impact_velocity: Vector3 = Vector3.ZERO
var _previous_impact_spin: Vector3 = Vector3.ZERO

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if is_destroyed:
		return
	for index: int in range(state.get_contact_count()):
		var normal: Vector3 = state.get_contact_local_normal(index).normalized()
		var point: Vector3 = state.get_contact_local_position(index)
		var relative: Vector3 = _previous_impact_velocity + _previous_impact_spin.cross(point - global_position) - state.get_contact_collider_velocity_at_position(index)
		record_object_impact(point, normal, relative, state.get_contact_collider_object(index) as Node3D)
	super._integrate_forces(state)
	_previous_impact_velocity = state.linear_velocity
	_previous_impact_spin = state.angular_velocity

func record_object_impact(point: Vector3, normal: Vector3, relative: Vector3, collider: Node3D) -> void:
	if is_release_contact_ignored(collider):
		return
	if not impact_damage_enabled or _impact_timer > 0.0 or is_carried() or is_destroyed or -relative.dot(normal) < impact_minimum_speed:
		return
	_impact_timer = maxf(impact_cooldown, 0.01)
	var hit: PropHit = PropHit.new()
	hit.profile = PropAttackProfile.make(&"physical_impact", PropAttackProfile.Category.IMPACT)
	hit.profile.damage = impact_damage
	hit.source = collider
	hit.instigator = impact_instigator
	hit.activation = Time.get_ticks_msec()
	hit.normal = -normal
	hit.velocity = -relative
	hit.position = point
	call_deferred("receive_prop_hit", hit)
