@tool
extends AutomationTrait
class_name AutomationSpeedTrait

enum Mode { ASSIST, PROPULSION, SOFT_CAP, MAX_SPEED_OVERRIDE }

## Assist follows input. Propulsion also drives neutral input. Caps and maximum-speed overrides are independent channels.
@export var mode: Mode = Mode.ASSIST:
	set(value):
		mode = value
		notify_property_list_changed()
## Uses canonical forward for propulsion, independently of rollback or reverse entry.
@export var canonical_direction: bool = false
## Uses the normal player acceleration and soft-cap pipeline for this Soft Cap target.
@export var player_top_speed: bool = false
## Optional absolute target-speed curve sampled at normalized route progress.
@export var target_speed_curve: Curve
## Along-route target speed, or player maximum for Maximum Speed Override.
@export_range(0.0, 2000.0, 0.1, "suffix:m/s") var target_speed: float = 35.0
## Acceleration or soft-cap deceleration in meters per second squared.
@export_range(0.0, 2000.0, 0.1, "or_greater") var acceleration: float = 18.0
## Allows intentional pullback to suppress automatic propulsion.
@export var allow_braking: bool = true
## Allows drive or soft-cap changes while rolling. Disabled preserves rolling momentum.
@export var affect_rolling: bool = false


func _validate_property(property: Dictionary) -> void:
	if property.name == "allow_braking" and mode != Mode.PROPULSION:
		property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR
	if property.name in ["acceleration", "affect_rolling"] and mode == Mode.MAX_SPEED_OVERRIDE:
		property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR

	if property.name == "player_top_speed" and mode != Mode.SOFT_CAP:
		property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR
	if property.name == "canonical_direction" and mode != Mode.PROPULSION:
		property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR
