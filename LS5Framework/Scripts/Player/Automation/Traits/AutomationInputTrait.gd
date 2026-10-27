@tool
extends AutomationTrait
class_name AutomationInputTrait

enum Mode { PERMISSIONS, PATH_HORIZONTAL, PATH_VERTICAL }

## Permissions restrict selected actions. Path modes map an input axis to canonical route travel.
@export var mode: Mode = Mode.PERMISSIONS:
	set(value):
		mode = value
		notify_property_list_changed()
## Blocks movement intent while retaining physical momentum.
@export var block_movement: bool = false
## Retains opposing input for braking when movement is blocked.
@export var allow_braking: bool = true
## Blocks jump requests.
@export var block_jump: bool = false
## Blocks new roll and spindash requests.
@export var block_roll_spindash: bool = false
## Blocks drift requests.
@export var block_drift: bool = false
## Blocks other modular ability requests.
@export var block_abilities: bool = false
## Additional action IDs blocked by this policy. The actions ID blocks every action category.
@export var blocked_actions: Array[StringName] = []
## Releases guidance when a permitted jump is requested.
@export var release_on_jump: bool = false
## Releases guidance when lateral input exceeds Breakaway Input.
@export var lateral_breakaway: bool = false
## Minimum lateral input required for breakaway.
@export_range(0.1, 1.0, 0.01) var breakaway_input: float = 0.85
## Influence required to engage permissions. Release Influence must be lower.
@export_range(0.01, 1.0, 0.01) var engage_influence: float = 0.6
## Influence below which engaged permissions release.
@export_range(0.0, 0.99, 0.01) var release_influence: float = 0.4
## Input-axis magnitude ignored by path mapping.
@export_range(0.0, 0.99, 0.01) var input_deadzone: float = 0.01
## Reverses the authored path input mapping independently of travel direction.
@export var reverse_axis: bool = false


func _validate_property(property: Dictionary) -> void:
	if not int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
		return
	var permissions: bool = mode == Mode.PERMISSIONS
	if property.name not in ["enabled", "grounded", "airborne", "mode", "resource_name", "resource_local_to_scene", "script"]:
		if (property.name in ["reverse_axis", "input_deadzone"] and permissions) or (not property.name in ["reverse_axis", "input_deadzone"] and not permissions):
			property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR
