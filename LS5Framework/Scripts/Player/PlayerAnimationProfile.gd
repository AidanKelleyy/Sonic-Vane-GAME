extends Resource
class_name PlayerAnimationProfile

## Enables the Motion branch with independent Ground, Air, and Ball state machines.
@export var hierarchical_motion: bool = false
## Compatibility movement commands mapped to family or family/state targets.
@export var motion_commands: Dictionary[StringName, StringName] = {}
## Enables fixed action-family selection and director-owned animation evaluation.
@export var hierarchical_actions: bool = false
## Presentation commands mapped to action-family/state destinations.
@export var presentation_commands: Dictionary[StringName, StringName] = {}
## Compatibility state names exposed by each action-family/state target.
@export var presentation_state_names: Dictionary[StringName, StringName] = {}
## Playback rate for finite actions, tricks, skydive, and parkour.
@export_range(0.0, 4.0, 0.01) var action_playback_scale: float = 1.0
## Playback rate for hurt and death, independent of movement playback.
@export_range(0.0, 4.0, 0.01) var reaction_playback_scale: float = 1.0
## Playback rate for carry gestures and their authored release markers.
@export_range(0.0, 4.0, 0.01) var carry_playback_scale: float = 1.0
## Enables generation-bound carry markers and finite landing-roll playback.
@export var normalized_markers: bool = false

## Persistent presentation IDs mapped to commands supported by the current tree adapter.
@export var action_commands: Dictionary[StringName, StringName] = {}
## Discrete presentation events mapped to commands supported by the current tree adapter.
@export var event_commands: Dictionary[StringName, StringName] = {}
## Action phases keyed as action_id/phase_id and mapped to tree adapter commands.
@export var phase_commands: Dictionary[StringName, StringName] = {}
## Default fade duration. Negative values retain the tree's authored transition settings.
@export_range(-1.0, 2.0, 0.01) var default_crossfade: float = -1.0
## Maximum number of discrete requests retained before new requests are rejected.
@export_range(1, 128, 1) var event_queue_capacity: int = 16
## Time a discrete request may wait for dispatch, measured in animation update seconds.
@export_range(0.01, 2.0, 0.01) var event_lifetime: float = 0.25


func get_action_command(action_id: StringName, phase_id: StringName = &"") -> StringName:
	if phase_id != &"":
		return phase_commands.get(StringName("%s/%s" % [action_id, phase_id]), &"")
	return action_commands.get(action_id, &"")


func get_event_command(event_id: StringName) -> StringName:
	return event_commands.get(event_id, &"")
