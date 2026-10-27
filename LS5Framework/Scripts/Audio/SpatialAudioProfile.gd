extends Resource
class_name SpatialAudioProfile

## Minimum attenuation scale in world units. The standard player capsule is approximately two units tall.
@export_range(0.1, 1000.0, 0.1) var minimum_unit_size: float = 90.0
## Minimum positive audible cutoff in world units. Sources authored with an unlimited cutoff retain it.
@export_range(0.0, 5000.0, 1.0) var minimum_max_distance: float = 320.0
## Maximum source level after distance attenuation, before audio bus volume.
@export_range(-40.0, 0.0, 0.1, "suffix:dB") var maximum_level_db: float = -6.0
## Maximum pre-attenuation gain. Lower authored gains and fade-outs remain unchanged.
@export_range(-40.0, 12.0, 0.1, "suffix:dB") var maximum_gain_db: float = 0.0
