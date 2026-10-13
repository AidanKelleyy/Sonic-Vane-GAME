extends RefCounted
class_name CharacterAttributeResolver

const OUTLINE_ID: StringName = &"visual.outline.enabled"
const UEKAWA_ID: StringName = &"visual.uekawa.enabled"
const EDITABLE_TYPES: Array[int] = [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_COLOR]

static func is_visual(id: StringName) -> bool:
	return String(id).begins_with("visual.")

static func property_info(target: Object, property: StringName) -> Dictionary:
	for info: Dictionary in target.get_property_list():
		if StringName(info.name) == property and int(info.usage) & PROPERTY_USAGE_STORAGE:
			return info.duplicate(true)
	return {}

static func resolve_target(pawn: Node, id: StringName) -> Dictionary:
	var parts: PackedStringArray = String(id).split(".")
	if parts.size() == 2 and parts[0] == "pawn":
		return {"target": pawn, "property": StringName(parts[1])}
	if parts.size() == 2 and parts[0] == "visual" and "character_visual_profile" in pawn:
		return {"target": pawn.get("character_visual_profile"), "property": StringName(parts[1])}
	if parts.size() == 3 and parts[0] == "ability":
		var target: Node = find_ability(pawn.get_node_or_null("Abilities"), StringName(parts[1]))
		return {"target": target, "property": StringName(parts[2])}
	return {}

static func find_ability(root: Node, id: StringName) -> Node:
	if not root:
		return null
	if "action_id" in root and StringName(root.get("action_id")) == id:
		return root
	if "action_id" in root and not root.get("action_id") and root.get_script() and script_ability_id(root.get_script()) == id:
		return root
	for child: Node in root.get_children():
		var found: Node = find_ability(child, id)
		if found:
			return found
	return null

static func script_ability_id(script: Script) -> StringName:
	return StringName(script.resource_path.get_file().get_basename().trim_suffix("_action").trim_suffix("_ability"))

static func script_default(script: Script, property: StringName) -> Variant:
	var cursor: Script = script
	while cursor:
		var value: Variant = cursor.get_property_default_value(property)
		if value != null:
			return value
		cursor = cursor.get_base_script()
	return null

static func describe(profile: CharacterSettingsProfile, id: StringName, info: Dictionary, baseline: Variant) -> Dictionary:
	if not profile or not profile.attribute_ids.has(id):
		return {}
	if id == OUTLINE_ID or id == UEKAWA_ID:
		info = {"type": TYPE_BOOL, "hint": PROPERTY_HINT_NONE, "hint_string": ""}
		baseline = true
	elif String(id).begins_with("pawn.") and not (int(info.get("usage", 0)) & PROPERTY_USAGE_EDITOR):
		return {}
	if info.is_empty() or not EDITABLE_TYPES.has(int(info.get("type", TYPE_NIL))):
		return {}
	var definition: Dictionary = {"id": id, "type": int(info.type), "default": baseline,
		"label": String(id).get_slice(".", String(id).get_slice_count(".") - 1).capitalize(),
		"description": "", "category": "Visual Effects" if is_visual(id) else "Physics",
		"min": -100000.0, "max": 100000.0, "step": 1.0 if int(info.type) == TYPE_INT else 0.1,
		"suffix": "", "hint": int(info.get("hint", PROPERTY_HINT_NONE)), "hint_string": String(info.get("hint_string", ""))}
	if id == OUTLINE_ID:
		definition.label = "Outline Shader"
		definition.description = "Enable the character's existing outline material passes."
	elif id == UEKAWA_ID:
		definition.label = "Uekawa Shader"
		definition.description = "Enable the character's existing Uekawa rim-light material passes."
	if int(definition.hint) == PROPERTY_HINT_RANGE:
		var range_parts: PackedStringArray = String(definition.hint_string).split(",")
		if range_parts.size() >= 2:
			definition.min = float(range_parts[0])
			definition.max = float(range_parts[1])
		if range_parts.size() >= 3 and range_parts[2].is_valid_float():
			definition.step = float(range_parts[2])
	var custom: Variant = profile.attribute_definitions.get(id, {})
	if custom is Dictionary:
		for key: String in ["label", "description", "category", "min", "max", "step", "suffix", "default"]:
			if custom.has(key):
				definition[key] = custom[key]
	var defaults: Dictionary = profile.normalize_attribute_settings(profile.default_settings)
	if defaults.has(id):
		definition.default = defaults[id]
	var checked_default: Dictionary = validate(definition, definition.default)
	definition.default = checked_default.value if not checked_default.is_empty() else baseline
	return definition

static func validate(definition: Dictionary, value: Variant) -> Dictionary:
	if definition.is_empty():
		return {}
	var type: int = int(definition.type)
	if type == TYPE_BOOL:
		return {"value": value} if value is bool else {}
	if type == TYPE_COLOR:
		if not value is Color or not is_finite(value.r) or not is_finite(value.g) or not is_finite(value.b) or not is_finite(value.a):
			return {}
		return {"value": Color(clampf(value.r, 0.0, 1.0), clampf(value.g, 0.0, 1.0), clampf(value.b, 0.0, 1.0), clampf(value.a, 0.0, 1.0))}
	if type == TYPE_INT or type == TYPE_FLOAT:
		if not (value is int or value is float) or not is_finite(float(value)):
			return {}
		var number: float = clampf(float(value), float(definition.min), float(definition.max))
		if type == TYPE_INT and int(definition.hint) == PROPERTY_HINT_ENUM:
			var permitted: bool = false
			var enum_value: int = 0
			for option: String in String(definition.hint_string).split(","):
				if option.contains(":"):
					enum_value = int(option.get_slice(":", 1))
				permitted = permitted or int(number) == enum_value
				enum_value += 1
			if not permitted:
				return {}
		return {"value": int(number) if type == TYPE_INT else number}
	return {}

static func scene_definitions(profile: CharacterSettingsProfile, scene: PackedScene) -> Dictionary:
	var definitions: Dictionary = {}
	if not profile:
		return definitions
	var nodes: Array[Dictionary] = []
	if scene:
		collect_scene_nodes(scene.get_state(), nodes)
	for id: StringName in profile.attribute_ids:
		var parts: PackedStringArray = String(id).split(".")
		var info: Dictionary = {}
		var baseline: Variant = null
		if id == OUTLINE_ID or id == UEKAWA_ID:
			definitions[id] = describe(profile, id, {}, true)
			continue
		for node: Dictionary in nodes:
			var values: Dictionary = node.values
			var script: Script = values.get("script", null) as Script
			if not script:
				continue
			var property: StringName = &""
			if parts.size() == 2 and parts[0] == "pawn" and String(node.path) == ".":
				property = StringName(parts[1])
			elif parts.size() == 3 and parts[0] == "ability":
				var action_value: Variant = values.get(&"action_id", script_default(script, &"action_id"))
				var action_id: StringName = StringName(action_value) if action_value is String or action_value is StringName else &""
				if action_id == &"":
					action_id = script_ability_id(script)
				if action_id == StringName(parts[1]):
					property = StringName(parts[2])
			elif parts.size() == 2 and parts[0] == "visual" and String(node.path) == ".":
				var visual: Resource = values.get(&"character_visual_profile", null) as Resource
				if visual:
					info = property_info(visual, StringName(parts[1]))
					baseline = visual.get(StringName(parts[1])) if not info.is_empty() else null
				break
			if property == &"":
				continue
			var cursor: Script = script
			while cursor and info.is_empty():
				for candidate: Dictionary in cursor.get_script_property_list():
					if StringName(candidate.name) == property and int(candidate.usage) & PROPERTY_USAGE_STORAGE:
						info = candidate
						break
				cursor = cursor.get_base_script()
			baseline = values.get(property, script_default(script, property))
			break
		var definition: Dictionary = describe(profile, id, info, baseline)
		if not definition.is_empty():
			definitions[id] = definition
	return definitions

static func collect_scene_nodes(state: SceneState, nodes: Array[Dictionary], prefix: String = "") -> void:
	if not state:
		return
	var base: SceneState = state.get_base_scene_state()
	if base:
		collect_scene_nodes(base, nodes, prefix)
	for index: int in range(state.get_node_count()):
		var path: String = String(state.get_node_path(index))
		path = prefix if path == "." and not prefix.is_empty() else (prefix + "/" + path if not prefix.is_empty() else path)
		var instance: PackedScene = state.get_node_instance(index)
		if instance:
			collect_scene_nodes(instance.get_state(), nodes, path)
		var values: Dictionary = {}
		for property_index: int in range(state.get_node_property_count(index)):
			values[state.get_node_property_name(index, property_index)] = state.get_node_property_value(index, property_index)
		var merged: bool = false
		for node: Dictionary in nodes:
			if String(node.path) == path:
				node.values.merge(values, true)
				merged = true
				break
		if not merged:
			nodes.append({"path": path, "values": values})
