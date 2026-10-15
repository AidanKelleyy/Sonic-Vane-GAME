extends Node
class_name ObjectBuoyancy3D

## Enables water forces on the owning physics body.
@export var enabled: bool = true
## Effective displaced volume in cubic world units.
@export var displaced_volume: float = 0.03
## Weighted local displacement samples. Empty samples the body origin.
@export var samples: Array[PropBuoyancySample] = []
## Default radius used for smooth partial submersion.
@export var sample_radius: float = 0.25
## Linear drag rate relative to water velocity.
@export var linear_drag: float = 3.0
## Angular drag rate while submerged.
@export var angular_drag: float = 2.0

var submerged_fraction: float = 0.0
var _body: RigidBody3D

func _ready() -> void:
	_body = get_parent() as RigidBody3D

func evaluate(transform: Transform3D, velocity: Vector3, spin: Vector3, gravity: Vector3, body_mass: float, delta: float) -> Dictionary:
	var force: Vector3 = Vector3.ZERO
	var torque: Vector3 = Vector3.ZERO
	submerged_fraction = 0.0
	if not enabled or not _body or delta <= 0.0:
		return {"force": force, "torque": torque}
	var candidates: Array[Node] = []
	var volumes: Array[Node] = get_tree().get_nodes_in_group(&"prop_water_volume")
	if volumes.is_empty():
		return {"force": force, "torque": torque}
	var query_bounds: AABB = _sample_bounds(transform)
	for water: Node in volumes:
		if water.has_method("get_prop_water_bounds"):
			var bounds: AABB = water.call("get_prop_water_bounds")
			if not bounds.intersects(query_bounds):
				continue
		candidates.append(water)
	if candidates.is_empty():
		return {"force": force, "torque": torque}
	var total_weight: float = 0.0
	for sample: PropBuoyancySample in samples:
		if sample:
			total_weight += maxf(sample.weight, 0.0)
	var count: int = samples.size() if total_weight > 0.0 else 1
	for index: int in range(count):
		var sample: PropBuoyancySample = samples[index] if total_weight > 0.0 else null
		if total_weight > 0.0 and not sample:
			continue
		var weight: float = sample.weight / total_weight if sample else 1.0
		var offset: Vector3 = transform.basis * sample.position if sample else Vector3.ZERO
		var radius: float = maxf(sample.radius if sample else sample_radius, 0.001)
		var data: Dictionary = _sample_water(transform.origin + offset, radius, candidates)
		var fraction: float = float(data.get("fraction", 0.0))
		if fraction <= 0.0:
			continue
		submerged_fraction += fraction * weight
		var fluid_gravity: Vector3 = data.get("gravity", gravity)
		var volume: float = maxf(displaced_volume, 0.0) * absf(transform.basis.determinant()) * weight * fraction
		var lift: Vector3 = -fluid_gravity * float(data.get("density", 1000.0)) * volume
		var relative: Vector3 = velocity + spin.cross(offset) - (data.get("velocity", Vector3.ZERO) as Vector3)
		var drag_fraction: float = 1.0 - exp(-maxf(linear_drag, 0.0) * fraction * delta)
		var sample_force: Vector3 = lift - relative * maxf(body_mass, 0.001) * weight * drag_fraction / delta
		force += sample_force
		torque += offset.cross(sample_force)
	var angular_fraction: float = 1.0 - exp(-maxf(angular_drag, 0.0) * submerged_fraction * delta)
	return {"force": force, "torque": torque, "angular_retention": 1.0 - angular_fraction}

func _sample_water(position: Vector3, radius: float, candidates: Array[Node]) -> Dictionary:
	var selected: Dictionary = {}
	var priority: int = -2147483648
	for water: Node in candidates:
		var data: Dictionary = water.call("sample_prop_water", position, radius)
		if float(data.get("fraction", 0.0)) <= 0.0:
			continue
		var candidate_priority: int = int(data.get("priority", 0))
		if selected.is_empty() or candidate_priority > priority:
			selected = data
			priority = candidate_priority
	return selected

func _sample_bounds(transform: Transform3D) -> AABB:
	var bounds: AABB
	var initialized: bool = false
	for sample: PropBuoyancySample in samples:
		if not sample:
			continue
		var position: Vector3 = transform * sample.position
		var extent: Vector3 = Vector3.ONE * maxf(sample.radius, 0.001)
		var sample_bounds: AABB = AABB(position - extent, extent * 2.0)
		bounds = bounds.merge(sample_bounds) if initialized else sample_bounds
		initialized = true
	if not initialized:
		var extent: Vector3 = Vector3.ONE * maxf(sample_radius, 0.001)
		bounds = AABB(transform.origin - extent, extent * 2.0)
	return bounds
