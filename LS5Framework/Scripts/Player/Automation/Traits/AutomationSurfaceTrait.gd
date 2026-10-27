@tool
extends AutomationTrait
class_name AutomationSurfaceTrait

enum Mode { TERRAIN_FRAME, ADHESION, WATER_BYPASS }
enum UpMode { SURFACE, GRAVITY, PATH }

## Terrain Frame selects correction axes. Adhesion preserves valid contact without suppressing intentional jumps.
@export var mode: Mode = Mode.TERRAIN_FRAME:
	set(value):
		mode = value
		notify_property_list_changed()
## Up axis used for grounded route projection. Airborne correction always preserves gravity-up motion.
@export var up_mode: UpMode = UpMode.SURFACE


func _validate_property(property: Dictionary) -> void:
	if property.name == "up_mode" and mode != Mode.TERRAIN_FRAME:
		property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR
