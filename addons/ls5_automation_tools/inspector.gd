@tool
extends EditorInspectorPlugin

signal source_requested(source: AutomationSplineCore)


func _can_handle(object: Object) -> bool:
	return object is AutomationSplineCore


func _parse_begin(object: Object) -> void:
	var button: Button = Button.new()
	button.text = "Open Automation Tools"
	button.tooltip_text = "Presets, influence editing, generated triggers, and route preview."
	button.pressed.connect(func() -> void: source_requested.emit(object as AutomationSplineCore))
	add_custom_control(button)
