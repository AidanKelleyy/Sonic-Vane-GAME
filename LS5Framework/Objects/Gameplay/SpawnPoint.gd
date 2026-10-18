@tool
extends Node3D
class_name SpawnPoint

const EDITOR_PREVIEW_PATH: String = "res://LS5Framework/Objects/Reference/Sonic_NeoAdventure_REF.glb"

@export_group("Editor Preview")
## Shows the reference character in the editor without loading it during gameplay.
@export var show_editor_preview: bool = true:
	set(value):
		show_editor_preview = value
		_update_editor_preview()
## Local preview offset from the player's collision-centred spawn origin.
@export var editor_preview_offset: Vector3 = Vector3(0.0, -1.0, 0.0):
	set(value):
		editor_preview_offset = value
		_update_editor_preview()

@export_group("Downwarp")
@export var downwarp_enabled: bool = true
@export var downwarp_distance: float = 150.0
@export var downwarp_offset: float = 0.05
@export var downwarp_collision_mask: int = 0xFFFFFFFF

## Unsaved reference model used to preview spawn placement and facing in the editor.
var _editor_preview: Node3D = null


func _ready() -> void:
	_update_editor_preview()


func _update_editor_preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if not show_editor_preview:
		if is_instance_valid(_editor_preview):
			remove_child(_editor_preview)
			_editor_preview.queue_free()
			_editor_preview = null
		return
	if not is_instance_valid(_editor_preview):
		var scene: PackedScene = load(EDITOR_PREVIEW_PATH) as PackedScene
		if not scene:
			return
		_editor_preview = scene.instantiate() as Node3D
		if not _editor_preview:
			return
		_editor_preview.name = "SpawnCharacterPreview"
		_editor_preview.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(_editor_preview, false, Node.INTERNAL_MODE_BACK)
		for node: Node in _editor_preview.find_children("*", "GeometryInstance3D", true, false):
			var geometry: GeometryInstance3D = node as GeometryInstance3D
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			geometry.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_editor_preview.position = editor_preview_offset
