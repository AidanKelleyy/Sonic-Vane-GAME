extends ActorTargetable3D
class_name PropTarget3D

## Prop owning the shared damage receiver. Empty uses the parent.
@export var prop: PropBody3D

func _ready() -> void:
	if not prop:
		prop = get_parent() as PropBody3D
	set_meta(&"npc_affiliation", &"neutral")
	set_enabled(false)

func _physics_process(delta: float) -> void:
	set_enabled(is_instance_valid(prop) and not prop.is_destroyed and not prop.is_carried() and prop.targeting_allowed)
	physics_tick(delta, true)

func is_prop_target_available(player: Node3D, homing: bool) -> bool:
	if not is_instance_valid(prop):
		return false
	var id: StringName = &"homing" if homing else PlayerPropContact3D.body_attack_id(player)
	if not homing and player.get_current_action_id() in [&"spin_kick", &"uppercut_kick"]:
		id = player.get_current_action_id()
		if id == &"spin_kick" and not player.attached:
			id = &"tornado_kick"
	return prop.accepts_profile(player.get_prop_attack_profile(id))

func on_homing_hit(player: Node, _jump_held: bool) -> bool:
	if not is_instance_valid(prop):
		return false
	var hit: PropHit = PropHit.from_player(player, &"homing")
	hit.position = global_position
	hit.normal = (player.global_position - global_position).normalized()
	prop.receive_prop_hit(hit)
	return true
