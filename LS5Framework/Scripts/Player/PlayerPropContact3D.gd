extends Node
class_name PlayerPropContact3D

## Solid layers queried for prop body contacts.
@export_flags_3d_physics var target_mask: int = 131
## Maximum samples used by a body sweep.
@export_range(1, 256, 1) var maximum_samples: int = 128
## Displacement treated as a teleport instead of an attack sweep.
@export var teleport_distance: float = 200.0

var _player: Node3D
var _previous: Vector3 = Vector3.ZERO
var _last_id: StringName = &""
var _pending_id: StringName = &""
var _pending_airborne: bool = false
var _prepared_frame: int = -1
var _shape: SphereShape3D = SphereShape3D.new()

func _ready() -> void:
	_player = get_parent() as Node3D
	_previous = _player.global_position
	process_physics_priority = 20

static func body_attack_id(player: Node3D) -> StringName:
	if player.get("_is_dead") or player.get("_hurt_active"):
		return &""
	if player.get("_homing_active"):
		return &"homing"
	var bounce: int = int(player.get("_bounce_state"))
	if bounce != 0:
		if bounce == int(player.BounceState.STOMP):
			return &"stomp"
		return &"bounce_rebound" if bounce == int(player.BounceState.REBOUND) else &"bounce"
	if player.get("_bounce_rebound_attack_active"):
		return &"bounce_rebound"
	var action: CharacterAction = player.get("_active_action") as CharacterAction
	if action and action.prop_body_attack_id != &"" and player.is_attack_active():
		return action.prop_body_attack_id
	var flags: int = int(player.get("_attack_sources"))
	var sources: Dictionary = {player.AttackSource.JUMP_DASH: &"jump_dash", player.AttackSource.LIGHTSPEED: &"lightspeed_dash", player.AttackSource.SPINDASH: &"spindash", player.AttackSource.ROLL: &"roll", player.AttackSource.JUMP: &"jump", player.AttackSource.AIR_UNCURL: &"air_uncurl", player.AttackSource.ENEMY_CHAIN: &"enemy_chain"}
	for flag: int in sources:
		if flags & flag:
			return sources[flag]
	return &""

func prepare() -> void:
	var id: StringName = body_attack_id(_player)
	if id != _last_id and id != &"":
		_player.set_meta(StringName("prop_activation_" + String(id)), Engine.get_physics_frames())
	_last_id = id
	var frame: int = Engine.get_physics_frames()
	if _prepared_frame != frame:
		_pending_id = id
		_pending_airborne = not bool(_player.get("attached"))
		_prepared_frame = frame
	elif id != &"":
		_pending_id = id
		_pending_airborne = _pending_airborne or not bool(_player.get("attached"))

func _physics_process(_delta: float) -> void:
	var current: Vector3 = _player.global_position
	var id: StringName = _pending_id if _prepared_frame == Engine.get_physics_frames() else body_attack_id(_player)
	if id == &"" or not _player._network_is_local_authority() or _player.get("_is_dead") or _player.get("_hurt_active"):
		_previous = current
		return
	var offset: Vector3 = Vector3.ZERO
	var radius: float = 0.5
	var main_shape: CollisionShape3D = _player.get("main_collision_shape") as CollisionShape3D
	if main_shape:
		offset = main_shape.global_position - current
	for child: Node in _player.get_children():
		if child is CollisionShape3D and not child.disabled and child.shape is SphereShape3D:
			radius = maxf(radius, child.shape.radius)
	_shape.radius = radius
	var start: Vector3 = _previous if _previous.distance_to(current) <= teleport_distance else current
	var count: int = clampi(ceili(start.distance_to(current) / maxf(radius * 0.5, 0.05)), 1, maximum_samples)
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = _shape
	query.collision_mask = target_mask
	query.exclude = [_player.get_rid()]
	var seen: Dictionary = {}
	for index: int in range(count + 1):
		var point: Vector3 = start.lerp(current, float(index) / float(count))
		query.transform = Transform3D(Basis.IDENTITY, point + offset)
		for result: Dictionary in _player.get_world_3d().direct_space_state.intersect_shape(query, 64):
			var prop: Node3D = result.get("collider") as Node3D
			if not prop is PropBody3D or seen.has(prop.get_instance_id()) or prop.is_destroyed:
				continue
			seen[prop.get_instance_id()] = true
			var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(point, prop.global_position, 17)
			ray.exclude = [_player.get_rid(), prop.get_rid()]
			if not _player.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				continue
			var hit: PropHit = PropHit.from_player(_player, id)
			hit.was_airborne = _pending_airborne or hit.was_airborne
			hit.position = point
			hit.normal = (point - prop.global_position).normalized()
			prop.receive_prop_hit(hit)
	_previous = current


func resolve_before_move(motion: Vector3) -> Array[PhysicsBody3D]:
	var ignored: Array[PhysicsBody3D] = []
	if not _player._network_is_local_authority():
		return ignored
	prepare()
	var id: StringName = body_attack_id(_player)
	if id == &"":
		return ignored
	var source_velocity: Vector3 = _player.velocity
	var parameters: PhysicsTestMotionParameters3D = PhysicsTestMotionParameters3D.new()
	parameters.from = _player.global_transform
	parameters.motion = motion
	parameters.margin = _player.safe_margin
	parameters.recovery_as_collision = true
	var result: PhysicsTestMotionResult3D = PhysicsTestMotionResult3D.new()
	for index: int in range(maximum_samples):
		if not PhysicsServer3D.body_test_motion(_player.get_rid(), parameters, result):
			break
		var prop: PropBody3D = result.get_collider() as PropBody3D
		if not prop:
			break
		if not prop.is_destroyed:
			var hit: PropHit = PropHit.from_player(_player, id)
			hit.position = result.get_collision_point()
			hit.normal = result.get_collision_normal()
			prop.receive_prop_hit(hit)
		if not prop.is_destroyed:
			break
		parameters.exclude_bodies.append(prop.get_rid())
		if prop not in _player.get_collision_exceptions():
			_player.add_collision_exception_with(prop)
			ignored.append(prop)
		if not source_velocity.is_equal_approx(_player.velocity):
			break
	return ignored
