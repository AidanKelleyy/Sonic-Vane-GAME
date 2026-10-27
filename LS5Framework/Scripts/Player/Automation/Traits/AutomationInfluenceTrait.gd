@tool
extends Resource
class_name AutomationInfluenceTrait

## Enables this weight resource.
@export var enabled: bool = true
## Channels weighted by this resource. First applicable entry per channel wins.
@export_flags("Steering", "Position", "Speed", "Surface", "Input") var channels: int = 31
## Constant multiplier for the selected channels.
@export_range(0.0, 1.0, 0.01) var weight: float = 1.0
## Enables distance falloff from the route.
@export var distance_falloff: bool = false
## Route distance with full influence.
@export_range(0.0, 1000.0, 0.1, "suffix:m") var full_distance: float = 2.0
## Route distance with zero influence. Must exceed Full Distance.
@export_range(0.01, 1000.0, 0.1, "suffix:m") var zero_distance: float = 8.0
## Fade distance from the physical start endpoint. Closed routes ignore endpoint ramps.
@export_range(0.0, 1000.0, 0.1, "suffix:m") var start_ramp: float = 0.0
## Fade distance from the physical end endpoint.
@export_range(0.0, 1000.0, 0.1, "suffix:m") var end_ramp: float = 0.0
## Normalized progress where influence begins.
@export_range(0.0, 1.0, 0.01) var progress_start: float = 0.0
## Normalized progress where influence ends.
@export_range(0.0, 1.0, 0.01) var progress_end: float = 1.0
## Minimum absolute along-route speed required for influence.
@export_range(0.0, 2000.0, 0.1, "suffix:m/s") var minimum_speed: float = 0.0
## Optional weight curve sampled at normalized canonical progress.
@export var progress_curve: Curve


func get_weight(session: AutomationSession, source: AutomationSplineCore) -> float:
	var fraction: float = session.sample.distance / maxf(source.sampler.length, 0.0001)
	if fraction < progress_start or fraction > progress_end or absf(session.signed_speed) < minimum_speed:
		return 0.0
	var value: float = clampf(weight, 0.0, 1.0)
	if distance_falloff:
		if zero_distance <= full_distance:
			return 0.0
		value *= 1.0 - smoothstep(full_distance, zero_distance, session.sample.spatial_error)
	if not source.sampler.closed:
		if start_ramp > 0.0:
			value *= smoothstep(0.0, start_ramp, session.sample.distance)
		if end_ramp > 0.0:
			value *= smoothstep(0.0, end_ramp, source.sampler.length - session.sample.distance)
	if progress_curve:
		value *= clampf(progress_curve.sample_baked(fraction), 0.0, 1.0)
	return value
