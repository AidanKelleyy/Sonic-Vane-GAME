@tool
extends Resource
class_name AutomationCameraTrait

enum CameraSide {
	RIGHT_OF_PATH,
	LEFT_OF_PATH,
}

enum CameraUpMode {
	GRAVITY,
	PLAYER,
	PATH_FRAME,
}

enum CameraIdleLeadMode {
	RECENTER,
	HOLD_LAST_DIRECTION,
}

@export_group("Spline Camera")
## Registers this spline as a dynamic camera constraint for the local player.
@export var camera_enabled: bool = true
## Higher values win when this camera overlaps other camera constraints.
@export var constraint_priority: int = 10
## Clears previously registered camera constraints when this spline camera activates.
@export var override_previous_camera_constraints: bool = false
## Chooses which side of the movement ribbon the camera occupies.
@export var camera_side: CameraSide = CameraSide.RIGHT_OF_PATH
## Chooses the camera's vertical frame independently from the movement ribbon.
@export var camera_up_mode: CameraUpMode = CameraUpMode.GRAVITY
## Prevents manual orbit and zoom while the spline camera is influencing.
@export var disable_camera_controls: bool = true
## Aims the final camera directly at the player instead of using the generated path frame.
@export var face_player: bool = false
## Fraction of the final face-player rotation applied by the camera rig.
@export_range(0.0, 1.0, 0.01) var aim_strength: float = 1.0
## Response speed for face-player aiming.
@export_range(0.0, 200.0, 0.1, "or_greater") var aim_smooth: float = 14.0
## World-space aim offset from the player's origin.
@export var aim_target_offset: Vector3 = Vector3(0.0, 1.5, 0.0)
## Applies the vertical aim offset along player up instead of gravity up.
@export var aim_offset_uses_player_up: bool = false
## Uses player up as the face-player look-at up axis.
@export var aim_up_uses_player_up: bool = false
## Allows the camera frame to roll with its selected up axis.
@export var allow_roll: bool = false
## Additional roll around the camera viewing axis.
@export_range(-180.0, 180.0, 0.1, "suffix:deg") var roll_deg: float = 0.0
## Overrides the camera rig's player-up setting while this spline is active.
@export var override_use_player_up: bool = true
## Player-up setting used by the camera rig during the override.
@export var target_use_player_up: bool = false

@export_group("Camera Framing")
## Overrides the normal player-controlled camera distance.
@export var distance_override_enabled: bool = true
## Distance from the movement ribbon while the override is active.
@export_range(0.01, 10000.0, 0.1, "or_greater", "suffix:m") var distance_override: float = 18.0
## Vertical tracking offset along the selected camera up axis.
@export_range(-1000.0, 1000.0, 0.1, "suffix:m") var camera_vertical_offset: float = 2.0
## Fixed tracking lead along the path in the current travel direction.
@export_range(-1000.0, 1000.0, 0.1, "suffix:m") var camera_path_lead_distance: float = 2.0
## Additional tracking lead calculated from signed path speed.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var camera_velocity_lead_time: float = 0.15
## Maximum absolute fixed and velocity lead. Zero removes the limit.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m") var camera_max_lead_distance: float = 12.0
## Minimum absolute path speed required before travel selects a lead direction.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m/s") var camera_lead_direction_speed: float = 1.0
## Chooses whether fixed lead recenters or retains its last direction below the direction speed.
@export var camera_idle_lead_mode: CameraIdleLeadMode = CameraIdleLeadMode.RECENTER
## Response speed used when lead approaches a moving target. Zero applies immediately.
@export_range(0.0, 200.0, 0.1, "or_greater") var camera_lead_smoothing: float = 4.0
## Response speed used when lead recenters at low speed. Zero applies immediately.
@export_range(0.0, 200.0, 0.1, "or_greater") var camera_lead_recenter_smoothing: float = 3.0
## Maximum camera-lead adjustment speed. Zero removes the limit.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m/s") var camera_lead_max_adjustment_speed: float = 16.0
## Removes the player's remaining depth error from the camera tracking point.
@export var camera_center_on_plane: bool = true

@export_group("Camera Lens")
## Overrides field of view while the spline camera is active.
@export var fov_override_enabled: bool = false
## Field of view used by the spline camera.
@export_range(1.0, 179.0, 0.1, "suffix:deg") var fov_override: float = 55.0
## Adjusts field of view by player distance from the tracking point.
@export var fov_distance_based_enabled: bool = false
## Field of view at or inside the near distance.
@export_range(1.0, 179.0, 0.1, "suffix:deg") var fov_distance_near_fov: float = 55.0
## Field of view at or beyond the far distance.
@export_range(1.0, 179.0, 0.1, "suffix:deg") var fov_distance_far_fov: float = 45.0
## Distance where the near field of view is fully applied.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m") var fov_distance_near: float = 0.0
## Distance where the far field of view is fully applied.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m") var fov_distance_far: float = 30.0

@export_group("Camera Transitions")
## Adds a timed entry transition when the spline first becomes active.
@export var entry_smoothing_enabled: bool = false
## Duration of the camera entry transition.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var entry_smoothing_duration: float = 0.25
## Adds a timed transition when the spline camera releases.
@export var exit_smoothing_enabled: bool = true
## Duration of camera release smoothing.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var exit_smoothing_duration: float = 0.35
## Response speed for camera tracking-point movement. Zero follows directly.
@export_range(0.0, 200.0, 0.1, "or_greater") var position_smoothing: float = 14.0
## Response speed for generated path-frame rotation. Zero follows directly.
@export_range(0.0, 200.0, 0.1, "or_greater") var rotation_smoothing: float = 10.0
## Response speed for field-of-view changes. Zero applies directly.
@export_range(0.0, 200.0, 0.1, "or_greater") var fov_smoothing: float = 8.0
## Applies FOV smoothing even when timed entry smoothing is disabled.
@export var fov_smoothing_independent: bool = true
## Overrides camera collision while this spline camera is active.
@export var override_camera_collision: bool = false
## Camera collision state used while the override is active.
@export var camera_collision_enabled_override: bool = true

