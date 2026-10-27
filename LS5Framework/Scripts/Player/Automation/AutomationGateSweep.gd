@tool
extends RefCounted

static func _gate_entry(gate: Area3D, from: Vector3, to: Vector3) -> float:
	var result: float = INF
	for child: Node in gate.get_children():
		var collision: CollisionShape3D = child as CollisionShape3D
		if not collision or collision.disabled or not collision.shape:
			continue
		var start: Vector3 = collision.to_local(from)
		var finish: Vector3 = collision.to_local(to)
		var shape: Shape3D = collision.shape
		var entry: float = -1.0
		if shape is BoxShape3D:
			var half: Vector3 = (shape as BoxShape3D).size * 0.5
			var hit: Variant = AABB(-half, half * 2.0).intersects_segment(start, finish)
			if hit is Vector3:
				entry = start.distance_to(hit as Vector3) / maxf(start.distance_to(finish), 0.000001)
		elif shape is SphereShape3D:
			entry = _sphere_entry(start, finish - start, (shape as SphereShape3D).radius)
		elif shape is CylinderShape3D:
			entry = _cylinder_entry(start, finish - start, (shape as CylinderShape3D).radius, (shape as CylinderShape3D).height * 0.5)
		elif shape is CapsuleShape3D:
			var capsule: CapsuleShape3D = shape as CapsuleShape3D
			var half: float = maxf(capsule.height * 0.5 - capsule.radius, 0.0)
			entry = _cylinder_entry(start, finish - start, capsule.radius, half)
			for side: float in [-1.0, 1.0]:
				var sphere: float = _sphere_entry(start - Vector3.UP * half * side, finish - start, capsule.radius)
				if sphere >= 0.0 and (entry < 0.0 or sphere < entry):
					entry = sphere
		if entry >= 0.0:
			result = minf(result, entry)
	return result if result < INF else -1.0


static func _sphere_entry(start: Vector3, motion: Vector3, radius: float) -> float:
	var a: float = motion.length_squared()
	var c: float = start.length_squared() - radius * radius
	if c <= 0.0:
		return 0.0
	if a < 0.00000001:
		return -1.0
	var b: float = start.dot(motion)
	var determinant: float = b * b - a * c
	if determinant < 0.0:
		return -1.0
	var entry: float = (-b - sqrt(determinant)) / a
	return entry if entry >= 0.0 and entry <= 1.0 else -1.0


static func _cylinder_entry(start: Vector3, motion: Vector3, radius: float, half: float) -> float:
	var low: float = 0.0
	var high: float = 1.0
	if absf(motion.y) < 0.00000001:
		if absf(start.y) > half:
			return -1.0
	else:
		var a: float = (-half - start.y) / motion.y
		var b: float = (half - start.y) / motion.y
		low = maxf(low, minf(a, b))
		high = minf(high, maxf(a, b))
	var a: float = motion.x * motion.x + motion.z * motion.z
	var b: float = start.x * motion.x + start.z * motion.z
	var c: float = start.x * start.x + start.z * start.z - radius * radius
	if a < 0.00000001:
		if c > 0.0:
			return -1.0
	else:
		var determinant: float = b * b - a * c
		if determinant < 0.0:
			return -1.0
		var root: float = sqrt(determinant)
		low = maxf(low, (-b - root) / a)
		high = minf(high, (-b + root) / a)
	return low if low <= high else -1.0


