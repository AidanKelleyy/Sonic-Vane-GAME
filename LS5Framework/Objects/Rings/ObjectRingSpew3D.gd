extends Node3D
class_name ObjectRingSpew3D

const DROPPED_RING_SCENE: PackedScene = preload("res://LS5Framework/Objects/Rings/DroppedRing.tscn")
const MAX_BURST_COUNT: int = 128

@export_group("Source")
## Enables ring emission from damage and destruction events.
@export var enabled: bool = true
## Prop or enemy providing damage events. Empty finds the nearest supported ancestor.
@export_node_path("Node3D") var source_path: NodePath = NodePath("")

@export_group("Ring Counts")
## Rings emitted after each nonlethal health or durability reduction.
@export_range(0, 128, 1) var damage_ring_count: int = 0
## Rings emitted on destruction or defeat. Lethal hits skip the damage burst.
@export_range(0, 128, 1) var destruction_ring_count: int = 10
## Maximum rings emitted between source resets. Zero disables this limit.
@export_range(0, 4096, 1, "or_greater") var ring_limit_per_life: int = 32
## Dropped-ring scene used for emitted pickups.
@export var ring_scene: PackedScene = DROPPED_RING_SCENE
## Uniform size of each emitted dropped ring.
@export_range(0.01, 100.0, 0.01, "or_greater") var ring_size: float = 1.0

@export_group("Launch")
## Minimum and maximum outward launch speeds.
@export var outward_speed: Vector2 = Vector2(18.0, 30.0)
## Minimum and maximum launch speeds along the source gravity-up direction.
@export var upward_speed: Vector2 = Vector2(20.0, 42.0)
## Fraction of the source velocity inherited by emitted rings.
@export_range(0.0, 2.0, 0.01, "or_greater") var inherit_velocity: float = 0.25
## Spawn offset along the source gravity-up direction, relative to this component.
@export var spawn_up_offset: float = 1.2
## Radius of the initial ring distribution around this component.
@export_range(0.0, 100.0, 0.01, "or_greater") var spawn_radius: float = 0.55

@export_group("Sound")
## Sound played once per nonempty burst. Empty disables emission audio.
@export var spew_sound: AudioStream = preload("res://LS5Framework/Sounds/General/RingSpread.wav")
## Volume of the ring emission sound.
@export var spew_volume_db: float = 0.0
## Pitch of the ring emission sound.
@export_range(0.01, 4.0, 0.01, "or_greater") var spew_pitch_scale: float = 1.0

## Prop or enemy supplying damage, gravity, and velocity state.
var _source: Node3D
## Enemy health component supplying damage, defeat, and reset signals.
var _health: ActorHealth
var _emitted_count: int = 0
var _destroyed: bool = false
var _previous_durability: float = 0.0
var _defeat_context: Dictionary = {}


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	_source = _resolve_source()
	if _source is PropBody3D:
		var prop: PropBody3D = _source as PropBody3D
		prop.damaged.connect(_on_prop_damaged)
		prop.destroyed.connect(_on_prop_destroyed)
		prop.restored.connect(reset_spew)
	elif _source is Enemy:
		var enemy: Enemy = _source as Enemy
		_health = enemy.get_node_or_null(enemy.health_component_path) as ActorHealth
		if _health:
			_health.damaged.connect(_on_enemy_damaged)
			_health.died.connect(_on_enemy_defeated)
			_health.restored.connect(reset_spew)
		else:
			push_warning("Ring spew source has no configured ActorHealth component.")
	else:
		push_warning("Ring spew requires a PropBody3D or Enemy source.")
	reset_spew()


func _resolve_source() -> Node3D:
	if not source_path.is_empty():
		return get_node_or_null(source_path) as Node3D
	var ancestor: Node = get_parent()
	while ancestor:
		if ancestor is PropBody3D or ancestor is Enemy:
			return ancestor as Node3D
		ancestor = ancestor.get_parent()
	return null


func reset_spew() -> void:
	_emitted_count = 0
	_destroyed = false
	_defeat_context.clear()
	if is_instance_valid(_source) and _source is PropBody3D:
		var prop: PropBody3D = _source as PropBody3D
		_previous_durability = prop.durability if prop.is_node_ready() else maxf(prop.maximum_durability, 0.001)


func _on_prop_damaged(_hit: PropHit, remaining: float) -> void:
	var reduced: bool = remaining < _previous_durability
	_previous_durability = remaining
	var prop: PropBody3D = _source as PropBody3D
	if prop.destroyable and remaining <= 0.0:
		_defeat_context = _capture_context()
	elif reduced:
		_emit_rings(damage_ring_count, _capture_context())


func _on_prop_destroyed(_hit: PropHit) -> void:
	_emit_destruction()


func _on_enemy_damaged(_amount: int, _attacker: Node) -> void:
	if _health.current_health <= 0:
		_defeat_context = _capture_context()
	else:
		_emit_rings(damage_ring_count, _capture_context())


func _on_enemy_defeated(_attacker: Node) -> void:
	_emit_destruction()


func _emit_destruction() -> void:
	if _destroyed:
		return
	_destroyed = true
	_emit_rings(destruction_ring_count, _defeat_context if not _defeat_context.is_empty() else _capture_context())
	_defeat_context.clear()


func _capture_context() -> Dictionary:
	var up: Vector3 = Vector3.UP
	var velocity: Vector3 = Vector3.ZERO
	if is_instance_valid(_source):
		if _source.has_method("get_gravity_up"):
			up = _source.call("get_gravity_up")
		if _source is ObjectPhysicsBody3D:
			velocity = (_source as ObjectPhysicsBody3D).get_dynamic_impact_velocity_at(global_position)
		elif _source is CharacterBody3D:
			velocity = (_source as CharacterBody3D).velocity
	up = Vector3.UP if up.is_zero_approx() else up.normalized()
	return {"position": global_position, "up": up, "velocity": velocity}


func _emit_rings(requested_count: int, context: Dictionary) -> void:
	if not enabled or not ring_scene or not is_inside_tree():
		return
	var count: int = clampi(requested_count, 0, MAX_BURST_COUNT)
	if ring_limit_per_life > 0:
		count = mini(count, maxi(ring_limit_per_life - _emitted_count, 0))
	if not count:
		return
	var parent: Node = get_tree().current_scene
	if not parent or parent == _source or (is_instance_valid(_source) and _source.is_ancestor_of(parent)):
		parent = get_tree().root
	var up: Vector3 = context.get("up", Vector3.UP)
	var velocity: Vector3 = context.get("velocity", Vector3.ZERO)
	var center: Vector3 = context.get("position", global_position) + up * spawn_up_offset
	var forward: Vector3 = Vector3.FORWARD.slide(up)
	if forward.is_zero_approx():
		forward = Vector3.RIGHT.slide(up)
	forward = forward.normalized()
	var right: Vector3 = up.cross(forward).normalized()
	var phase: float = randf() * TAU
	var emitted: int = 0
	for index: int in range(count):
		var ring: Node = ring_scene.instantiate()
		if not ring is DroppedRing:
			ring.free()
			continue
		var pickup: DroppedRing = ring as DroppedRing
		var angle: float = phase + TAU * float(index) / float(count)
		var radial: Vector3 = forward * cos(angle) + right * sin(angle)
		var launch: Vector3 = radial * randf_range(minf(outward_speed.x, outward_speed.y), maxf(outward_speed.x, outward_speed.y))
		launch += up * randf_range(minf(upward_speed.x, upward_speed.y), maxf(upward_speed.x, upward_speed.y))
		launch += velocity * maxf(inherit_velocity, 0.0)
		pickup.top_level = true
		pickup.position = center + radial * maxf(spawn_radius, 0.0)
		pickup.size = ring_size
		pickup.local_collection_only = true
		pickup.setup_dropped_ring(launch, up)
		parent.add_child.call_deferred(pickup)
		emitted += 1
	_emitted_count += emitted
	if emitted and spew_sound:
		var audio: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		audio.add_to_group(&"LevelTransient")
		audio.top_level = true
		audio.position = center
		audio.stream = spew_sound
		audio.bus = &"SFX"
		audio.volume_db = spew_volume_db
		audio.pitch_scale = maxf(spew_pitch_scale, 0.01)
		audio.autoplay = true
		audio.finished.connect(audio.queue_free)
		parent.add_child.call_deferred(audio)
