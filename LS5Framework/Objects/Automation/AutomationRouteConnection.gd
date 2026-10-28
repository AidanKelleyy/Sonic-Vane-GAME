@tool
extends Node3D
class_name AutomationRouteConnection

enum Choice { DEFAULT, LEFT, RIGHT }

## Enables this junction without removing its configuration.
@export var enabled: bool = true
## Destination automation source, resolved relative to this connection.
@export_node_path("Node3D") var destination_path: NodePath
## Normalized distance on the parent route where transfer occurs.
@export_range(0.0, 1.0, 0.001) var source_progress: float = 1.0
## Canonical direction crossing the source junction.
@export_enum("Forward:1", "Reverse:-1") var source_direction: int = 1
## Normalized distance on the destination route.
@export_range(0.0, 1.0, 0.001) var destination_progress: float = 0.0
## Travel direction after transfer. Reverse connections are authored independently.
@export_enum("Forward:1", "Reverse:-1") var destination_direction: int = 1
## Buffered canonical left/right choice, independent of camera orientation.
@export var choice: Choice = Choice.DEFAULT
## Maximum age of a buffered choice at this junction, in seconds.
@export_range(0.0, 3.0, 0.01) var buffer_seconds: float = 0.4
## Minimum deliberate lateral input for a branch choice.
@export_range(0.1, 1.0, 0.01) var input_threshold: float = 0.6
## Largest permitted route gap, in world meters. Transfers never reposition the body.
@export_range(0.01, 20.0, 0.01) var maximum_gap: float = 2.0
## Maximum travel-heading change across the junction, in degrees.
@export_range(0.0, 180.0, 0.1) var maximum_angle: float = 60.0
## Minimum agreement between source and destination up vectors.
@export_range(-1.0, 1.0, 0.01) var minimum_up_dot: float = 0.5
## Draws the destination and travel arrows in the parent route gizmo.
@export var show_preview: bool = true


func get_source() -> AutomationSplineCore:
	return get_parent() as AutomationSplineCore


func get_destination() -> AutomationSplineCore:
	return get_node_or_null(destination_path) as AutomationSplineCore if destination_path else null


func preview() -> Dictionary:
	var source: AutomationSplineCore = get_source()
	var destination: AutomationSplineCore = get_destination()
	if not source or not destination or source == destination:
		return {"valid": false, "reason": "A distinct destination route is required."}
	source.sampler.configure(source.get_node_or_null(source.path_path) as Path3D)
	destination.sampler.configure(destination.get_node_or_null(destination.path_path) as Path3D)
	if not source.sampler.refresh() or not destination.sampler.refresh():
		return {"valid": false, "reason": "Both routes require valid curves."}
	var start: AutomationSample = source.sampler.sample(source_progress * source.sampler.length)
	var finish: AutomationSample = destination.sampler.sample(destination_progress * destination.sampler.length)
	var reason: String = ""
	if not source.permits_direction(source_direction) or not destination.permits_direction(destination_direction):
		reason = "Connection directions conflict with a route direction policy."
	elif start.position.distance_to(finish.position) > maximum_gap:
		reason = "Connection gap exceeds Maximum Gap."
	elif (start.tangent * float(source_direction)).dot(finish.tangent * float(destination_direction)) < cos(deg_to_rad(maximum_angle)) - 0.00001:
		reason = "Connection heading exceeds Maximum Angle."
	elif start.up.dot(finish.up) < minimum_up_dot:
		reason = "Connection up vectors are incompatible."
	return {"valid": reason.is_empty(), "reason": reason, "start": start, "finish": finish}


func _get_configuration_warnings() -> PackedStringArray:
	if not enabled:
		return []
	var value: Dictionary = preview()
	return [] if value.valid else PackedStringArray([value.reason])
