@tool
extends Panel
class_name OptionsPanelLayout

const MINIMUM_PANEL_SIZE: Vector2 = Vector2(900.0, 640.0)

## Container spanning the options viewport.
var _frame: Control


func _ready() -> void:
	_frame = get_parent() as Control
	if not _frame:
		return
	_frame.resized.connect(_queue_layout)
	visibility_changed.connect(_queue_layout)
	_queue_layout()


func _queue_layout() -> void:
	_apply_layout.call_deferred()


func _apply_layout() -> void:
	if not is_instance_valid(_frame) or not is_inside_tree():
		return
	var available: Vector2 = (_frame.size - Vector2.ONE * 32.0).max(Vector2.ONE)
	var factor: float = minf(1.0, minf(available.x / MINIMUM_PANEL_SIZE.x, available.y / MINIMUM_PANEL_SIZE.y))
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	scale = Vector2.ONE * factor
	size = Vector2(MINIMUM_PANEL_SIZE.x, maxf(MINIMUM_PANEL_SIZE.y, (_frame.size.y - 64.0) / factor))
	position = (_frame.size - size * factor) * 0.5
