extends RefCounted

const PREFIX: StringName = &"ls5_automation_edit"
const TRAITS: Array[String] = ["AutomationTrait", "AutomationSteeringTrait", "AutomationPositionTrait", "AutomationRibbonTrait", "AutomationLaneTrait", "AutomationSpeedTrait", "AutomationSurfaceTrait", "AutomationInputTrait", "AutomationTransitionTrait", "AutomationInfluenceTrait", "AutomationCameraTrait"]
const EXTENSIONS: Dictionary = {"connection": preload("res://LS5Framework/Objects/Automation/AutomationRouteConnection.gd"), "marker": preload("res://LS5Framework/Objects/Automation/AutomationProgressMarker.gd")}
const SHAPES: Array[String] = ["BoxShape3D", "SphereShape3D", "CapsuleShape3D", "CylinderShape3D"]
static var monitoring: bool = false
static var _next_report: int = 0


static func capture(message: String, data: Array) -> bool:
	if message == "monitor" and data.size() == 1:
		monitoring = bool(data[0])
		return true
	if message != "configuration" or data.size() != 3 or not data[2] is Dictionary:
		return false
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if not tree:
		return true
	for source: Node in tree.get_nodes_in_group(&"LiveAutomationSources"):
		var ancestor: Node = source
		while ancestor and ancestor != tree.root:
			if ancestor.scene_file_path == String(data[0]) and ancestor.get_path_to(source) == NodePath(data[1]):
				apply_snapshot(source, data[2])
				break
			ancestor = ancestor.get_parent()
	return true


static func poll(source: Node) -> void:
	if not monitoring or not EngineDebugger.is_active() or not source.is_in_group(&"LiveAutomationSources"):
		return
	var now: int = Time.get_ticks_msec()
	if now < _next_report:
		return
	_next_report = now + 250
	var records: Array[Dictionary] = []
	for body: Node in source.get_tree().get_nodes_in_group(&"AutomationDebugPlayers"):
		if body.has_method("get_automation_controller"):
			var controller: RefCounted = body.call("get_automation_controller")
			if controller:
				records.append(controller.call("get_diagnostics"))
	EngineDebugger.send_message("ls5_automation_edit:diagnostics", records)


static func _properties(object: Object) -> Array[Dictionary]:
	var script: Script = object.get_script() as Script
	return script.get_script_property_list() if script else []


static func encode(value: Variant) -> Variant:
	if value is Curve:
		var curve: Curve = value
		var points: Array[Dictionary] = []
		for index: int in curve.point_count:
			points.append({"position": curve.get_point_position(index), "left": curve.get_point_left_tangent(index), "right": curve.get_point_right_tangent(index), "left_mode": curve.get_point_left_mode(index), "right_mode": curve.get_point_right_mode(index)})
		return {"curve": points, "min_domain": curve.min_domain, "max_domain": curve.max_domain, "min_value": curve.min_value, "max_value": curve.max_value}
	if value is Resource:
		var component: Resource = value
		var script: Script = component.get_script() as Script
		if not script or not _allowed(script.resource_path):
			return null
		var values: Dictionary = {}
		for property: Dictionary in _properties(component):
			if int(property.usage) & PROPERTY_USAGE_STORAGE:
				values[property.name] = encode(component.get(property.name))
		return {"component_script": script.resource_path, "properties": values, "name": component.resource_name}
	if value is Array:
		var items: Array = []
		for item: Variant in value:
			items.append(encode(item))
		return items
	return value if not value is Object else null


static func _allowed(path: String) -> bool:
	return path.get_base_dir() == "res://LS5Framework/Scripts/Player/Automation/Traits" and path.get_file().get_basename() in TRAITS


static func decode(value: Variant, current: Variant = null) -> Variant:
	if value is Dictionary and value.has("curve"):
		var curve: Curve = Curve.new()
		curve.min_domain = value.min_domain
		curve.max_domain = value.max_domain
		curve.min_value = value.min_value
		curve.max_value = value.max_value
		for point: Dictionary in value.curve:
			curve.add_point(point.position, point.left, point.right, point.left_mode, point.right_mode)
		return curve
	if value is Dictionary and value.has("component_script"):
		if not _allowed(String(value.component_script)):
			return null
		var script: Script = load(String(value.component_script)) as Script
		var component: Resource = current as Resource if current is Resource and current.get_script() == script else script.new()
		apply_properties(component, value.properties)
		component.resource_name = String(value.get("name", ""))
		component.emit_changed()
		return component
	if value is Array:
		var items: Array = current.duplicate() if current is Array else []
		items.clear()
		for index: int in value.size():
			var previous: Variant = current[index] if current is Array and index < current.size() else null
			var item: Variant = decode(value[index], previous)
			if items.get_typed_script() != null and item != null and (not item is Object or not is_instance_of(item, items.get_typed_script())):
				continue
			items.append(item)
		return items
	return value


static func apply_properties(object: Object, values: Dictionary) -> void:
	var allowed: Dictionary = {}
	for property: Dictionary in _properties(object):
		if int(property.usage) & PROPERTY_USAGE_STORAGE:
			allowed[property.name] = true
	for key: String in values:
		if allowed.has(key):
			object.set(key, decode(values[key], object.get(key)))


static func snapshot(source: Node3D) -> Dictionary:
	var values: Dictionary = {}
	for property: Dictionary in _properties(source):
		if int(property.usage) & PROPERTY_USAGE_STORAGE:
			values[property.name] = encode(source.get(property.name))
	var children: Dictionary = {}
	_collect(source, source, children)
	return {"properties": values, "transform": source.transform, "children": children}


static func _collect(root: Node3D, node: Node, children: Dictionary) -> void:
	for child: Node in node.get_children():
		if child.has_method("refresh_live_configuration"):
			continue
		if child is AutomationRouteConnection or child is AutomationProgressMarker:
			var properties: Dictionary = {}
			for property: Dictionary in _properties(child):
				if int(property.usage) & PROPERTY_USAGE_STORAGE:
					properties[property.name] = encode(child.get(property.name))
			children[String(root.get_path_to(child))] = {"class": "Node3D", "transform": child.transform, "extension": "connection" if child is AutomationRouteConnection else "marker", "properties": properties}
			continue
		if child is Node3D and (child is Path3D or child is Area3D or child is CollisionShape3D or child.get_meta(&"automation_generated", false)):
			var state: Dictionary = {"class": child.get_class(), "transform": child.transform, "generated": child.get_meta(&"automation_generated", false)}
			if child.has_meta(&"automation_basis"):
				state["basis"] = child.get_meta(&"automation_basis")
			if child is Area3D:
				state["area"] = {"collision_layer": child.collision_layer, "collision_mask": child.collision_mask}
			if child is Path3D and child.curve:
				var points: Array[Dictionary] = []
				for index: int in child.curve.point_count:
					points.append({"position": child.curve.get_point_position(index), "in": child.curve.get_point_in(index), "out": child.curve.get_point_out(index), "tilt": child.curve.get_point_tilt(index)})
				state["curve"] = {"points": points, "closed": child.curve.closed, "up_vector_enabled": child.curve.up_vector_enabled, "bake_interval": child.curve.bake_interval}
			if child is CollisionShape3D:
				state["disabled"] = child.disabled
				state["shape"] = _shape_snapshot(child.shape)
			children[String(root.get_path_to(child))] = state
		_collect(root, child, children)


static func _shape_snapshot(shape: Shape3D) -> Dictionary:
	if not shape or not shape.get_class() in SHAPES:
		return {}
	var values: Dictionary = {}
	for key: String in ["size", "radius", "height"]:
		for property: Dictionary in shape.get_property_list():
			if String(property.name) == key:
				values[key] = shape.get(key)
	return {"class": shape.get_class(), "values": values}


static func _activation(state: Dictionary) -> Dictionary:
	var values: Dictionary = {}
	for key: String in ["activation_mode", "area_crossings_bidirectional", "require_group", "direction_policy", "path_path", "volume_path", "start_gate_path", "end_gate_path", "automation_spline_path"]:
		values[key] = state.properties.get(key)
	values["transform"] = state.transform
	var gates: Dictionary = {}
	for path: String in state.children:
		var child: Dictionary = state.children[path]
		if child["class"] in ["Area3D", "CollisionShape3D"] or child.get("generated", false) or child.has("extension"):
			gates[path] = child
	values["gates"] = gates
	return values


static func apply_snapshot(source: Node3D, state: Dictionary) -> void:
	if not state.has_all(["properties", "transform", "children"]):
		return
	var changed: bool = _activation(snapshot(source)) != _activation(state)
	apply_properties(source, state.properties)
	source.transform = state.transform
	for child: Node in source.get_children():
		if (child is AutomationRouteConnection or child is AutomationProgressMarker) and not state.children.has(String(source.get_path_to(child))):
			source.remove_child(child)
			child.queue_free()
	var generated: Node = source.get_node_or_null("_AutomationVolumes")
	if generated and generated.get_meta(&"automation_generated", false):
		# Generated children are replaced as one authoring unit.
		source.remove_child(generated)
		generated.queue_free()
	for path: String in state.children:
		var data: Dictionary = state.children[path]
		var child: Node3D = source.get_node_or_null(NodePath(path)) as Node3D
		if data.has("extension"):
			if not EXTENSIONS.has(data.extension) or "/" in path or ".." in path:
				continue
			if not child:
				child = EXTENSIONS[data.extension].new()
				child.name = path
				source.add_child(child)
			if child.get_script() == EXTENSIONS[data.extension]:
				apply_properties(child, data.properties)
			continue
		if not child:
			if not path.begins_with("_AutomationVolumes") or ".." in path or not String(data["class"]) in ["Node3D", "Area3D", "CollisionShape3D"]:
				continue
			var parent: Node = source.get_node_or_null(NodePath(path.get_base_dir())) if "/" in path else source
			if not parent:
				continue
			child = ClassDB.instantiate(String(data["class"])) as Node3D
			child.name = path.get_file()
			parent.add_child(child)
		child.transform = data.transform
		if data.get("generated", false):
			child.set_meta(&"automation_generated", true)
		if data.has("basis"):
			child.set_meta(&"automation_basis", data.basis)
		if child is Area3D and data.has("area"):
			child.collision_layer = data.area.collision_layer
			child.collision_mask = data.area.collision_mask
		if child is Path3D and data.has("curve"):
			var curve: Curve3D = Curve3D.new()
			curve.closed = data.curve.closed
			curve.up_vector_enabled = data.curve.up_vector_enabled
			curve.bake_interval = data.curve.bake_interval
			for point: Dictionary in data.curve.points:
				curve.add_point(point.position, point["in"], point.out)
				curve.set_point_tilt(curve.point_count - 1, point.tilt)
			child.curve = curve
		if child is CollisionShape3D:
			if data.has("shape") and not data.shape.is_empty() and String(data.shape["class"]) in SHAPES:
				var shape: Shape3D = ClassDB.instantiate(String(data.shape["class"])) as Shape3D
				for key: String in data.shape["values"]:
					shape.set(key, data.shape["values"][key])
				child.shape = shape
			child.set_deferred("disabled", bool(data.get("disabled", false)))
	source.call("refresh_live_configuration", changed)
