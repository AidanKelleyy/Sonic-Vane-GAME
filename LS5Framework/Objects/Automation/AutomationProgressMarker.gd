@tool
extends Node3D
class_name AutomationProgressMarker

signal crossed(body: Node3D, direction: int)

enum Direction { BOTH, FORWARD, REVERSE }
enum Retrigger { ONCE_PER_ACTIVATION, REARM_DISTANCE }

## Enables this event without removing the marker.
@export var enabled: bool = true
## Identifier included in the player's progress event signal.
@export var event_id: StringName = &"marker"
## Normalized canonical distance on the parent route.
@export_range(0.0, 1.0, 0.001) var progress: float = 0.5
## Permitted crossing directions, independent of model facing.
@export var direction: Direction = Direction.BOTH
## Repeats only after a new activation or after leaving the rearm distance.
@export var retrigger: Retrigger = Retrigger.ONCE_PER_ACTIVATION
## Required arc-distance separation before another crossing, in world meters.
@export_range(0.01, 1000.0, 0.1) var rearm_distance: float = 2.0


func permits(direction_value: int) -> bool:
	return direction == Direction.BOTH or (direction == Direction.FORWARD and direction_value > 0) or (direction == Direction.REVERSE and direction_value < 0)


func _get_configuration_warnings() -> PackedStringArray:
	return [] if get_parent() is AutomationSplineCore else PackedStringArray(["Progress markers require an automation source parent."])
