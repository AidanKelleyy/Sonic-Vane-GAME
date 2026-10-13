extends RefCounted
class_name PlayerCharacterAttributes

var _owner: Node
var _profile: CharacterSettingsProfile
var _bindings: Dictionary = {}
var _definitions: Dictionary = {}
var _baselines: Dictionary = {}
var _values: Dictionary = {}

func _init(pawn: Node) -> void:
	_owner = pawn

func initialize() -> void:
	_profile = _owner.character_settings_profile
	if not _profile:
		return
	if _owner.character_visual_profile:
		_owner.character_visual_profile = _owner.character_visual_profile.duplicate() as PlayerCharacterVisualProfile
	for id: StringName in _profile.attribute_ids:
		var binding: Dictionary = CharacterAttributeResolver.resolve_target(_owner, id)
		var info: Dictionary = {}
		var baseline: Variant = true
		if id != CharacterAttributeResolver.OUTLINE_ID and id != CharacterAttributeResolver.UEKAWA_ID:
			var target: Object = binding.get("target", null)
			if not target:
				continue
			info = CharacterAttributeResolver.property_info(target, binding.property)
			if info.is_empty():
				continue
			baseline = target.get(binding.property)
		var definition: Dictionary = CharacterAttributeResolver.describe(_profile, id, info, baseline)
		if definition.is_empty():
			push_warning("Unavailable character attribute: %s" % id)
			continue
		_bindings[id] = binding
		_definitions[id] = definition
		_baselines[id] = baseline
	if not CharacterProfileManager.character_profile_changed.is_connected(_on_profile_changed):
		CharacterProfileManager.character_profile_changed.connect(_on_profile_changed)
	apply(CharacterProfileManager.get_effective_settings(_profile) if _owner._network_is_local_authority() else {})

func dispose() -> void:
	if CharacterProfileManager.character_profile_changed.is_connected(_on_profile_changed):
		CharacterProfileManager.character_profile_changed.disconnect(_on_profile_changed)
	_bindings.clear()
	_definitions.clear()
	_baselines.clear()
	_values.clear()
	_owner = null
	_profile = null

func snapshot() -> Dictionary:
	return _values.duplicate(true)

func shader_enabled(id: StringName) -> bool:
	return bool(_values.get(id, true))

func apply(settings: Dictionary) -> void:
	var racing: bool = _owner._network_is_local_authority() and (_owner.race_active or _owner.race_in_countdown or _owner.race_session_joined)
	var next_values: Dictionary = {}
	for id: StringName in _definitions:
		var definition: Dictionary = _definitions[id]
		var proposed: Variant = settings.get(id, definition.default)
		if racing and not CharacterAttributeResolver.is_visual(id):
			proposed = _values.get(id, definition.default)
		var checked: Dictionary = CharacterAttributeResolver.validate(definition, proposed)
		var value: Variant = checked.value if not checked.is_empty() else definition.default
		next_values[id] = value
	if next_values == _values:
		return
	_values = next_values
	for id: StringName in _definitions:
		var binding: Dictionary = _bindings[id]
		var target: Object = binding.get("target", null)
		if target:
			target.set(binding.property, _baselines[id])
			target.set(binding.property, _values[id])
	var primary: Color = _owner._character_primary_color
	var secondary: Color = _owner._character_secondary_color
	_owner._apply_character_visual_profile()
	if _owner._character_colors_configured:
		_owner._character_primary_color = primary
		_owner._character_secondary_color = secondary
		_owner.character_tint_enabled = _owner._character_colors_enabled and (not _owner.character_visual_profile or _owner.character_visual_profile.tint_enabled)
	_owner._apply_action_node_settings()
	for id: StringName in _bindings:
		if not String(id).begins_with("ability."):
			continue
		var binding: Dictionary = _bindings[id]
		var info: Dictionary = CharacterAttributeResolver.property_info(_owner, binding.property)
		if not info.is_empty() and not (int(info.usage) & PROPERTY_USAGE_EDITOR):
			_owner.set(binding.property, _values[id])
	_owner._apply_character_tint()

func _on_profile_changed(key: String) -> void:
	if not _profile or key != _profile.get_profile_key() or not _owner._network_is_local_authority() or _owner._is_buddy_actor():
		return
	apply(CharacterProfileManager.get_effective_settings(_profile))
	_owner._publish_character_attributes()
