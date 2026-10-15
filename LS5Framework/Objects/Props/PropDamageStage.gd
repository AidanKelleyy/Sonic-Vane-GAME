extends Resource
class_name PropDamageStage

## Remaining durability at or below which this usable stage is entered.
@export var durability_threshold: float = 0.5
## Scene attached as the retained usable representation. Empty keeps the current representation.
@export var visual_scene: PackedScene
## Replacement compound collision parts. Empty keeps the current shapes.
@export var collision_parts: Array[PropCollisionPart] = []
## Emits fractures on entering this stage.
@export var emit_fractures: bool = false
## Allows carrying while this stage is active.
@export var carry_allowed: bool = true
## Allows target registration while this stage is active.
@export var targeting_allowed: bool = true
## Replacement mass. Zero preserves the current mass.
@export var mass_override: float = 0.0
## Replacement effective displacement. Zero preserves the current volume.
@export var volume_override: float = 0.0
