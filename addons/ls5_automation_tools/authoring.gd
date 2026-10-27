@tool
extends RefCounted

const ARRAYS: Array[String] = ["steering_traits", "position_traits", "speed_traits", "surface_traits", "input_traits", "transition_traits", "influence_traits", "camera_traits"]
const PRESETS: Array[String] = ["SoftRouteGuide", "LoopAssist", "GuidedRun", "ScriptedRun", "SideViewRibbon"]
const GENERATED: StringName = &"_AutomationVolumes"
const MARKER: StringName = &"automation_generated"
const CATALOG: Array[Dictionary] = [
	{"label": "Steering / Input heading", "script": "AutomationSteeringTrait", "array": "steering_traits", "mode": 0},
	{"label": "Steering / Velocity alignment", "script": "AutomationSteeringTrait", "array": "steering_traits", "mode": 1},
	{"label": "Position / Soft corridor", "script": "AutomationPositionTrait", "array": "position_traits", "mode": 0},
	{"label": "Position / Collision confinement", "script": "AutomationPositionTrait", "array": "position_traits", "mode": 1},
	{"label": "Position / 2.5D ribbon", "script": "AutomationRibbonTrait", "array": "position_traits", "mode": 2},
	{"label": "Speed / Input assistance", "script": "AutomationSpeedTrait", "array": "speed_traits", "mode": 0},
	{"label": "Speed / Automatic propulsion", "script": "AutomationSpeedTrait", "array": "speed_traits", "mode": 1},
	{"label": "Speed / Soft cap", "script": "AutomationSpeedTrait", "array": "speed_traits", "mode": 2},
	{"label": "Speed / Maximum override", "script": "AutomationSpeedTrait", "array": "speed_traits", "mode": 3},
	{"label": "Surface / Terrain frame", "script": "AutomationSurfaceTrait", "array": "surface_traits", "mode": 0},
	{"label": "Surface / Contact adhesion", "script": "AutomationSurfaceTrait", "array": "surface_traits", "mode": 1},
	{"label": "Input / Permissions", "script": "AutomationInputTrait", "array": "input_traits", "mode": 0},
	{"label": "Input / Horizontal path", "script": "AutomationInputTrait", "array": "input_traits", "mode": 1},
	{"label": "Input / Vertical path", "script": "AutomationInputTrait", "array": "input_traits", "mode": 2},
	{"label": "Transition / Entry", "script": "AutomationTransitionTrait", "array": "transition_traits", "phase": 0},
	{"label": "Transition / Exit", "script": "AutomationTransitionTrait", "array": "transition_traits", "phase": 1},
	{"label": "Influence / Channel weights", "script": "AutomationInfluenceTrait", "array": "influence_traits"},
	{"label": "Camera / Ribbon companion", "script": "AutomationCameraTrait", "array": "camera_traits"},
	{"label": "Steering / Tangent damping", "script": "AutomationSteeringTrait", "array": "steering_traits", "mode": 2},
	{"label": "Position / Speed-scaled attraction", "script": "AutomationPositionTrait", "array": "position_traits", "mode": 3},
	{"label": "Surface / Water bypass", "script": "AutomationSurfaceTrait", "array": "surface_traits", "mode": 2},
]


static func make_component(index: int) -> Resource:
	if index < 0 or index >= CATALOG.size():
		return null
	var item: Dictionary = CATALOG[index]
	var component: Resource = load("res://LS5Framework/Scripts/Player/Automation/Traits/" + String(item.script) + ".gd").new()
	component.resource_local_to_scene = true
	component.resource_name = String(item.label).get_slice(" / ", 1)
	for key: String in ["mode", "phase"]:
		if item.has(key):
			component.set(key, item[key])
	return component


static func preset_properties(index: int) -> Dictionary:
	if index < 0 or index >= PRESETS.size():
		return {}
	var scene: PackedScene = load("res://LS5Framework/Objects/Automation/Presets/" + PRESETS[index] + ".tscn")
	var source: AutomationSplineCore = scene.instantiate() as AutomationSplineCore
	var values: Dictionary = local_properties(source)
	values["capture_distance"] = source.capture_distance
	values["integrate_before_speed_limits"] = source.integrate_before_speed_limits
	values["sample_lookahead"] = source.sample_lookahead
	values["maximum_tracking_window"] = source.maximum_tracking_window
	source.free()
	return values


static func local_properties(source: AutomationSplineCore) -> Dictionary:
	var values: Dictionary = {}
	for key: String in ARRAYS:
		var items: Array = source.get(key).duplicate()
		for index: int in items.size():
			if items[index]:
				items[index] = items[index].duplicate(true)
				items[index].resource_local_to_scene = true
		values[key] = items
	return values


static func refresh(source: AutomationSplineCore) -> void:
	if not is_instance_valid(source):
		return
	source.sampler.configure(source.get_node_or_null(source.path_path) as Path3D)
	source.sampler.invalidate()
	source.update_configuration_warnings()
	source.update_gizmos()


static func preview(source: AutomationSplineCore) -> Dictionary:
	source.sampler.configure(source.get_node_or_null(source.path_path) as Path3D)
	if not source.sampler.refresh():
		return {"valid": false, "message": source.sampler.validation_message}
	var session: AutomationSession = AutomationSession.new()
	session.sample = source.sampler.sample(source.preview_progress * source.sampler.length)
	session.signed_speed = source.preview_speed * float(source.preview_direction)
	session.direction = source.preview_direction
	var weights: Dictionary = {}
	for channel: int in [1, 2, 4, 8, 16]:
		var key: String = {1: "steering_traits", 2: "position_traits", 4: "speed_traits", 8: "surface_traits", 16: "input_traits"}[channel]
		var assigned: bool = false
		for component: AutomationTrait in source.get(key):
			if component and component.applies(true):
				assigned = true
				break
		var weight: float = 1.0 if assigned else 0.0
		for component: AutomationInfluenceTrait in source.influence_traits:
			if component and component.enabled and component.channels & channel:
				weight *= component.get_weight(session, source)
				break
		weights[channel] = weight
	var sample: AutomationSample = session.sample
	for component: AutomationPositionTrait in source.position_traits:
		if component and component.applies(true):
			if component is AutomationRibbonTrait:
				var ribbon: AutomationRibbonState = AutomationRibbonState.new(component, source)
				weights[2] *= ribbon._get_adherence_weight(source.sampler.closed, sample.distance, source.sampler.length)
				weights[16] *= weights[2]
			break
	sample = _preview_sample(source, sample)
	return {"valid": true, "sample": sample, "length": source.sampler.length, "weights": weights,
		"direction": session.direction, "signed_speed": session.signed_speed}


static func build_triggers(source: AutomationSplineCore) -> Node3D:
	source.sampler.configure(source.get_node_or_null(source.path_path) as Path3D)
	if not source.sampler.refresh():
		return null
	var existing: Node = source.get_node_or_null(NodePath(GENERATED))
	if existing and not existing.get_meta(MARKER, false):
		return null
	var container: Node3D = Node3D.new()
	container.name = GENERATED
	container.set_meta(MARKER, true)
	var frame: Transform3D = Transform3D(Basis.IDENTITY, source.global_position)
	container.transform = source.global_transform.affine_inverse() * frame
	container.set_meta(&"automation_basis", source.global_basis)
	var inverse: Transform3D = frame.affine_inverse()
	var width: float = maxf(source.trigger_width, 0.1)
	var height: float = maxf(source.trigger_height, 0.1)
	for index: int in 2:
		var value: AutomationSample = source.sampler.sample(0.0 if index == 0 else source.sampler.length)
		var gate: Area3D = _area("Start" if index == 0 else "End")
		container.add_child(gate)
		gate.transform = inverse * value.get_transform()
		_box(gate, Vector3(width, height, maxf(source.trigger_gate_depth, 0.1)), Transform3D.IDENTITY)
	var volume: Area3D = _area("Volume")
	container.add_child(volume)
	var step: float = maxf(minf(source.trigger_spacing, width * 0.5), 0.1)
	var count: int = clampi(int(ceil(source.sampler.length / step)), 1, 2048)
	for index: int in count:
		var start: AutomationSample = source.sampler.sample(source.sampler.length * float(index) / float(count))
		var finish: AutomationSample = source.sampler.sample(source.sampler.length * float(index + 1) / float(count))
		var middle: AutomationSample = source.sampler.sample(source.sampler.length * (float(index) + 0.5) / float(count))
		var tangent: Vector3 = (finish.position - start.position).normalized()
		if not tangent:
			tangent = middle.tangent
		var up: Vector3 = middle.up.slide(tangent).normalized()
		var side: Vector3 = tangent.cross(up).normalized()
		var pose: Transform3D = Transform3D(Basis(side, side.cross(tangent), -tangent), (start.position + finish.position) * 0.5)
		_box(volume, Vector3(width, height, start.position.distance_to(finish.position) + source.trigger_gate_depth), inverse * pose)
	return container


static func _area(label: String) -> Area3D:
	var area: Area3D = Area3D.new()
	area.name = label
	area.collision_layer = 0
	area.collision_mask = 4
	return area


static func _box(area: Area3D, size: Vector3, pose: Transform3D) -> void:
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "Shape%d" % area.get_child_count()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.resource_local_to_scene = true
	shape.size = size
	collision.shape = shape
	collision.transform = pose
	area.add_child(collision)


static func replace_triggers(source: AutomationSplineCore, remove: Node3D, add: Node3D, owner: Node, paths: Dictionary) -> void:
	if is_instance_valid(remove) and remove.get_parent() == source:
		source.remove_child(remove)
	if is_instance_valid(add):
		source.add_child(add)
		_set_owner(add, owner)
	for key: String in paths:
		source.set(key, paths[key])
	refresh(source)


static func _set_owner(node: Node, owner: Node) -> void:
	node.owner = owner
	for child: Node in node.get_children():
		_set_owner(child, owner)


static func guide_lines(source: AutomationSplineCore) -> Dictionary:
	var state: Dictionary = preview(source)
	if not state.valid:
		return {}
	var lines: Dictionary = {"route": PackedVector3Array(), "corridor": PackedVector3Array(), "frame": PackedVector3Array(), "ramp": PackedVector3Array(), "cursor": PackedVector3Array(), "offset": PackedVector3Array()}
	var inverse: Transform3D = source.global_transform.affine_inverse()
	var count: int = clampi(int(ceil(source.sampler.length / 3.0)), 8, 192)
	var width: float = 0.0
	var ribbon: AutomationRibbonTrait = null
	for component: AutomationPositionTrait in source.position_traits:
		if component and component.applies(true):
			width = component.attraction_radius if component.mode == AutomationPositionTrait.Mode.ATTRACTION else component.free_radius
			ribbon = component as AutomationRibbonTrait
			break
	for index: int in count:
		var a: AutomationSample = _preview_sample(source, source.sampler.sample(source.sampler.length * float(index) / float(count)))
		var b: AutomationSample = _preview_sample(source, source.sampler.sample(source.sampler.length * float(index + 1) / float(count)))
		_line(lines.route, inverse, a.position, b.position)
		if ribbon:
			for side: float in [-1.0, 1.0]:
				_line(lines.corridor, inverse, a.position + a.up * source.trigger_height * 0.5 * side, b.position + b.up * source.trigger_height * 0.5 * side)
		elif width > 0.0:
			for side: float in [-1.0, 1.0]:
				_line(lines.corridor, inverse, a.position + a.normal * width * side, b.position + b.normal * width * side)
		if index % maxi(count / 12, 1) == 0:
			for direction: int in [1, -1]:
				if source.permits_direction(direction):
					_arrow(lines.route, inverse, a.position, a.tangent * float(direction), a.normal, minf(2.0, source.sampler.length / 30.0))
	var sample: AutomationSample = state.sample
	_arrow(lines.cursor, inverse, sample.position, sample.tangent * float(source.preview_direction), sample.normal, 3.0)
	_line(lines.frame, inverse, sample.position, sample.position + sample.normal * 4.0)
	_line(lines.cursor, inverse, sample.position, sample.position + sample.up * 3.0)
	# Capture limit at the preview position.
	var capture: float = source.failsafe_exit_distance if source is AutomationDepthProfile else source.capture_distance
	for index: int in (32 if capture > 0.0 else 0):
		var a: float = TAU * float(index) / 32.0
		var b: float = TAU * float(index + 1) / 32.0
		_line(lines.frame, inverse, sample.position + (sample.normal * cos(a) + sample.up * sin(a)) * capture,
			sample.position + (sample.normal * cos(b) + sample.up * sin(b)) * capture)
	var ramps: Array[float] = []
	if ribbon:
		ramps.assign([ribbon.entry_blend_distance, source.sampler.length - ribbon.exit_blend_distance])
	for component: AutomationInfluenceTrait in source.influence_traits:
		if component and component.enabled:
			if component.start_ramp > 0.0:
				ramps.append(component.start_ramp)
			if component.end_ramp > 0.0:
				ramps.append(source.sampler.length - component.end_ramp)
	if not source.sampler.closed:
		for distance: float in ramps:
			var value: AutomationSample = source.sampler.sample(distance)
			_line(lines.ramp, inverse, value.position - value.normal * 3.0, value.position + value.normal * 3.0)
	if source is AutomationDepthProfile:
		var target: AutomationSplineCore = source.get_node_or_null(source.automation_spline_path) as AutomationSplineCore if source.automation_spline_path else source.get_parent() as AutomationSplineCore
		if target:
			target.sampler.configure(target.get_node_or_null(target.path_path) as Path3D)
			if target.sampler.refresh():
				for index: int in 13:
					var value: AutomationSample = source.sampler.sample(source.sampler.length * float(index) / 12.0)
					var main: AutomationSample = _preview_sample(target, target.sampler.closest(value.position))
					_line(lines.offset, inverse, value.position, value.position - main.normal * (value.position - main.position).dot(main.normal))
	return lines


static func _preview_sample(source: AutomationSplineCore, value: AutomationSample) -> AutomationSample:
	for component: AutomationPositionTrait in source.position_traits:
		if not component or not component.applies(true):
			continue
		if not component is AutomationRibbonTrait:
			break
		var ribbon: AutomationRibbonTrait = component as AutomationRibbonTrait
		if ribbon.cubic_path_sampling:
			value = source.sampler.smooth_sample(value, ribbon.tangent_lookahead)
		var normal: Vector3 = value.normal
		if ribbon.plane_frame_mode in [AutomationRibbonTrait.PlaneFrameMode.GRAVITY_RIBBON, AutomationRibbonTrait.PlaneFrameMode.PLAYER_RIBBON]:
			normal = value.tangent.cross(Vector3.UP)
		elif ribbon.plane_frame_mode == AutomationRibbonTrait.PlaneFrameMode.FIXED_PATH_AXIS:
			normal = (source.get_node(source.path_path) as Path3D).global_basis.x
		normal = normal.slide(value.tangent)
		if not normal:
			normal = value.normal
		value.normal = normal.normalized() * (-1.0 if ribbon.reverse_plane_normal else 1.0)
		value.up = value.normal.cross(value.tangent).normalized()
		break
	return value


static func _line(lines: PackedVector3Array, inverse: Transform3D, from: Vector3, to: Vector3) -> void:
	lines.append(inverse * from)
	lines.append(inverse * to)


static func _arrow(lines: PackedVector3Array, inverse: Transform3D, point: Vector3, tangent: Vector3, side: Vector3, size: float) -> void:
	var tip: Vector3 = point + tangent * size
	_line(lines, inverse, point, tip)
	_line(lines, inverse, tip, tip - tangent * size * 0.4 + side * size * 0.3)
	_line(lines, inverse, tip, tip - tangent * size * 0.4 - side * size * 0.3)
