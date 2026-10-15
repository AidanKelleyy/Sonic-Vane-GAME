extends Resource
class_name PropHitRule

## Categories accepted by this rule. Zero accepts none.
@export_flags("Traversal", "Command", "Physical Impact", "Scripted") var categories: int = 3
## Required attack identities. Empty accepts all identities in the categories.
@export var allowed_attacks: Array[StringName] = []
## Attack identities rejected by this rule.
@export var blocked_attacks: Array[StringName] = []
## Tags that must all be present on the attack profile.
@export var required_tags: Array[StringName] = []
## Minimum relative closing speed along the contact normal.
@export var minimum_closing_speed: float = 0.0
## Multiplier applied to incoming durability damage.
@export var damage_multiplier: float = 1.0
## Removes all remaining durability on an accepted hit.
@export var instant_destroy: bool = false

func accepts_profile(profile: PropAttackProfile) -> bool:
	if not profile or not (categories & profile.categories):
		return false
	if profile.attack_id in blocked_attacks:
		return false
	if not allowed_attacks.is_empty() and not profile.attack_id in allowed_attacks:
		return false
	for tag: StringName in required_tags:
		if not tag in profile.tags:
			return false
	return true

func accepts(hit: PropHit, target_velocity: Vector3) -> bool:
	if not accepts_profile(hit.profile):
		return false
	return maxf(-(hit.velocity - target_velocity).dot(hit.normal), 0.0) >= minimum_closing_speed
