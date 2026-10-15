@tool
extends Resource
class_name FractureImportPhysics

## Mass assigned to each imported fracture body.
@export var piece_mass: float = 4.0
## Material density used for water displacement. Zero disables buoyancy.
@export var piece_density: float = 0.0
## Gravity multiplier used by shared directional gravity physics.
@export var gravity_scale: float = 4.0
## Collision friction assigned to imported pieces.
@export var friction: float = 0.25
## Restitution assigned to imported pieces.
@export var bounce: float = 0.15
## Linear damping assigned to imported pieces.
@export var linear_damp: float = 0.09
## Angular damping assigned to imported pieces.
@export var angular_damp: float = 0.05
## Physics layers occupied by imported fracture pieces.
@export_flags_3d_physics var collision_layer: int = 8
## Physics layers collided with by imported fracture pieces.
@export_flags_3d_physics var collision_mask: int = 5
## Enables native continuous collision detection.
@export var continuous_collision: bool = true
## Enables supplemental collision sweeps for fast fragments.
@export var collision_safety_enabled: bool = true
## Minimum speed requiring supplemental sweeps.
@export var collision_safety_min_speed: float = 35.0
