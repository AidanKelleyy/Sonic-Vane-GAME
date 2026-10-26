extends Node

## Panel constrained to the available menu viewport.
var panel: Control
## Aligns form labels and editors without collapsing labels into narrow columns.
var form_layout: bool = false
## Body constrained by the panel's scroll viewport.
var _content: VBoxContainer
## Scrolls the panel body without shrinking text or focus targets.
var _scroll: ScrollContainer
var _maximum_width: float = 1120.0


func _ready() -> void:
	if not panel:
		return
	_maximum_width = maxf(panel.size.x, 640.0)
	for child: Node in panel.get_children():
		if child is VBoxContainer:
			_scroll = ScrollContainer.new()
			_scroll.name = "MenuViewport"
			_scroll.focus_mode = Control.FOCUS_NONE
			_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			panel.add_child(_scroll)
			_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_scroll.offset_left = 20.0
			_scroll.offset_top = 20.0
			_scroll.offset_right = -20.0
			_scroll.offset_bottom = -20.0
			child.reparent(_scroll, false)
			var content: VBoxContainer = child as VBoxContainer
			_content = content
			content.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			content.size_flags_vertical = Control.SIZE_EXPAND_FILL
			break
	get_viewport().size_changed.connect(_layout)
	panel.visibility_changed.connect(_layout)
	_layout()


func _layout() -> void:
	if not panel or not panel.is_inside_tree():
		return
	var parent: Control = panel.get_parent() as Control
	var available: Vector2 = parent.size if parent else get_viewport().get_visible_rect().size
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.custom_minimum_size = Vector2.ZERO
	panel.size = Vector2(minf(_maximum_width, maxf(available.x - 48.0, 1.0)), maxf(available.y - 64.0, 1.0))
	panel.position = (available - panel.size) * 0.5
	var content_width: float = maxf(panel.size.x - 56.0, 1.0)
	if form_layout and _content:
		_fit_form(_content, content_width)
	else:
		_fit_content(panel, content_width)


func _fit_form(content: VBoxContainer, width: float) -> void:
	var label_width: float = clampf(width * 0.30, 148.0, 232.0)
	for child: Node in content.get_children():
		if child is HBoxContainer:
			var row: HBoxContainer = child as HBoxContainer
			row.custom_minimum_size.y = 48.0
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for item: Node in row.get_children():
				if item is Label:
					var label: Label = item as Label
					label.add_theme_font_size_override("font_size", 20)
					label.custom_minimum_size.x = label_width
					label.size_flags_horizontal = Control.SIZE_FILL
					label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				elif item is CheckBox or item is ColorPickerButton:
					var compact: Control = item as Control
					compact.custom_minimum_size = Vector2(52.0, 48.0)
					compact.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
					compact.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				elif item is LineEdit or item is OptionButton or item is SpinBox or item is Button:
					var editor: Control = item as Control
					editor.custom_minimum_size = Vector2(0.0, 48.0)
					editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					editor.size_flags_vertical = Control.SIZE_SHRINK_CENTER
					editor.add_theme_font_size_override("font_size", 20)
		elif child is Label and child.name != &"LabelOnline":
			var description: Label = child as Label
			description.custom_minimum_size.x = width
			description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			description.add_theme_font_size_override("font_size", 18)


func _fit_content(node: Node, width: float) -> void:
	for child: Node in node.get_children():
		if child is Label:
			var label: Label = child as Label
			if node is HBoxContainer:
				label.autowrap_mode = TextServer.AUTOWRAP_OFF
				if label.name == &"Value":
					label.custom_minimum_size.x = maxf(label.custom_minimum_size.x, 64.0)
					label.size_flags_horizontal = Control.SIZE_SHRINK_END
				else:
					for sibling: Node in node.get_children():
						if sibling is Slider:
							label.custom_minimum_size.x = clampf(width * 0.32, 140.0, 200.0)
							label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			else:
				label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				label.custom_minimum_size.x = 0.0
		elif child is Control:
			var control: Control = child as Control
			control.custom_minimum_size.x = minf(control.custom_minimum_size.x, width * 0.45 if control.get_parent() is HBoxContainer else width)
		_fit_content(child, width)
