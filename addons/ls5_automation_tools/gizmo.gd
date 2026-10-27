@tool
extends EditorNode3DGizmoPlugin

const Authoring = preload("res://addons/ls5_automation_tools/authoring.gd")


func _init() -> void:
	create_material("route", Color(0.15, 0.8, 1.0))
	create_material("corridor", Color(0.65, 0.4, 1.0))
	create_material("frame", Color(1.0, 0.3, 0.25))
	create_material("ramp", Color(1.0, 0.8, 0.2))
	create_material("cursor", Color(0.3, 1.0, 0.4))
	create_material("offset", Color(1.0, 0.6, 0.15))


func _get_gizmo_name() -> String:
	return "Automation"


func _has_gizmo(node: Node3D) -> bool:
	return node is AutomationSplineCore


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var source: AutomationSplineCore = gizmo.get_node_3d() as AutomationSplineCore
	if not source or not source.show_authoring_guides:
		return
	var lines: Dictionary = Authoring.guide_lines(source)
	var selected: bool = false
	for node: Node in EditorInterface.get_selection().get_selected_nodes():
		if node == source or source.is_ancestor_of(node):
			selected = true
			break
	for key: String in lines:
		if key != "route" and not selected:
			continue
		var points: PackedVector3Array = lines[key]
		if not points.is_empty():
			gizmo.add_lines(points, get_material(key, gizmo))
			if key == "route":
				gizmo.add_collision_segments(points)
