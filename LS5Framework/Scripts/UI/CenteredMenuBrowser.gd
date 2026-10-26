extends Control
class_name CenteredMenuBrowser

const PLACEHOLDER: Texture2D = preload("res://LS5Framework/Images/UI/MENU_Selection_Placeholder.png")
const LEFT_ARROW: Texture2D = preload("res://LS5Framework/Images/UI/MENU_Arrow_Left.png")
const RIGHT_ARROW: Texture2D = preload("res://LS5Framework/Images/UI/MENU_Arrow_Right.png")
const SCROLL_TRANSITION_DURATION: float = 0.11

var _groups: Array[Dictionary] = []
var _indices: Dictionary = {}
var _states: Dictionary = {}
var _prompt_signature: String = ""
var _category: int = 0
var _selected_id: String = ""
var _buddy_id: String = ""
var _activate: Callable
var _buddy: Callable
var _settings: Callable
var _back: Callable
var clear_buddy: Callable
var _title: String = ""
var _scroll_transition: Tween
var _transition_targets: Dictionary = {}
var _horizontal_step: float = 0.0
var _vertical_step: float = 0.0
var _pointer_entry: Dictionary = {}
var _pointer_click_position: Vector2 = Vector2.ZERO
var _pointer_click_time: int = 0
## Dark frame containing the selector, guides, and action controls.
var _frame: Panel
## Contains the visible category rows and their thumbnail cards.
var _cards: Control
## Displays the browsed item and its selection status.
var _status: Label
## Contains explicit pointer actions for the current item.
var _footer: HFlowContainer


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_rebuild)
	visibility_changed.connect(_on_browser_visibility_changed)
	_rebuild()


func configure(entries: Array, title: String, selected_id: String, activate: Callable, back: Callable, buddy: Callable = Callable(), buddy_id: String = "", settings: Callable = Callable()) -> void:
	var previous: String = _entry_key(current_entry())
	if title != _title:
		_states[_title] = {"indices": _indices.duplicate(), "category": _category, "entry": previous}
		var state: Dictionary = _states.get(title, {})
		_indices = state.get("indices", {}).duplicate()
		_category = int(state.get("category", 0))
		previous = String(state.get("entry", ""))
	_title = title
	_selected_id = selected_id
	_buddy_id = buddy_id
	_activate = activate
	_back = back
	_buddy = buddy
	_settings = settings
	_groups = MenuSelectList._group_entries_by_category(entries)
	_category = clampi(_category, 0, maxi(_groups.size() - 1, 0))
	var wanted: String = previous if not previous.is_empty() else selected_id
	for category_index: int in range(_groups.size()):
		var category_entries: Array = _groups[category_index]["entries"]
		for index: int in range(category_entries.size()):
			if _entry_key(category_entries[index]) == wanted:
				_category = category_index
				_indices[String(_groups[category_index]["label"])] = index
	_rebuild()


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var signature: String = _input_signature()
	if signature != _prompt_signature:
		_refresh_actions()


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var action: StringName = &""
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			action = &"ui_left" if event.shift_pressed else &"ui_up"
		MOUSE_BUTTON_WHEEL_DOWN:
			action = &"ui_right" if event.shift_pressed else &"ui_down"
		MOUSE_BUTTON_WHEEL_LEFT:
			action = &"ui_left"
		MOUSE_BUTTON_WHEEL_RIGHT:
			action = &"ui_right"
	if action != &"":
		menu_navigate(action)
		grab_focus()
		accept_event()


func current_entry() -> Dictionary:
	if _groups.is_empty():
		return {}
	var group: Dictionary = _groups[_category]
	var entries: Array = group["entries"]
	var index: int = clampi(int(_indices.get(String(group["label"]), 0)), 0, entries.size() - 1)
	return entries[index] if not entries.is_empty() else {}


func menu_navigate(action: StringName) -> void:
	if not can_navigate(action):
		return
	_finish_scroll_transition()
	var previous: Dictionary = _capture_card_positions()
	var direction: Vector2 = Vector2.ZERO
	if action == &"ui_up" or action == &"ui_down":
		_category = clampi(_category + (-1 if action == &"ui_up" else 1), 0, _groups.size() - 1)
		direction.y = -1.0 if action == &"ui_up" else 1.0
	else:
		var group: Dictionary = _groups[_category]
		var label: String = group["label"]
		var entries: Array = group["entries"]
		_indices[label] = clampi(int(_indices.get(label, 0)) + (-1 if action == &"ui_left" else 1), 0, entries.size() - 1)
		direction.x = -1.0 if action == &"ui_left" else 1.0
	_rebuild()
	_start_scroll_transition(previous, direction)


func can_navigate(action: StringName) -> bool:
	if _groups.is_empty():
		return false
	match action:
		&"ui_up":
			return _category > 0
		&"ui_down":
			return _category < _groups.size() - 1
		&"ui_left", &"ui_right":
			var group: Dictionary = _groups[_category]
			var entries: Array = group["entries"]
			var index: int = clampi(int(_indices.get(String(group["label"]), 0)), 0, entries.size() - 1)
			return index > 0 if action == &"ui_left" else index < entries.size() - 1
	return false


func menu_confirm() -> void:
	var entry: Dictionary = current_entry()
	if not entry.is_empty() and _activate.is_valid():
		_activate.call(entry)


func menu_event(event: InputEvent) -> bool:
	if not event.is_pressed() or event.is_echo():
		return false
	var settings_pressed: bool = event is InputEventJoypadButton and event.button_index == JOY_BUTTON_Y
	var buddy_pressed: bool = event is InputEventJoypadButton and event.button_index == JOY_BUTTON_X
	if event is InputEventKey:
		settings_pressed = event.keycode == KEY_F
		buddy_pressed = event.keycode == KEY_R
	if settings_pressed and _settings.is_valid() and not current_entry().is_empty():
		_settings.call(current_entry())
		return true
	if buddy_pressed and _buddy.is_valid() and not current_entry().is_empty():
		_buddy.call(current_entry())
		return true
	if clear_buddy.is_valid() and ((event is InputEventJoypadButton and event.button_index == JOY_BUTTON_LEFT_SHOULDER) or (event is InputEventKey and event.keycode == KEY_DELETE)):
		clear_buddy.call()
		return true
	return false


func _browse(category_index: int, item_index: int) -> void:
	if category_index == _category and _entry_key(_groups[category_index]["entries"][item_index]) == _entry_key(current_entry()):
		grab_focus()
		return
	_finish_scroll_transition()
	var previous: Dictionary = _capture_card_positions()
	var direction: Vector2 = Vector2.ZERO
	if category_index != _category:
		direction.y = signf(float(category_index - _category))
	else:
		direction.x = signf(float(item_index - int(_indices.get(String(_groups[_category]["label"]), 0))))
	_category = category_index
	_indices[String(_groups[_category]["label"])] = item_index
	grab_focus()
	_rebuild()
	_start_scroll_transition(previous, direction)


func _rebuild() -> void:
	if not is_inside_tree():
		return
	_finish_scroll_transition()
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_frame = Panel.new()
	_frame.name = "BrowserFrame"
	_frame.set_meta(&"crt_background_exempt", true)
	_frame.clip_contents = true
	_frame.mouse_filter = Control.MOUSE_FILTER_PASS
	var frame_style: StyleBoxFlat = StyleBoxFlat.new()
	frame_style.bg_color = Color(0.008, 0.018, 0.045, 0.90)
	frame_style.border_color = Color(0.16, 0.32, 0.49, 0.85)
	frame_style.set_border_width_all(1)
	frame_style.set_corner_radius_all(10)
	_frame.add_theme_stylebox_override("panel", frame_style)
	_frame.size = Vector2(minf(maxf(size.x - 32.0, 1.0), 1720.0), maxf(size.y - 32.0, 1.0))
	_frame.position = (size - _frame.size) * 0.5
	add_child(_frame)
	var heading: Label = _label(_title, 30)
	heading.position = Vector2(24.0, 18.0)
	heading.size = Vector2(maxf(_frame.size.x - 48.0, 1.0), 40.0)
	_frame.add_child(heading)
	_cards = Control.new()
	_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards.clip_contents = true
	_frame.add_child(_cards)
	_cards.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cards.offset_top = 76.0
	_cards.offset_bottom = -160.0
	var card_width: float = clampf(_frame.size.x * 0.30, 160.0, 300.0)
	var card_height: float = minf(card_width * 0.75, maxf(_frame.size.y * 0.30, 100.0))
	var center: Vector2 = _frame.size * 0.5
	var row_stride: float = card_height * 0.9 + 40.0
	_horizontal_step = card_width + 28.0
	_vertical_step = row_stride
	for category_index: int in range(maxi(0, _category - 1), mini(_groups.size(), _category + 2)):
		var group: Dictionary = _groups[category_index]
		var entries: Array = group["entries"]
		var selected: int = clampi(int(_indices.get(String(group["label"]), 0)), 0, entries.size() - 1)
		var y: float = center.y - 76.0 + (category_index - _category) * row_stride
		var category_label: Label = _label(String(group["label"]).to_upper(), 20)
		category_label.set_meta(&"browser_motion_key", "row:" + String(group["label"]))
		category_label.position = Vector2(0.0, y - card_height * (0.5 if category_index == _category else 0.4) - 35.0)
		category_label.size = Vector2(_frame.size.x, 30.0)
		_cards.add_child(category_label)
		for item_index: int in range(maxi(0, selected - 2), mini(entries.size(), selected + 3)):
			var entry: Dictionary = entries[item_index]
			var active: bool = category_index == _category and item_index == selected
			var dimensions: Vector2 = Vector2(card_width, card_height) * (1.0 if active else 0.80)
			var button: Button = Button.new()
			button.set_meta(&"browser_motion_key", String(group["label"]) + ":" + _entry_key(entry))
			button.focus_mode = Control.FOCUS_NONE
			button.position = Vector2(center.x + (item_index - selected) * (card_width + 28.0), y) - dimensions * 0.5
			button.size = dimensions
			button.clip_contents = true
			button.tooltip_text = String(entry.get("name", ""))
			if active:
				var style: StyleBoxFlat = StyleBoxFlat.new()
				style.bg_color = Color(0.035, 0.13, 0.25)
				style.border_color = Color(0.42, 0.90, 1.0)
				style.set_border_width_all(4)
				style.set_corner_radius_all(7)
				button.add_theme_stylebox_override("normal", style)
			var image: TextureRect = TextureRect.new()
			image.texture = _thumbnail(entry)
			image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			image.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(image)
			image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			image.offset_left = 8.0
			image.offset_top = 8.0
			image.offset_right = -8.0
			image.offset_bottom = -36.0
			var caption: Label = _label(String(entry.get("name", "")), 20)
			caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			button.add_child(caption)
			caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
			caption.offset_top = -34.0
			caption.offset_bottom = -4.0
			button.pressed.connect(_browse.bind(category_index, item_index))
			button.gui_input.connect(_on_card_input.bind(entry, button))
			_cards.add_child(button)
			button.modulate.a = 1.0 if active else 0.48
	if can_navigate(&"ui_left"):
		_add_arrow(LEFT_ARROW, Vector2(center.x - card_width * 0.5 - 54.0, center.y - 24.0), &"ui_left")
	if can_navigate(&"ui_right"):
		_add_arrow(RIGHT_ARROW, Vector2(center.x + card_width * 0.5 + 6.0, center.y - 24.0), &"ui_right")
	_status = _label(_status_text(), 20)
	_frame.add_child(_status)
	_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_status.offset_top = -132.0
	_status.offset_bottom = -96.0
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer = HFlowContainer.new()
	_footer.name = "ActionBar"
	_footer.alignment = FlowContainer.ALIGNMENT_CENTER
	_footer.add_theme_constant_override("h_separation", 12)
	_frame.add_child(_footer)
	_footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_footer.offset_left = 16.0
	_footer.offset_right = -16.0
	_footer.offset_top = -88.0
	_footer.offset_bottom = -12.0
	_refresh_actions()


func _refresh_actions() -> void:
	if not is_instance_valid(_footer):
		return
	_prompt_signature = _input_signature()
	for child: Node in _footer.get_children():
		_footer.remove_child(child)
		child.queue_free()
	_add_action("Select" if _buddy.is_valid() or _settings.is_valid() else "Play", menu_confirm, not _groups.is_empty(), JOY_BUTTON_A, "Enter")
	if _buddy.is_valid():
		_add_action("Set as Buddy", func() -> void: _buddy.call(current_entry()), not _groups.is_empty(), JOY_BUTTON_X, "R")
	if _settings.is_valid():
		_add_action("Character Settings", func() -> void: _settings.call(current_entry()), not _groups.is_empty(), JOY_BUTTON_Y, "F")
	if clear_buddy.is_valid():
		_add_action("Remove Buddy", func() -> void: clear_buddy.call(), true, JOY_BUTTON_LEFT_SHOULDER, "Del")
	_add_action("Back", func() -> void: _back.call(), true, JOY_BUTTON_B, "Esc")


func _add_action(text: String, callback: Callable, enabled: bool = true, glyph_button: int = -1, key: String = "") -> void:
	var button: Button = Button.new()
	button.text = text
	if SettingsManager.is_controller_input_active() and glyph_button >= 0:
		var glyph: Dictionary = _button_glyph(glyph_button as JoyButton)
		button.icon = glyph.get("texture") as Texture2D
		button.expand_icon = false
		button.add_theme_constant_override("icon_max_width", 32)
		if not button.icon:
			button.text = "%s  %s" % [String(glyph.get("label", "")), text]
	elif not key.is_empty():
		button.text = "%s  %s" % [key, text]
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = not enabled
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(callback)
	_footer.add_child(button)


func _add_arrow(texture: Texture2D, at: Vector2, action: StringName) -> void:
	var button: TextureButton = TextureButton.new()
	button.texture_normal = texture
	button.name = "ArrowLeft" if action == &"ui_left" else "ArrowRight"
	button.flip_h = action == &"ui_left"
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.focus_mode = Control.FOCUS_NONE
	button.position = at
	button.size = Vector2(48.0, 48.0)
	button.pressed.connect(func() -> void: menu_navigate(action))
	_frame.add_child(button)


func _status_text() -> String:
	if _groups.is_empty():
		return "No content available"
	var entry: Dictionary = current_entry()
	var status: String = String(entry.get("name", ""))
	if _entry_key(entry) == _selected_id:
		status += "  •  Selected"
	if not _buddy_id.is_empty() and _entry_key(entry) == _buddy_id:
		status += "  •  Buddy"
	var group: Dictionary = _groups[_category]
	status += "  •  %d / %d" % [int(_indices.get(String(group["label"]), 0)) + 1, group["entries"].size()]
	return status


func _thumbnail(entry: Dictionary) -> Texture2D:
	var thumbnail: Variant = entry.get("thumbnail")
	if thumbnail is Texture2D:
		return thumbnail as Texture2D
	var attributes: Dictionary = entry.get("attributes", {})
	var path: String = String(attributes.get("thumbnail", ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		return load(path) as Texture2D
	return PLACEHOLDER


func _entry_key(entry: Dictionary) -> String:
	return String(entry.get("id", entry.get("source", entry.get("name", ""))))


func _label(text: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _button_glyph(button: JoyButton, style: int = InputBindingGlyphs.Style.AUTO) -> Dictionary:
	return InputBindingGlyphs.describe_binding({"type": "joy_button", "button": button}, style)


func _on_card_input(event: InputEvent, entry: Dictionary, button: Button) -> void:
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var now: int = Time.get_ticks_msec()
	if not event.double_click:
		_pointer_entry = entry
		_pointer_click_position = event.global_position
		_pointer_click_time = now
		return
	button.accept_event()
	var target: Dictionary = _pointer_entry if not _pointer_entry.is_empty() and now - _pointer_click_time <= 1000 and event.global_position.distance_to(_pointer_click_position) <= 8.0 else entry
	_pointer_entry = {}
	var key: String = _entry_key(target)
	for category_index: int in range(_groups.size()):
		var entries: Array = _groups[category_index]["entries"]
		for item_index: int in range(entries.size()):
			if _entry_key(entries[item_index]) == key:
				_browse(category_index, item_index)
				menu_confirm()
				return


func _input_signature() -> String:
	return "%s:%s:%s" % [SettingsManager.is_controller_input_active(), InputBindingGlyphs.resolve_style(), SettingsManager.get_preferred_joypad_device()]


func _capture_card_positions() -> Dictionary:
	var positions: Dictionary = {}
	if not is_instance_valid(_cards):
		return positions
	for child: Node in _cards.get_children():
		if child is Control and child.has_meta(&"browser_motion_key"):
			positions[String(child.get_meta(&"browser_motion_key"))] = (child as Control).position
	return positions


func _start_scroll_transition(previous: Dictionary, direction: Vector2) -> void:
	if not is_visible_in_tree() or direction == Vector2.ZERO:
		return
	_scroll_transition = create_tween()
	_scroll_transition.set_parallel(true)
	_scroll_transition.set_trans(Tween.TRANS_CUBIC)
	_scroll_transition.set_ease(Tween.EASE_OUT)
	for child: Node in _cards.get_children():
		if not (child is Control) or not child.has_meta(&"browser_motion_key"):
			continue
		var control: Control = child as Control
		var key: String = String(control.get_meta(&"browser_motion_key"))
		var destination: Vector2 = control.position
		var alpha: float = control.modulate.a
		_transition_targets[control] = {"position": destination, "alpha": alpha}
		if previous.has(key):
			control.position = previous[key]
		else:
			control.position = destination + direction * Vector2(_horizontal_step, _vertical_step)
			control.modulate.a = 0.0
		_scroll_transition.tween_property(control, "position", destination, SCROLL_TRANSITION_DURATION)
		_scroll_transition.tween_property(control, "modulate:a", alpha, SCROLL_TRANSITION_DURATION)


func _finish_scroll_transition() -> void:
	if _scroll_transition and _scroll_transition.is_valid():
		_scroll_transition.kill()
	_scroll_transition = null
	for control: Control in _transition_targets:
		if is_instance_valid(control):
			var destination: Dictionary = _transition_targets[control]
			control.position = destination["position"]
			control.modulate.a = float(destination["alpha"])
	_transition_targets.clear()


func _on_browser_visibility_changed() -> void:
	_finish_scroll_transition()
	if is_visible_in_tree():
		_refresh_actions()


func _exit_tree() -> void:
	_finish_scroll_transition()
