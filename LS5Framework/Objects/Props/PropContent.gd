extends Resource
class_name PropContent

## Scene spawned once on destruction.
@export var scene: PackedScene
## Number of instances produced by this entry.
@export_range(0, 64, 1) var count: int = 1
## Chance that this entry is emitted.
@export_range(0.0, 1.0, 0.01) var probability: float = 1.0
## Local spawn offset relative to the prop.
@export var offset: Vector3 = Vector3.ZERO
## Fraction of source linear velocity assigned to rigid contents.
@export var inherit_velocity: float = 1.0
