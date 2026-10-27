@tool
extends EditorDebuggerPlugin

signal configuration_requested(session_id: int)
signal diagnostics_received(data: Array)


func _has_capture(capture: String) -> bool:
	return capture == "ls5_automation_edit"


func _capture(message: String, data: Array, session_id: int) -> bool:
	if message == "ls5_automation_edit:request":
		configuration_requested.emit(session_id)
		return true
	if message == "ls5_automation_edit:diagnostics":
		diagnostics_received.emit(data)
		return true
	return false
