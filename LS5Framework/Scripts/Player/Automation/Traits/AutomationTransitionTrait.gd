@tool
extends Resource
class_name AutomationTransitionTrait

enum Phase { ENTRY, EXIT }
enum Mode { INSTANT, TIME, DISTANCE }

## Enables this transition.
@export var enabled: bool = true
## Entry or ordinary release transition. Death, teleport, disable, and removal release immediately.
@export var phase: Phase = Phase.ENTRY
## Channels affected by this transition. First entry per channel and phase wins.
@export_flags("Steering", "Position", "Speed", "Surface", "Input") var channels: int = 31
## Time uses real unpaused seconds. Distance uses accumulated route travel.
@export var mode: Mode = Mode.TIME:
	set(value):
		mode = value
		notify_property_list_changed()
## Transition duration in unpaused seconds.
@export_range(0.0, 10.0, 0.01, "suffix:s") var duration: float = 0.35
## Transition travel distance in world meters.
@export_range(0.01, 1000.0, 0.1, "suffix:m") var distance: float = 8.0
## Applies smoothstep to the transition fraction.
@export var smooth: bool = true


func _validate_property(property: Dictionary) -> void:
	if (property.name == "duration" and mode != Mode.TIME) or (property.name == "distance" and mode != Mode.DISTANCE):
		property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR
