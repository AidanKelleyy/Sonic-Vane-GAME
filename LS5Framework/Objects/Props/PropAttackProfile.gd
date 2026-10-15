extends Resource
class_name PropAttackProfile

enum Category { NONE = 0, TRAVERSAL = 1, COMMAND = 2, IMPACT = 4, SCRIPTED = 8 }

## Stable identity of the damaging phase.
@export var attack_id: StringName = &""
## Interaction categories carried by this attack.
@export_flags("Traversal", "Command", "Physical Impact", "Scripted") var categories: int = Category.TRAVERSAL
## Tags used by prop acceptance rules.
@export var tags: Array[StringName] = []
## Durability removed by an accepted contact.
@export_range(0.0, 1000.0, 0.1, "or_greater") var damage: float = 1.0
## Impulse applied to movable targets.
@export var impulse: float = 30.0
## Delay between repeated hits. Zero permits one hit per activation.
@export_range(0.0, 10.0, 0.01) var repeat_interval: float = 0.0

static func make(id: StringName, category: int = Category.TRAVERSAL) -> PropAttackProfile:
	var profile: PropAttackProfile = PropAttackProfile.new()
	profile.attack_id = id
	profile.categories = category
	return profile

static func default_for(id: StringName) -> PropAttackProfile:
	if id in [&"spin_kick", &"tornado_kick", &"uppercut_kick", &"bounce", &"stomp", &"bounce_rebound"]:
		var profile: PropAttackProfile = make(id, Category.COMMAND)
		if id in [&"spin_kick", &"tornado_kick", &"uppercut_kick"]:
			profile.impulse = 300.0
		return profile
	if id in [&"jump", &"jump_dash", &"homing", &"roll", &"spindash", &"lightspeed_dash", &"air_uncurl", &"enemy_chain"]:
		return make(id)
	return null
