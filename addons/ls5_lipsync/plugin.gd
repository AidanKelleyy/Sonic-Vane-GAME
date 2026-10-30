@tool
extends EditorPlugin

## Lip Sync workspace retained independently of the edited scene.
var _screen: Control


func _enter_tree() -> void:
	if not main_screen_changed.is_connected(_on_main_screen_changed):
		main_screen_changed.connect(_on_main_screen_changed)


func _exit_tree() -> void:
	if main_screen_changed.is_connected(_on_main_screen_changed):
		main_screen_changed.disconnect(_on_main_screen_changed)
	if _screen:
		_screen.set_workspace_active(false)
		_screen.queue_free()
		_screen = null


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if visible and not _screen:
		_screen = preload("res://addons/ls5_lipsync/editor/lip_sync_screen.gd").new()
		_screen.hide()
		_screen.set_workspace_active(false)
		_screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
		EditorInterface.get_editor_main_screen().add_child(_screen)
		_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _screen:
		_screen.visible = visible
		_screen.set_workspace_active(visible)


func _on_main_screen_changed(screen_name: String) -> void:
	_make_visible(screen_name == _get_plugin_name())


func _get_plugin_name() -> String:
	return "Lip Sync"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("AudioStreamPlayer", "EditorIcons")
