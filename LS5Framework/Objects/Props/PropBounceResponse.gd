extends Resource
class_name PropBounceResponse

enum Mode { NONE, BADNIK, RADIAL, DIRECTIONAL }
## Player response applied to this outcome.
@export var mode: Mode = Mode.NONE
## Attack identities accepted by this response. Empty accepts every identity.
@export var attacks: Array[StringName] = []
## Outcomes accepted by this response.
@export_flags("Rejected", "Damaged", "Broken", "Destroyed") var outcomes: int = 14
## Gravity-up rebound speed.
@export var speed: float = 16.0
## Maximum rebound speed.
@export var maximum_speed: float = 160.0
## Fraction of gravity-planar player velocity retained.
@export var lateral_retention: float = 1.0
## Local launch direction for directional responses.
@export var direction: Vector3 = Vector3.UP
## Speed multiplier while jump is held.
@export var jump_held_multiplier: float = 1.0
## Refreshes airborne abilities after the response.
@export var refresh_abilities: bool = false
## Restricts rebounds to contacts made while airborne.
@export var airborne_only: bool = true
## Ends an active Bounce or Stomp on contact.
@export var end_bounce_stomp: bool = true
## Fraction of target velocity added to the rebound.
@export var inherit_target_velocity: float = 0.0

func matches(hit: PropHit, outcome: int) -> bool:
	return bool(outcomes & outcome) and (attacks.is_empty() or hit.profile.attack_id in attacks)
