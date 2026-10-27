@tool
extends AutomationPositionTrait
class_name AutomationRibbonTrait

enum PlaneFrameMode {
	PATH_FRAME,
	GRAVITY_RIBBON,
	PLAYER_RIBBON,
	FIXED_PATH_AXIS,
}

enum TransitionEase {
	LINEAR,
	SMOOTHSTEP,
	SMOOTHERSTEP,
}

enum SurfaceTraversalMode {
	PROJECT_PATH_ON_SURFACE,
	RIBBON_SURFACE_TANGENT,
}

@export_group("Transitions")
## Path distance used to blend from free 3D movement into strict 2.5D movement at the start.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m") var entry_blend_distance: float = 12.0
## Path distance used to blend from strict 2.5D movement back to free 3D movement at the end.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m") var exit_blend_distance: float = 12.0
## Easing function applied to entry and exit adherence.
@export var transition_ease: TransitionEase = TransitionEase.SMOOTHERSTEP
## Applies the plane constraint while airborne so jumps remain inside the 2.5D ribbon.
@export var constrain_airborne: bool = true
## Applies the plane constraint during homing, jump dash, and other normal external movement states.
@export var constrain_special_moves: bool = true

## Uses cubic positions after connected branch selection.
@export var cubic_path_sampling: bool = true
## Local curve distance used to smooth the canonical tangent.
@export_range(0.01, 100.0, 0.01) var tangent_lookahead: float = 0.5

@export_group("Plane Frame")
## Selects how the forbidden sideways axis is generated along the path.
@export var plane_frame_mode: PlaneFrameMode = PlaneFrameMode.PATH_FRAME
## Reverses the generated sideways axis without changing path direction.
@export var reverse_plane_normal: bool = false
## Uses the previous valid path frame when a vertical or degenerate segment cannot produce one.
@export var preserve_frame_through_degenerate_segments: bool = true

@export_group("Terrain Traversal Adjustment")
## Adapts movement orientation to attached terrain without changing spline progress.
@export var surface_frame_enabled: bool = true
## Selects whether terrain tangent follows a path projection or the surface direction inside the ribbon.
@export var surface_traversal_mode: SurfaceTraversalMode = SurfaceTraversalMode.RIBBON_SURFACE_TANGENT
## Keeps the authored sideways axis stable while terrain changes movement up and forward.
@export var surface_frame_preserve_ribbon_normal: bool = true
## Blend from the authored curve frame to the attached surface frame.
@export_range(0.0, 1.0, 0.01) var surface_frame_influence: float = 1.0
## Uses grounded travel direction to refine the surface tangent when moving fast enough.
@export var surface_frame_uses_velocity: bool = false
## Minimum grounded speed required before travel direction refines the surface frame.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m/s") var surface_frame_min_speed: float = 2.0
## Grounded tangent alignment strength used while terrain traversal adjustment is active.
@export_range(0.0, 200.0, 0.1, "or_greater") var terrain_tangent_alignment_strength: float = 6.0

@export_group("Adaptive Centerline")
## Captures the player's depth relative to the curve when the spline first activates.
@export var capture_entry_depth_offset: bool = true
## Fades captured entry depth to the authored centerline as endpoint adherence increases.
@export var captured_depth_transition_enabled: bool = true
## Lets unmarked attached terrain continuously move the centerline. Disable for strict authored depth.
@export var follow_unanchored_surface_depth: bool = false
## Lets the constrained plane follow bounded depth changes caused by attached surface geometry.
@export var adaptive_centerline_enabled: bool = true
## Limits adaptive centerline movement to grounded or otherwise attached motion.
@export var adaptive_centerline_grounded_only: bool = true
## Response speed used when the centerline follows detected surface depth. Zero follows immediately.
@export_range(0.0, 200.0, 0.1, "or_greater") var adaptive_centerline_strength: float = 20.0
## Maximum centerline movement speed. Zero removes the limit.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m/s") var adaptive_centerline_max_speed: float = 12.0
## Maximum absolute depth offset the adaptive centerline may keep from the authored curve. Zero removes the limit.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m") var adaptive_centerline_max_offset: float = 4.0
## Minimum depth difference required before the centerline follows the surface.
@export_range(0.0, 1.0, 0.001, "or_greater", "suffix:m") var adaptive_centerline_deadzone: float = 0.02

@export_group("Terrain Piece Anchors")
## Uses metadata-marked attached collision pieces as stable centerline depth targets.
@export var terrain_piece_anchors_enabled: bool = false
## Metadata key placed on a collision node or one of its parents. True uses node origin; Vector3 uses a local anchor; a number supplies a direct plane offset.
@export var terrain_piece_anchor_metadata: StringName = &"automation_25d_centerline_anchor"
## Maximum number of collider parents searched for terrain-piece anchor metadata.
@export_range(0, 32, 1) var terrain_piece_anchor_parent_search: int = 8

@export_group("Depth Offset Splines")
## Allows active 2.5D depth-profile splines to supply deterministic centerline offsets.
@export var depth_offset_splines_enabled: bool = true

@export_group("Position Constraint")
## Resolves final depth error at full adherence within collision-safe travel.
@export var strict_position_lock: bool = true
## Reapplies depth correction after collision movement.
@export var post_slide_constraint_pass_enabled: bool = true
## Response speed used to pull position toward the ribbon during transitions. Zero follows transition weight directly.
@export_range(0.0, 200.0, 0.1, "or_greater") var position_lock_strength: float = 12.0
## Maximum sideways correction speed during transitions. Zero removes the limit.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m/s") var max_position_correction_speed: float = 80.0
## Sideways error below this distance is ignored outside the strict core.
@export_range(0.0, 1.0, 0.001, "or_greater", "suffix:m") var position_lock_deadzone: float = 0.005

@export_group("Velocity Constraint")
## Removes all sideways velocity at full adherence.
@export var strict_velocity_lock: bool = true
## Prevents passive steering-angle speed loss while the 2.5D spline is active.
@export var disable_turning_slowdown: bool = true
## Response speed used to remove sideways velocity during transitions. Zero follows transition weight directly.
@export_range(0.0, 200.0, 0.1, "or_greater") var velocity_lock_strength: float = 18.0
## Restores a fraction of speed lost when sideways velocity is removed. Zero avoids converting turn arcs into forward speed.
@export_range(0.0, 1.0, 0.01) var sideways_removal_speed_preservation: float = 0.0



func _init() -> void:
	mode = Mode.RIBBON
	airborne = true


func applies(attached: bool) -> bool:
	return enabled and (grounded if attached else airborne and constrain_airborne)


func _validate_property(property: Dictionary) -> void:
	if property.name in ["mode", "free_radius", "spring_strength", "damping", "max_acceleration", "correction_speed", "attraction_acceleration", "attraction_per_speed", "attraction_speed_scale", "attraction_radius"]:
		property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR
