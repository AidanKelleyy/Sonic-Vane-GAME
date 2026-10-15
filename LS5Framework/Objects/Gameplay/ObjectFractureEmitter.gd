extends Node3D
class_name ObjectFractureEmitter

@export_group("Fracture")
## Enables fracture spawning when triggered.
@export var fracture_enabled: bool = true
## Node used as the prepared fracture template.
@export var fracture_source_path: NodePath = NodePath("")
## Node that receives spawned fracture bodies.
@export var spawn_parent_path: NodePath = NodePath("")
## Spawns fracture bodies under a scene-level debris root.
@export var detach_to_scene_root: bool = true
## Scene-level parent used for detached fracture bodies.
@export var debris_root_name: StringName = &"ObjectFractureDebrisRoot"
## Hides the prepared fracture template while the object is intact.
@export var hide_source_on_ready: bool = true
## Disables the prepared fracture template collisions while it is hidden.
@export var disable_source_collision_on_ready: bool = true
## Adds each spawned fracture body to this group.
@export var spawned_group: StringName = &"object_fracture"

@export_group("Piece Profiles")
## Additional authored fracture template roots emitted with the primary source.
@export var additional_source_paths: Array[NodePath] = []
## Maximum number of live pieces emitted by this component.
@export_range(1, 256, 1) var maximum_live_pieces: int = 64
## Maximum number of live fracture bodies across the scene.
@export_range(1, 1024, 1) var scene_piece_budget: int = 192
## Overrides the imported body settings with this emitter's physics parameters.
@export var override_imported_physics: bool = false
## Material density override. Zero disables buoyancy when imported physics overrides are enabled.
@export var piece_density: float = 0.0
## Gravity scale applied when imported physics overrides are enabled.
@export var piece_gravity_scale: float = 4.0
## Fraction of the attack impulse distributed across the emitted pieces.
@export var attack_impulse_fraction: float = 0.25
## Fraction of source linear and angular motion inherited by fragments.
@export var inherit_motion: float = 1.0

@export_group("Physics")
## Collision layer restored on spawned fracture bodies when the template uses no layer.
@export_flags_3d_physics var fallback_collision_layer: int = 8
## Collision mask restored on spawned fracture bodies when the template uses no mask.
@export_flags_3d_physics var fallback_collision_mask: int = 5
## Mass override applied when imported physics overrides are enabled. Zero preserves imported mass.
@export var piece_mass: float = 0.35
## Outward impulse applied to each fracture piece.
@export var explosion_impulse: float = 6.0
## Upward impulse added after the outward impulse.
@export var upward_impulse: float = 1.5
## Random impulse variation added per piece.
@export var random_impulse: float = 1.0
## Random angular velocity applied per piece.
@export var random_angular_velocity: float = 8.0
## Continuous collision override applied when imported physics overrides are enabled.
@export var piece_continuous_collision: bool = true

@export_group("Collision Safety")
## Supplemental sweep override applied when imported physics overrides are enabled.
@export var piece_collision_safety_enabled: bool = true
## Minimum linear speed requiring supplemental fragment sweeps. Native CCD remains independent.
@export var piece_collision_safety_min_speed: float = 35.0
## Collision mask used by spawned fracture collision safety sweeps.
@export_flags_3d_physics var piece_collision_safety_mask: int = 17
## Radius used by spawned fracture collision safety sweeps.
@export var piece_collision_safety_radius: float = 0.25
## Extra separation used by spawned fracture collision safety sweeps.
@export var piece_collision_safety_skin: float = 0.04
## Maximum distance covered by one spawned fracture collision safety sweep step.
@export var piece_collision_safety_max_sweep_step_distance: float = 0.4
## Normal velocity retained after spawned fracture collision safety hits.
@export_range(0.0, 1.25, 0.01) var piece_collision_safety_bounce: float = 0.15
## Tangential velocity removed after spawned fracture collision safety hits.
@export_range(0.0, 1.0, 0.01) var piece_collision_safety_friction: float = 0.25
## Up direction used by spawned fracture collision safety support checks.
@export var piece_collision_safety_up: Vector3 = Vector3.UP

@export_group("Cleanup")
## Time before spawned pieces begin fading.
@export var lifetime_sec: float = 3.0
## Time used for the fade-out cleanup.
@export var fade_out_sec: float = 1.0
## Removes non-detached spawned pieces when this emitter exits the scene tree.
@export var cleanup_on_exit: bool = true

var _emission_context: Dictionary = {}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _spawned: Array[Node3D] = []
var _fracture_source: Node3D
var _piece_templates: Array[Dictionary] = []


func _ready() -> void:
	_rng.randomize()
	_fracture_source = _resolve_fracture_source()
	_rebuild_piece_templates()
	if hide_source_on_ready and _fracture_source:
		_fracture_source.visible = false
	if disable_source_collision_on_ready and _fracture_source:
		_set_source_collision_enabled(false)


func _exit_tree() -> void:
	if not cleanup_on_exit:
		return
	if detach_to_scene_root:
		_spawned.clear()
		return
	for piece in _spawned:
		if piece and is_instance_valid(piece):
			piece.queue_free()
	_spawned.clear()


func emit_fractures(origin: Vector3 = Vector3.INF, context: Dictionary = {}) -> void:
	_emission_context = context
	if not fracture_enabled:
		return
	if not _fracture_source:
		_fracture_source = _resolve_fracture_source()
	if not _fracture_source:
		return
	if _piece_templates.is_empty():
		_rebuild_piece_templates()
	if _piece_templates.is_empty():
		return
	if origin == Vector3.INF:
		origin = _fracture_source.global_position

	var parent: Node = _resolve_spawn_parent()
	if not parent:
		return

	for piece_template in _piece_templates:
		if _spawned.size() >= maximum_live_pieces or get_tree().get_nodes_in_group(&"object_fracture").size() >= scene_piece_budget:
			break
		_spawn_piece(piece_template, parent, origin)


func _spawn_piece(piece_template: Dictionary, parent: Node, origin: Vector3) -> void:
	var source_node: Node3D = piece_template.get("source_node", null) as Node3D
	if not source_node:
		return

	if not source_node is RigidBody3D:
		return
	var piece: RigidBody3D = source_node.duplicate(Node.DUPLICATE_SIGNALS | Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS) as RigidBody3D
	if not piece:
		return
	var source_transform: Transform3D = piece_template["source_transform"] as Transform3D
	var body_transform: Transform3D = _fracture_source.global_transform * source_transform
	piece.process_mode = Node.PROCESS_MODE_INHERIT
	if piece is ObjectPhysicsBody3D:
		piece.fracture_template = false
	if override_imported_physics:
		_apply_physics_overrides(piece)
	piece.transform = Transform3D.IDENTITY
	piece.name = "%s_Fracture" % String(piece_template.get("name", "Piece"))
	piece.visible = true
	piece.top_level = false
	piece.add_to_group(spawned_group)
	piece.add_to_group(&"LevelTransient")

	parent.add_child(piece)
	piece.global_transform = body_transform
	if piece is ObjectPhysicsBody3D:
		piece._reset_motion_history()
		piece._store_surface_effect_previous_state()
	_restore_piece_collision_state(piece, piece_template)
	_prepare_spawned_piece(piece)

	_spawned.append(piece)
	piece.tree_exited.connect(_on_piece_tree_exited.bind(piece))

	_apply_explosion(piece, origin)
	_setup_cleanup(piece)


func _prepare_spawned_piece(piece: Node3D) -> void:
	_set_visible_recursive(piece, true)
	if piece is RigidBody3D:
		piece.freeze = false
		piece.sleeping = false


func _apply_physics_overrides(body: RigidBody3D) -> void:
	if piece_mass > 0.0:
		body.mass = piece_mass
	body.continuous_cd = piece_continuous_collision
	var material: PhysicsMaterial = PhysicsMaterial.new()
	material.friction = piece_collision_safety_friction
	material.bounce = piece_collision_safety_bounce
	body.physics_material_override = material
	if body is ObjectPhysicsBody3D:
		body.carry_mass = body.mass
		body.carry_gravity_scale = piece_gravity_scale
		body.carry_bounce = piece_collision_safety_bounce
		body.carry_friction = piece_collision_safety_friction
		body.carry_continuous_collision = piece_continuous_collision
		body.collision_safety_enabled = piece_collision_safety_enabled
		body.collision_safety_min_speed = piece_collision_safety_min_speed
		body.buoyancy_enabled = piece_density > 0.0
		body.buoyancy_volume = body.mass / maxf(piece_density, 0.001)
	else:
		body.gravity_scale = piece_gravity_scale


func _apply_explosion(piece: Node3D, origin: Vector3) -> void:
	var body: RigidBody3D = _find_rigid_body(piece)
	if not body:
		return

	var outward: Vector3 = body.global_position - origin
	if outward.length_squared() <= 0.0001:
		outward = _random_unit_vector()
	else:
		outward = outward.normalized()

	var impulse: Vector3 = outward * max(explosion_impulse, 0.0)
	var up: Vector3 = _emission_context.get("up", piece_collision_safety_up)
	impulse += up.normalized() * upward_impulse
	impulse += (_emission_context.get("impulse", Vector3.ZERO) as Vector3) * attack_impulse_fraction / maxf(float(_piece_templates.size()), 1.0)
	if random_impulse > 0.0:
		impulse += _random_unit_vector() * _rng.randf_range(0.0, random_impulse)
	var source_velocity: Vector3 = _emission_context.get("velocity", Vector3.ZERO)
	var source_spin: Vector3 = _emission_context.get("angular_velocity", Vector3.ZERO)
	var source_position: Vector3 = _emission_context.get("source_position", origin)
	body.linear_velocity = (source_velocity + source_spin.cross(body.global_position - source_position)) * inherit_motion
	body.angular_velocity = source_spin * inherit_motion
	if body is ObjectPhysicsBody3D and _emission_context.has("gravity"):
		var gravity: Vector3 = _emission_context["gravity"]
		body.simplified_up = -gravity.normalized() if not gravity.is_zero_approx() else up
		body.carry_gravity_scale = gravity.length() / maxf(float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)), 0.001)
		body._update_gravity_pull_state(0.0)
	body.apply_central_impulse(impulse)

	var angular_strength: float = max(random_angular_velocity, 0.0)
	if angular_strength > 0.0:
		body.angular_velocity += _random_unit_vector() * _rng.randf_range(0.0, angular_strength)


func _setup_cleanup(piece: Node3D) -> void:
	var wait_time: float = max(lifetime_sec, 0.0)
	var fade_time: float = max(fade_out_sec, 0.0)
	if wait_time <= 0.0 and fade_time <= 0.0:
		piece.queue_free()
		return

	if wait_time <= 0.0:
		_fade_and_free(piece, fade_time)
		return
	var timer: Timer = Timer.new()
	timer.one_shot = true
	timer.wait_time = wait_time
	piece.add_child(timer)
	timer.timeout.connect(func():
		if not piece or not is_instance_valid(piece):
			return
		if fade_time <= 0.0:
			piece.queue_free()
			return
		_fade_and_free(piece, fade_time)
	)
	timer.start()


func _fade_and_free(piece: Node3D, fade_time: float) -> void:
	var materials: Array[Material] = []
	_collect_fade_materials(piece, materials)

	if materials.is_empty():
		piece.queue_free()
		return

	var tween: Tween = piece.create_tween()
	for material in materials:
		tween.parallel().tween_method(_set_material_alpha.bind(material), 1.0, 0.0, fade_time)
	tween.finished.connect(func():
		if piece and is_instance_valid(piece):
			piece.queue_free()
	)


func _set_material_alpha(alpha: float, material: Material) -> void:
	if not material:
		return
	if material is BaseMaterial3D:
		var base_material: BaseMaterial3D = material as BaseMaterial3D
		base_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var color: Color = base_material.albedo_color
		color.a = clamp(alpha, 0.0, 1.0)
		base_material.albedo_color = color


func _rebuild_piece_templates() -> void:
	_piece_templates.clear()
	if not _fracture_source:
		return

	var source_inverse: Transform3D = _fracture_source.global_transform.affine_inverse()
	var piece_roots: Array[Node3D] = _collect_piece_roots()
	for path: NodePath in additional_source_paths:
		var extra: Node3D = get_node_or_null(path) as Node3D
		if extra:
			_collect_rigid_piece_roots(extra, piece_roots)
	for piece_root in piece_roots:
		if not _contains_mesh(piece_root):
			continue
		_piece_templates.append({
			"name": piece_root.name,
			"source_node": piece_root,
			"source_transform": source_inverse * piece_root.global_transform,
			"collision_states": _collect_collision_states(piece_root)
		})

	for path: NodePath in additional_source_paths:
		var extra: Node3D = get_node_or_null(path) as Node3D
		if extra:
			extra.visible = false
			_set_collision_enabled_recursive(extra, false)


func _collect_piece_roots() -> Array[Node3D]:
	var roots: Array[Node3D] = []
	_collect_rigid_piece_roots(_fracture_source, roots)
	if roots.is_empty():
		push_warning("Fracture source '%s' requires imported dynamic bodies with convex collision. Runtime collision generation is disabled." % _fracture_source.name)
	return roots


func _collect_rigid_piece_roots(node: Node, roots: Array[Node3D]) -> void:
	if node is RigidBody3D and _contains_mesh(node):
		var valid_shape: bool = false
		for child: Node in node.get_children():
			if child is CollisionShape3D and child.shape and not child.shape is ConcavePolygonShape3D:
				valid_shape = true
		if valid_shape:
			roots.append(node)
		else:
			push_warning("Fracture body '%s' has no prepared convex collision." % node.name)
		return
	for child: Node in node.get_children():
		_collect_rigid_piece_roots(child, roots)


func _collect_collision_states(root: Node) -> Dictionary:
	var states: Dictionary = {}
	_collect_collision_states_recursive(root, root, states)
	return states


func _collect_collision_states_recursive(root: Node, node: Node, states: Dictionary) -> void:
	var state: Dictionary = {}
	if node is CollisionObject3D:
		var collision_object: CollisionObject3D = node as CollisionObject3D
		state["collision_layer"] = collision_object.collision_layer
		state["collision_mask"] = collision_object.collision_mask
		if node is Area3D:
			var area: Area3D = node as Area3D
			state["monitoring"] = area.monitoring
			state["monitorable"] = area.monitorable
	if node is CollisionShape3D:
		state["disabled"] = (node as CollisionShape3D).disabled
	if not state.is_empty():
		states[root.get_path_to(node)] = state
	for child in node.get_children():
		_collect_collision_states_recursive(root, child, states)


func _restore_piece_collision_state(piece: Node3D, piece_template: Dictionary) -> void:
	var states: Dictionary = piece_template.get("collision_states", {}) as Dictionary
	for path in states.keys():
		var node: Node = piece.get_node_or_null(path as NodePath)
		if not node:
			continue
		var state: Dictionary = states[path] as Dictionary
		if node is CollisionObject3D:
			var collision_object: CollisionObject3D = node as CollisionObject3D
			collision_object.collision_layer = int(state.get("collision_layer", fallback_collision_layer))
			collision_object.collision_mask = int(state.get("collision_mask", fallback_collision_mask))
			if node is Area3D:
				var area: Area3D = node as Area3D
				area.monitoring = bool(state.get("monitoring", true))
				area.monitorable = bool(state.get("monitorable", true))
		if node is CollisionShape3D:
			(node as CollisionShape3D).disabled = bool(state.get("disabled", false))


func _set_source_collision_enabled(value: bool) -> void:
	if not _fracture_source:
		return
	_set_collision_enabled_recursive(_fracture_source, value)


func _set_collision_enabled_recursive(node: Node, value: bool) -> void:
	if node is RigidBody3D and not value:
		node.freeze = true
		node.sleeping = true
		node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is CollisionObject3D:
		var collision_object: CollisionObject3D = node as CollisionObject3D
		if value:
			return
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0
	if node is Area3D:
		var area: Area3D = node as Area3D
		area.monitoring = value
		area.monitorable = value
	for child in node.get_children():
		_set_collision_enabled_recursive(child, value)


func _collect_fade_materials(node: Node, materials: Array[Material]) -> void:
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		var material_override: Material = mesh_instance.material_override
		if material_override:
			mesh_instance.material_override = _duplicate_fade_material(material_override)
			materials.append(mesh_instance.material_override)

		var surface_count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh else 0
		for i in range(surface_count):
			var surface_material: Material = mesh_instance.get_active_material(i)
			if surface_material and not material_override:
				var duplicate: Material = _duplicate_fade_material(surface_material)
				mesh_instance.set_surface_override_material(i, duplicate)
				materials.append(duplicate)

	for child in node.get_children():
		_collect_fade_materials(child, materials)


func _duplicate_fade_material(material: Material) -> Material:
	var duplicate: Material = material.duplicate() as Material
	if duplicate is BaseMaterial3D:
		var base_material: BaseMaterial3D = duplicate as BaseMaterial3D
		base_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return duplicate


func _contains_mesh(node: Node) -> bool:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		return true
	for child in node.get_children():
		if _contains_mesh(child):
			return true
	return false


func _set_visible_recursive(node: Node, value: bool) -> void:
	if node is Node3D:
		(node as Node3D).visible = value
	for child in node.get_children():
		_set_visible_recursive(child, value)


func _find_rigid_body(node: Node) -> RigidBody3D:
	if node is RigidBody3D:
		return node as RigidBody3D
	for child in node.get_children():
		var body: RigidBody3D = _find_rigid_body(child)
		if body:
			return body
	return null


func _resolve_fracture_source() -> Node3D:
	if fracture_source_path != NodePath(""):
		var node: Node = get_node_or_null(fracture_source_path)
		if node is Node3D:
			return node as Node3D
	return null


func _resolve_spawn_parent() -> Node:
	if spawn_parent_path != NodePath(""):
		var node: Node = get_node_or_null(spawn_parent_path)
		if node:
			return node
	if detach_to_scene_root:
		return _resolve_debris_root()
	var parent: Node = get_parent()
	if parent:
		return parent
	return get_tree().current_scene


func _resolve_debris_root() -> Node:
	var scene_root: Node = get_tree().current_scene
	if not scene_root:
		scene_root = get_tree().root

	var existing: Node = scene_root.get_node_or_null(NodePath(String(debris_root_name)))
	if existing:
		return existing

	var debris_root := Node3D.new()
	debris_root.name = String(debris_root_name)
	scene_root.add_child(debris_root)
	return debris_root


func _on_piece_tree_exited(piece: Node3D) -> void:
	_spawned.erase(piece)


func _random_unit_vector() -> Vector3:
	var vector: Vector3 = Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0)
	)
	if vector.length_squared() <= 0.0001:
		return Vector3.UP
	return vector.normalized()
