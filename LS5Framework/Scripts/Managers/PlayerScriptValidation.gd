extends RefCounted

const MANIFEST_PATH: String = "res://LS5Framework/Resources/Diagnostics/PlayerStartupDependencies.json"

static func read_manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not parsed is Dictionary or int(parsed.get("version", 0)) != 1:
		return {}
	if not parsed.get("required_resources") is Array or not parsed.get("player_scripts") is Array:
		return {}
	if parsed.required_resources.is_empty() or parsed.player_scripts.is_empty():
		return {}
	for path: Variant in parsed.player_scripts:
		if not path is String or not path.begins_with("res://") or not path.ends_with(".gd"):
			return {}
	for entry: Variant in parsed.required_resources:
		if not entry is Dictionary or not entry.get("path") is String or not String(entry.path).begins_with("res://") or not entry.get("owners") is Array:
			return {}
		for owner: Variant in entry.owners:
			if not owner is Dictionary or not owner.get("path") is String or not owner.get("kind") is String:
				return {}
	return parsed

static func inspect_resources(manifest: Dictionary) -> Dictionary:
	var failed: Dictionary = {}
	if manifest.is_empty():
		failed[MANIFEST_PATH] = "The startup dependency manifest is missing or invalid. Rebuild the base game."
		return failed
	for entry: Dictionary in manifest.get("required_resources", []):
		var path: String = String(entry.get("path", ""))
		if path.is_empty() or (ResourceLoader.exists(path) or FileAccess.file_exists(path)):
			continue
		var owners: PackedStringArray = []
		for owner: Dictionary in entry.get("owners", []):
			owners.append("%s (%s)" % [owner.get("path", ""), owner.get("kind", "Dependency")])
		failed[path] = "Required before content packs mount. Referenced by: " + ", ".join(owners)
	return failed

static func inspect_scripts(manifest: Dictionary) -> Dictionary:
	var failed: Dictionary = {}
	for path: String in manifest.get("player_scripts", []):
		var script: Script = ResourceLoader.load(path, "Script") as Script
		if not script or not script.can_instantiate():
			failed[path] = "Player script could not be loaded or instantiated. Check its class references and preloaded resources."
	return failed

static func inspect_scene(packed: PackedScene, scene_path: String) -> Dictionary:
	var failed: Dictionary = {}
	var queue: Array[SceneState] = [packed.get_state()]
	var seen: Dictionary = {}
	var root_script: Script = null
	var root_resolved: bool = false
	while not queue.is_empty():
		var state: SceneState = queue.pop_back()
		if not state or seen.has(state.get_instance_id()):
			continue
		seen[state.get_instance_id()] = true
		var base: SceneState = state.get_base_scene_state()
		if base:
			queue.append(base)
		for index: int in range(state.get_node_count()):
			var instance: PackedScene = state.get_node_instance(index)
			if instance:
				queue.push_front(instance.get_state())
			for property_index: int in range(state.get_node_property_count(index)):
				if state.get_node_property_name(index, property_index) != &"script":
					continue
				var script: Script = state.get_node_property_value(index, property_index) as Script
				if state.get_node_path(index) == NodePath(".") and not root_resolved:
					root_script = script
					root_resolved = true
				if script and not script.can_instantiate():
					failed[script.resource_path if not script.resource_path.is_empty() else scene_path] = "Invalid script reference on %s in %s." % [state.get_node_path(index), scene_path]
	if not root_script or not root_script.can_instantiate() or not _script_has_method(root_script, &"_network_initialize_spawn_state"):
		failed[scene_path] = "The character root has no valid player controller script. Its inherited class or dependencies may have failed to load."
	return failed

static func inspect_instance(player: Node, scene_path: String) -> Dictionary:
	var script: Script = player.get_script() as Script
	if not script or not script.can_instantiate() or not player.has_method("_network_initialize_spawn_state"):
		return {scene_path: "The instantiated character root is missing its player controller script or spawn interface."}
	return {}

static func _script_has_method(script: Script, method: StringName) -> bool:
	while script:
		for entry: Dictionary in script.get_script_method_list():
			if StringName(entry.get("name", "")) == method:
				return true
		script = script.get_base_script()
	return false
