@tool
extends EditorScenePostImport

const PHYSICS_SCRIPT: Script = preload("res://LS5Framework/Objects/Props/ObjectPhysicsBody3D.gd")
const PROFILE_SCRIPT: Script = preload("res://LS5Framework/Objects/Props/FractureImportPhysics.gd")

func _post_import(scene: Node) -> Object:
	var profile_path: String = get_source_file().get_basename() + "_physics.tres"
	var profile: Resource = load(profile_path) if ResourceLoader.exists(profile_path) else PROFILE_SCRIPT.new()
	if not profile or profile.get_script() != PROFILE_SCRIPT:
		push_error("Fracture import requires a FractureImportPhysics profile: %s" % profile_path)
		return scene
	var bodies: Array[RigidBody3D] = []
	_collect_bodies(scene, bodies)
	if bodies.is_empty():
		push_error("Fracture meshes must enable Generate Physics with Dynamic bodies in Advanced Import Settings: %s" % get_source_file())
		return null
	if not _validate_meshes(scene):
		return null
	for body: RigidBody3D in bodies:
		_prepare_body(body, profile)
	return scene

func _validate_meshes(node: Node, dynamic_parent: bool = false) -> bool:
	dynamic_parent = dynamic_parent or node is RigidBody3D
	if node is MeshInstance3D and node.mesh and not dynamic_parent:
		push_error("Fracture mesh '%s' must import as a Dynamic body." % node.name)
		return false
	if node is RigidBody3D:
		var prepared: bool = false
		for child: Node in node.get_children():
			if child is CollisionShape3D:
				if not _supports_collision_shape(child.shape):
					push_error("Fracture body '%s' requires convex or primitive collision." % node.name)
					return false
				prepared = true
		if not prepared:
			push_error("Fracture body '%s' has no imported collision shape." % node.name)
			return false
	for child: Node in node.get_children():
		if not _validate_meshes(child, dynamic_parent):
			return false
	return true

func _collect_bodies(node: Node, bodies: Array[RigidBody3D]) -> void:
	if node is RigidBody3D:
		bodies.append(node)
		return
	for child: Node in node.get_children():
		_collect_bodies(child, bodies)

func _prepare_body(body: RigidBody3D, profile: Resource) -> void:
	var scale: Vector3 = body.basis.get_scale()
	var scale_basis: Basis = Basis.from_scale(scale)
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(body, meshes)
	var bounds: AABB
	var initialized: bool = false
	for mesh: MeshInstance3D in meshes:
		var relative: Transform3D = _relative_transform(body, mesh)
		var box: AABB = Transform3D(scale_basis) * relative * mesh.get_aabb()
		bounds = bounds.merge(box) if initialized else box
		initialized = true
	var center: Vector3 = bounds.get_center()
	for child: Node in body.get_children():
		if child is Node3D:
			child.transform = Transform3D(scale_basis) * child.transform
			child.position -= center
		if child is CollisionShape3D:
			_bake_collision_shape(child)
	body.basis = body.basis.orthonormalized()
	body.position += body.basis * center
	body.set_script(PHYSICS_SCRIPT)
	body.set("fracture_template", true)
	body.set("carry_enabled", false)
	body.set("carry_respawn_enabled", false)
	body.set("carry_mass", profile.piece_mass)
	body.set("carry_gravity_scale", profile.gravity_scale)
	body.set("carry_friction", profile.friction)
	body.set("carry_bounce", profile.bounce)
	body.set("carry_linear_damp", profile.linear_damp)
	body.set("carry_angular_damp", profile.angular_damp)
	body.set("carry_continuous_collision", profile.continuous_collision)
	body.set("collision_safety_enabled", profile.collision_safety_enabled)
	body.set("collision_safety_min_speed", profile.collision_safety_min_speed)
	body.set("surface_effect_rigid_probe_enabled", false)
	body.set("buoyancy_enabled", profile.piece_density > 0.0)
	body.set("buoyancy_volume", maxf(float(profile.piece_mass), 0.001) / maxf(float(profile.piece_density), 0.001))
	body.mass = maxf(float(profile.piece_mass), 0.001)
	body.linear_damp = profile.linear_damp
	body.angular_damp = profile.angular_damp
	body.gravity_scale = 0.0
	body.continuous_cd = profile.continuous_collision
	body.collision_layer = profile.collision_layer
	body.collision_mask = profile.collision_mask
	var material: PhysicsMaterial = PhysicsMaterial.new()
	material.friction = profile.friction
	material.bounce = profile.bounce
	body.physics_material_override = material
	body.freeze = true
	body.sleeping = true
	body.process_mode = Node.PROCESS_MODE_DISABLED
	body.add_to_group(&"dynamic_physics_object", true)
	body.set_meta(&"fracture_import_prepared", true)

func _supports_collision_shape(shape: Shape3D) -> bool:
	return shape is ConvexPolygonShape3D or shape is BoxShape3D or shape is SphereShape3D or shape is CapsuleShape3D or shape is CylinderShape3D


func _bake_collision_shape(collision: CollisionShape3D) -> void:
	var shape: Shape3D = collision.shape.duplicate() as Shape3D
	var transform: Transform3D = collision.transform
	if shape is ConvexPolygonShape3D:
		var points: PackedVector3Array = shape.points
		for index: int in range(points.size()):
			points[index] = transform * points[index]
		shape.points = points
		collision.transform = Transform3D.IDENTITY
	else:
		var scale: Vector3 = transform.basis.get_scale().abs()
		if shape is BoxShape3D:
			shape.size *= scale
		elif shape is SphereShape3D:
			shape.radius *= maxf(scale.x, maxf(scale.y, scale.z))
		elif shape is CylinderShape3D:
			shape.radius *= maxf(scale.x, scale.z)
			shape.height *= scale.y
		elif shape is CapsuleShape3D:
			var radius: float = shape.radius * maxf(scale.x, scale.z)
			var height: float = maxf(shape.height * scale.y, radius * 2.0)
			shape.height = maxf(height, shape.radius * 2.0)
			shape.radius = radius
			shape.height = height
		transform.basis = transform.basis.orthonormalized()
		collision.transform = transform
	collision.shape = shape


func _collect_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and node.mesh:
		meshes.append(node)
	for child: Node in node.get_children():
		_collect_meshes(child, meshes)

func _relative_transform(root: Node3D, node: Node3D) -> Transform3D:
	var transform: Transform3D = node.transform
	var parent: Node = node.get_parent()
	while parent != root and parent is Node3D:
		transform = parent.transform * transform
		parent = parent.get_parent()
	return transform
