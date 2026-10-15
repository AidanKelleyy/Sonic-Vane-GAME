extends Resource
class_name PropBuoyancySample

## Local center of this displaced volume sample.
@export var position: Vector3 = Vector3.ZERO
## Fractional weight of this sample, normalized across all samples.
@export_range(0.001, 100.0, 0.01) var weight: float = 1.0
## Radius used to smooth partial submersion at water boundaries.
@export var radius: float = 0.25
