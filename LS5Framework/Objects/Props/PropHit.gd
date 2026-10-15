extends RefCounted
class_name PropHit

var profile: PropAttackProfile
var source: Node3D
var instigator: Node3D
var activation: int = 0
var position: Vector3 = Vector3.ZERO
var normal: Vector3 = Vector3.UP
var velocity: Vector3 = Vector3.ZERO
var up: Vector3 = Vector3.UP
var impulse: Vector3 = Vector3.ZERO
var was_airborne: bool = false

static func from_player(player: Node3D, id: StringName) -> PropHit:
	var hit: PropHit = PropHit.new()
	hit.source = player
	hit.instigator = player
	hit.profile = PropAttackProfile.default_for(id)
	if player.has_method("get_prop_attack_profile"):
		hit.profile = player.call("get_prop_attack_profile", id)
	hit.activation = int(player.get_meta(StringName("prop_activation_" + String(id)), 0))
	hit.position = player.global_position
	hit.velocity = player.get("velocity")
	hit.was_airborne = not bool(player.get("attached"))
	hit.up = player.call("get_gravity_up") if player.has_method("get_gravity_up") else Vector3.UP
	if hit.profile:
		hit.impulse = hit.velocity.normalized() * hit.profile.impulse
	return hit
