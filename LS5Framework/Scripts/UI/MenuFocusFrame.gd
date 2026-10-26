extends Control

## Active navigation service supplying the current focus boundary.
var navigation: Node


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not navigation or not navigation._root or not navigation._keyboard_active:
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if not navigation._eligible(focus) or focus.has_method("menu_navigate") or focus is LineEdit or focus is TextEdit:
		return
	var row: Control = focus.get_parent() as Control if focus.get_parent() is HBoxContainer else focus
	var rect: Rect2 = row.get_global_rect().grow(3.0)
	var parent: Node = focus.get_parent()
	while parent and parent != navigation._root:
		if parent is ScrollContainer:
			rect = rect.intersection((parent as ScrollContainer).get_global_rect())
		parent = parent.get_parent()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	draw_rect(rect, Color(0.12, 0.64, 0.94, 0.10), true)
	draw_rect(rect, Color(0.40, 0.90, 1.0, 0.95), false, 2.0)
	draw_rect(Rect2(rect.position, Vector2(5.0, rect.size.y)), Color(0.40, 0.90, 1.0), true)
