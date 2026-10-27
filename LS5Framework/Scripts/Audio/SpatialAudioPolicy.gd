extends Node
class_name SpatialAudioPolicy

const WORLD: SpatialAudioProfile = preload("res://LS5Framework/Resources/Audio/WorldEffects.tres")
const VOICE: SpatialAudioProfile = preload("res://LS5Framework/Resources/Audio/Voices.tres")
const LAUNCH: SpatialAudioProfile = preload("res://LS5Framework/Resources/Audio/LaunchEffects.tres")
const AMBIENCE: SpatialAudioProfile = preload("res://LS5Framework/Resources/Audio/Ambience.tres")
const DETAILS: SpatialAudioProfile = preload("res://LS5Framework/Resources/Audio/MovementDetails.tres")

var _sources: Dictionary = {}
var _refresh_elapsed: float = 0.0


static func get_profile(player: AudioStreamPlayer3D) -> SpatialAudioProfile:
	var override: Variant = player.get_meta(&"spatial_audio_profile") if player.has_meta(&"spatial_audio_profile") else null
	if override is SpatialAudioProfile:
		return override
	var source_name: String = String(player.name).to_lower()
	if player.bus == &"Voice" or "dialogue" in source_name or "voice" in source_name:
		return VOICE
	if player.bus in [&"Rain", &"EnemyIdle"] or "idle" in source_name or "ambient" in source_name:
		return AMBIENCE
	if "footstep" in source_name or "slide" in source_name or "rollloop" in source_name:
		return DETAILS
	if player.stream and player.stream.resource_path.ends_with("/DashPanel.wav"):
		return LAUNCH
	var ancestor: Node = player.get_parent()
	while ancestor:
		var script: Script = ancestor.get_script() as Script
		if script and ("/DashPanels/" in script.resource_path or "/Spring/" in script.resource_path or "/Springs/" in script.resource_path or "/DashRing" in script.resource_path or "/Ramps/" in script.resource_path or script.resource_path.ends_with("/RailBooster.gd")):
			return LAUNCH
		ancestor = ancestor.get_parent()
	return WORLD


static func apply(player: AudioStreamPlayer3D, profile: SpatialAudioProfile = null) -> void:
	if not is_instance_valid(player):
		return
	if not profile:
		profile = get_profile(player)
	if player.unit_size < profile.minimum_unit_size:
		player.unit_size = profile.minimum_unit_size
	if player.max_distance > 0.0 and player.max_distance < profile.minimum_max_distance:
		player.max_distance = profile.minimum_max_distance
	if player.max_db > profile.maximum_level_db:
		player.max_db = profile.maximum_level_db
	if player.volume_db > profile.maximum_gain_db:
		player.volume_db = profile.maximum_gain_db


static func get_listener_position(context: Node3D) -> Vector3:
	var viewport: Viewport = context.get_viewport()
	var listener: AudioListener3D = viewport.get_audio_listener_3d()
	if listener:
		return listener.global_position
	var camera: Camera3D = viewport.get_camera_3d()
	return camera.global_position if camera else context.global_position


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 1000
	get_tree().node_added.connect(_on_node_added)
	_register_subtree(get_tree().root)


func _register_subtree(node: Node) -> void:
	_on_node_added(node)
	for child: Node in node.get_children():
		_register_subtree(child)


func _on_node_added(node: Node) -> void:
	if not node is AudioStreamPlayer3D:
		return
	var player: AudioStreamPlayer3D = node as AudioStreamPlayer3D
	_sources[player.get_instance_id()] = {"source": weakref(player), "profile": get_profile(player)}
	apply(player)
	if not player.is_node_ready():
		player.ready.connect(_on_source_ready.bind(weakref(player)), CONNECT_ONE_SHOT)


func _on_source_ready(reference: WeakRef) -> void:
	var player: AudioStreamPlayer3D = reference.get_ref() as AudioStreamPlayer3D
	if player:
		apply(player)


func _physics_process(delta: float) -> void:
	_refresh_elapsed += delta
	var refresh: bool = _refresh_elapsed >= 0.25
	if refresh:
		_refresh_elapsed = 0.0
	for id: int in _sources.keys():
		var entry: Dictionary = _sources[id]
		var player: AudioStreamPlayer3D = (entry["source"] as WeakRef).get_ref() as AudioStreamPlayer3D
		if not player:
			_sources.erase(id)
			continue
		if not player.is_inside_tree():
			_sources.erase(id)
			continue
		var profile: SpatialAudioProfile = entry["profile"]
		if refresh:
			profile = get_profile(player)
			entry["profile"] = profile
			apply(player, profile)
		else:
			if player.max_db > profile.maximum_level_db:
				player.max_db = profile.maximum_level_db
			if player.volume_db > profile.maximum_gain_db:
				player.volume_db = profile.maximum_gain_db
