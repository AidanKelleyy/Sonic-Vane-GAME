@tool
extends AutomationTrait
class_name AutomationSteeringTrait

enum Mode { INPUT_HEADING, VELOCITY_ALIGNMENT, TANGENT_DAMPING }

## Input Heading assists movement intent. Velocity Alignment rotates momentum without changing its magnitude.
@export var mode: Mode = Mode.INPUT_HEADING:
	set(value):
		mode = value
		notify_property_list_changed()
## Uses canonical forward instead of the session's signed travel direction.
@export var canonical_direction: bool = false
## Per-second removal of velocity perpendicular to the tangent in Tangent Damping mode.
@export_range(0.0, 1000.0, 0.1) var damping_strength: float = 0.0
## Fraction of path heading blended into movement intent.
@export_range(0.0, 1.0, 0.01) var strength: float = 0.35
## Maximum velocity rotation rate. Used by Velocity Alignment.
@export_range(0.0, 3600.0, 1.0, "or_greater", "suffix:deg/s") var turn_rate: float = 180.0
## Preserves deliberate pullback and braking instead of steering against them.
@export var allow_pullback: bool = true


func _validate_property(property: Dictionary) -> void:
	if (property.name == "strength" and mode != Mode.INPUT_HEADING) or (property.name == "turn_rate" and mode != Mode.VELOCITY_ALIGNMENT):
		property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR

	if property.name == "damping_strength" and mode != Mode.TANGENT_DAMPING:
		property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR
	if property.name in ["canonical_direction", "allow_pullback"] and mode == Mode.TANGENT_DAMPING:
		property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR
