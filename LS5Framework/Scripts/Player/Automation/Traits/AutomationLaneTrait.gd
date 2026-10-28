@tool
extends AutomationPositionTrait
class_name AutomationLaneTrait

## Number of lanes centered on the canonical route normal.
@export_range(1, 16, 1) var lane_count: int = 3
## Distance between adjacent lane centers, in world meters.
@export_range(0.1, 100.0, 0.1) var lane_spacing: float = 2.0
## Initial lane index. Values beyond Lane Count use the nearest valid index.
@export_range(0, 15, 1) var initial_lane: int = 1
## Minimum deliberate lateral input for a single lane change.
@export_range(0.1, 1.0, 0.01) var input_threshold: float = 0.6


func offset(index: int) -> float:
	return (float(clampi(index, 0, lane_count - 1)) - float(lane_count - 1) * 0.5) * lane_spacing


func _init() -> void:
	mode = Mode.CORRIDOR
	free_radius = 0.15


func _validate_property(property: Dictionary) -> void:
	super._validate_property(property)
	if property.name in ["mode", "attraction_acceleration", "attraction_per_speed", "attraction_speed_scale", "attraction_radius", "correction_speed", "obstruction"]:
		property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR
