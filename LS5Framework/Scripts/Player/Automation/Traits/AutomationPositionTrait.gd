@tool
extends AutomationTrait
class_name AutomationPositionTrait

enum Mode { CORRIDOR, CONFINEMENT, RIBBON, ATTRACTION }
enum Obstruction { BLOCK, RELEASE }

## Corridor applies bounded acceleration. Confinement also performs a collision-tested post-movement correction.
@export var mode: Mode = Mode.CORRIDOR:
	set(value):
		mode = value
		notify_property_list_changed()
## Constant centering acceleration for Attraction mode.
@export_range(0.0, 100000.0, 0.1) var attraction_acceleration: float = 0.0
## Additional attraction acceleration per speed unit. Uses along-spline speed when selected.
@export_range(0.0, 1000.0, 0.01) var attraction_per_speed: float = 0.0
## Uses absolute speed along the sampled spline tangent for both attraction speed terms. Disabled preserves total/planar speed scaling.
@export var attraction_use_along_speed: bool = false
## Multiplies attraction by one plus planar speed times this factor, or along-spline speed when selected.
@export_range(0.0, 1.0, 0.001) var attraction_speed_scale: float = 0.0
## Attraction falls to zero at this projected distance. Zero disables range falloff.
@export_range(0.0, 1000.0, 0.01) var attraction_radius: float = 0.0
## Free distance from the route before centering begins, in world meters.
@export_range(0.0, 100.0, 0.05, "suffix:m") var free_radius: float = 2.0
## Acceleration per meter outside the free corridor.
@export_range(0.0, 500.0, 0.1) var spring_strength: float = 12.0
## Damping of cross-route velocity outside the free corridor.
@export_range(0.0, 100.0, 0.1) var damping: float = 6.0
## Maximum centering acceleration, in world meters per second squared.
@export_range(0.0, 1000.0, 0.1, "or_greater") var max_acceleration: float = 30.0
## Maximum collision-tested correction speed for Confinement.
@export_range(0.0, 1000.0, 0.1, "suffix:m/s") var correction_speed: float = 24.0
## Response when collision prevents confinement.
@export var obstruction: Obstruction = Obstruction.BLOCK


func _validate_property(property: Dictionary) -> void:
	if property.name in ["correction_speed", "obstruction"] and mode == Mode.CORRIDOR:
		property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR

	if String(property.name).begins_with("attraction_") and mode != Mode.ATTRACTION:
		property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR
	if property.name in ["free_radius", "spring_strength", "damping", "correction_speed"] and mode == Mode.ATTRACTION:
		property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR
