extends CanvasLayer

## Controller supplying the displayed session and channel state.
var controller_ref: WeakRef
## Source enabling this overlay, retained through ordinary release.
var source_ref: WeakRef
var _panel: PanelContainer
var _text: Label
var _scroll: ScrollContainer
var _remaining: float = 0.0


func _ready() -> void:
	layer = 90
	add_to_group(&"AutomationOverlays")
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background: StyleBoxFlat = StyleBoxFlat.new()
	background.bg_color = Color(0.025, 0.04, 0.065, 0.92)
	background.border_color = Color(0.2, 0.75, 1.0, 0.8)
	background.set_border_width_all(1)
	background.set_content_margin_all(10.0)
	_panel.add_theme_stylebox_override("panel", background)
	add_child(_panel)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.focus_mode = Control.FOCUS_NONE
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_panel.add_child(_scroll)
	_text = Label.new()
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_color_override("font_color", Color(0.9, 0.96, 1.0))
	_scroll.add_child(_text)


func _process(delta: float) -> void:
	var source: Node = source_ref.get_ref() as Node if source_ref else null
	visible = is_instance_valid(source) and bool(source.get("debug_overlay_enabled"))
	if not visible:
		return
	_remaining -= delta
	if _remaining > 0.0:
		return
	_remaining = 0.1
	var controller: RefCounted = controller_ref.get_ref() as RefCounted if controller_ref else null
	if not controller:
		queue_free()
		return
	var data: Dictionary = controller.call("get_diagnostics")
	_text.text = format_diagnostics(data)
	fit_to_viewport(get_viewport().get_visible_rect().size)


func fit_to_viewport(viewport_size: Vector2) -> void:
	var width: float = clampf(viewport_size.x * 0.32, 220.0, 440.0)
	width = minf(width, maxf(viewport_size.x - 24.0, 80.0))
	var font_size: int = clampi(int(viewport_size.y / 48.0), 10, 16)
	_text.add_theme_font_size_override("font_size", font_size)
	_text.custom_minimum_size.x = 0.0
	_panel.size = Vector2(width, 0.0)
	var index: int = 0
	var count: int = 0
	for overlay: Node in get_tree().get_nodes_in_group(&"AutomationOverlays"):
		if overlay is CanvasLayer and overlay.visible and overlay.get_viewport() == get_viewport():
			if overlay != self and count == index:
				index += 1
			count += 1
		if overlay == self:
			index = count - 1
	var columns: int = clampi(int(viewport_size.x / 300.0), 1, maxi(count, 1))
	var rows: int = maxi(int(ceil(float(count) / float(columns))), 1)
	var slot: Vector2 = (viewport_size - Vector2(24.0, 24.0)) / Vector2(float(columns), float(rows))
	width = minf(width, maxf(slot.x - 12.0, 80.0))
	var font: Font = _text.get_theme_font("font")
	var text_size: Vector2 = font.get_multiline_string_size(_text.text, HORIZONTAL_ALIGNMENT_LEFT, maxf(width - 32.0, 60.0), font_size)
	var line_count: float = ceil(text_size.y / maxf(font.get_height(font_size), 1.0))
	var height: float = text_size.y + line_count * float(_text.get_theme_constant("line_spacing")) + 20.0
	_panel.size = Vector2(width, minf(maxf(height, 100.0), slot.y))
	var column: int = index % columns
	var row: int = index / columns
	_panel.position = Vector2(maxf(viewport_size.x - 12.0 - float(column) * slot.x - width, 0.0), maxf(viewport_size.y - 12.0 - float(row) * slot.y - _panel.size.y, 0.0))


static func format_diagnostics(data: Dictionary) -> String:
	var weights: Dictionary = data.weights
	return "AUTOMATION · %s\n%s\nProgress %.1f m · branch %d · direction %d\nSpeed %.1f m/s · error %.2f m\nSteering %.2f · Position %.2f · Speed %.2f\nSurface %.2f · Input %.2f\nBlocked: %s\nCorrection %.3f m · obstruction %s\nSuspended: %s · last release: %s" % [data.player, data.source,
		data.progress, data.branch, data.direction, data.speed, data.tracking_error,
		weights.get(1, 0.0), weights.get(2, 0.0), weights.get(4, 0.0), weights.get(8, 0.0), weights.get(16, 0.0),
		", ".join(data.blocked_actions) if not data.blocked_actions.is_empty() else "none", data.correction, data.obstruction, data.suspended, data.last_release] + "\nLane %d · buffered choice %d" % [data.get("lane", -1), data.get("buffered_choice", 0)]
