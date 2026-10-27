extends CanvasLayer

signal level_selected(entry: Dictionary)
signal character_selected(entry: Dictionary)
signal buddy_selected(entry: Dictionary)
signal buddy_despawn_requested()
signal canceled()

@export var title_text: String = "Terminal"
@export var level_data_dir: String = ""
## Directory where CHAR_*.tres character docs live.
@export var character_data_dir: String = "res://LS5Framework/Characters"

@onready var panel: Panel = get_node_or_null("Root/Panel")
@onready var vbox: VBoxContainer = get_node_or_null("Root/Panel/VBox")

var _level_entries: Array = []
var _character_entries: Array = []
var _pack_wait_attempts: int = 0
var _level_list_waiting_for_packs: bool = false
var _current_screen: StringName = &"parent"
## Terminal whose world and scene branch determine the active environment.
var _environment_context: Node3D
## Environment receiving the staged weather and time changes.
var _weather_target: Node
## Reports availability and the result of applying staged changes.
var _weather_status: Label
var _weather_changes: Dictionary = {}


func _ready() -> void:
	MenuNavigation.register_menu(self, _menu_navigation_scope, 20)
	layer = 60
	visible = true
	add_to_group("ModalMenu")
	set_process(true)
	set_process_unhandled_input(true)
	_ensure_content_pack_manager()
	_resolve_level_data_dir()
	_show_parent_menu()
	call_deferred("_focus_default_control")


func _unhandled_input(event: InputEvent) -> void:
	if event == null:
		return
	var cancel_pressed: bool = event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")
	if not cancel_pressed and event is InputEventKey:
		var key := event as InputEventKey
		cancel_pressed = key.pressed and key.keycode == Key.KEY_ESCAPE
	if not cancel_pressed:
		return
	get_viewport().set_input_as_handled()
	if _current_screen != &"parent":
		_show_parent_menu()
	else:
		_cancel()


func _process(_delta: float) -> void:
	pass


func set_level_entries(entries: Array) -> void:
	_level_entries = entries.duplicate(true)
	if _current_screen == &"level":
		_build_level_list()


func _resolve_level_data_dir() -> void:
	if level_data_dir.strip_edges() != "":
		return
	var level_manager := _get_level_manager()
	if level_manager != null:
		var raw_dir = level_manager.get("level_data_dir")
		if raw_dir is String and String(raw_dir).strip_edges() != "":
			level_data_dir = String(raw_dir)
	if level_data_dir.strip_edges() == "":
		level_data_dir = "res://LS5Framework/Scenes/Levels"


## Centered browser shared by terminal content selection screens.
var _browser: CenteredMenuBrowser


func _show_parent_menu() -> void:
	panel.show()
	if is_instance_valid(_browser):
		_browser.hide()
	_current_screen = &"parent"
	_clear_vbox()
	_add_title(_get_title_text())
	_add_button("Character Select", Callable(self, "_show_character_select"))
	_add_button("Buddies", Callable(self, "_show_buddy_select"))
	_add_button("Level Select", Callable(self, "_show_level_select"))
	_add_button("Weather", _show_weather_menu)
	_add_spacer()
	_add_button("Cancel", Callable(self, "_on_cancel_pressed"))
	_add_hint("Esc to cancel")
	call_deferred("_focus_default_control")


func _show_character_select() -> void:
	_current_screen = &"character"
	_character_entries = CharacterCatalog.load_character_entries(character_data_dir)
	_prepare_browser()
	_browser.clear_buddy = Callable()
	_browser.configure(_character_entries, "CHARACTER SELECT", SettingsManager.chosen_character_id, _on_character_entry_pressed, _show_parent_menu, _on_character_entry_right_pressed, SettingsManager.chosen_buddy_character_id if SettingsManager.buddy_active else "")
	MenuNavigation.restore_focus()


func _show_buddy_select() -> void:
	_current_screen = &"buddy"
	_character_entries = CharacterCatalog.load_character_entries(character_data_dir)
	_prepare_browser()
	_browser.clear_buddy = _on_buddy_despawn_pressed
	_browser.configure(_character_entries, "BUDDY SELECT", "", _on_buddy_entry_pressed, _show_parent_menu, _on_character_entry_right_pressed, SettingsManager.chosen_buddy_character_id if SettingsManager.buddy_active else "")
	MenuNavigation.restore_focus()


func _show_level_select() -> void:
	_current_screen = &"level"
	_prepare_browser()
	_build_level_list_after_packs()


func _build_level_list_after_packs() -> void:
	if _current_screen != &"level":
		return
	var pack_manager: Node = _get_content_pack_manager()
	if pack_manager == null:
		_build_level_list()
		return
	if pack_manager.has_method("are_packs_loaded"):
		var loaded = pack_manager.call("are_packs_loaded")
		if loaded is bool and bool(loaded):
			_build_level_list()
			return
	if not _level_list_waiting_for_packs:
		_level_list_waiting_for_packs = true
		if pack_manager.has_signal("packs_loaded"):
			if not pack_manager.packs_loaded.is_connected(_on_packs_loaded):
				pack_manager.packs_loaded.connect(_on_packs_loaded)
			return
	_pack_wait_attempts += 1
	if _pack_wait_attempts >= 120:
		_build_level_list()
		return
	call_deferred("_build_level_list_after_packs")


func _on_packs_loaded() -> void:
	_level_list_waiting_for_packs = false
	if _current_screen == &"level":
		_build_level_list()


func _build_level_list() -> void:
	if _current_screen != &"level":
		return
	if _level_entries.is_empty():
		_level_entries = LevelCatalog.load_level_entries(level_data_dir)
	_prepare_browser()
	_browser.clear_buddy = Callable()
	_browser.configure(_level_entries, "LEVEL SELECT", "", _on_level_entry_pressed, _show_parent_menu)
	MenuNavigation.restore_focus()


func _on_character_entry_pressed(entry: Dictionary) -> void:
	var character_id: String = String(entry.get("id", "")).strip_edges()
	if character_id == "":
		return
	SettingsManager.set_chosen_character_id(character_id)
	SettingsManager.save_now()
	emit_signal("character_selected", entry)
	_show_parent_menu()


func _on_character_entry_right_pressed(entry: Dictionary) -> void:
	_toggle_buddy_entry(entry)


func _on_buddy_entry_pressed(entry: Dictionary) -> void:
	_activate_buddy_entry(entry)
	_show_buddy_select()


func _on_buddy_despawn_pressed() -> void:
	SettingsManager.set_buddy_active(false)
	SettingsManager.save_now()
	emit_signal("buddy_despawn_requested")
	_show_buddy_select()


func _toggle_buddy_entry(entry: Dictionary) -> void:
	var character_id: String = String(entry.get("id", "")).strip_edges()
	if character_id == "":
		return
	if SettingsManager.buddy_active and SettingsManager.chosen_buddy_character_id.nocasecmp_to(character_id) == 0:
		SettingsManager.set_buddy_active(false)
		SettingsManager.save_now()
		emit_signal("buddy_despawn_requested")
	else:
		_activate_buddy_entry(entry)
	if _current_screen == &"character":
		_show_character_select()
	elif _current_screen == &"buddy":
		_show_buddy_select()


func _activate_buddy_entry(entry: Dictionary) -> void:
	var character_id: String = String(entry.get("id", "")).strip_edges()
	if character_id == "":
		return
	SettingsManager.set_chosen_buddy_character_id(character_id)
	SettingsManager.set_buddy_active(true)
	SettingsManager.save_now()
	emit_signal("buddy_selected", entry)


func _on_level_entry_pressed(entry: Dictionary) -> void:
	emit_signal("level_selected", entry)


func _add_title(text: String) -> Label:
	var label := Label.new()
	label.name = "Title"
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	vbox.add_child(label)
	return label


func _add_button(text: String, pressed_callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func():
		pressed_callback.call()
	)
	vbox.add_child(button)
	return button


func _add_scroll_list() -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	return list


func _add_empty_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(label)


func _add_back_buttons(add_hint: bool = true) -> HBoxContainer:
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	vbox.add_child(buttons)

	var back: Button = Button.new()
	back.text = "Back"
	back.pressed.connect(_show_parent_menu)
	buttons.add_child(back)

	var cancel: Button = Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(_on_cancel_pressed)
	buttons.add_child(cancel)

	if add_hint:
		_add_hint("Esc to go back")
	return buttons


func _add_spacer() -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 8.0)
	vbox.add_child(spacer)


func _add_hint(text: String) -> void:
	var hint := Label.new()
	hint.text = text
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	vbox.add_child(hint)


func _clear_vbox() -> void:
	if vbox == null:
		return
	for child in vbox.get_children():
		vbox.remove_child(child)
		child.queue_free()


func _get_title_text() -> String:
	var display: String = title_text.strip_edges()
	if display == "":
		display = "Terminal"
	return display


func _get_active_list() -> VBoxContainer:
	if vbox == null:
		return null
	var scroll: ScrollContainer = vbox.get_node_or_null("Scroll")
	if scroll == null:
		return null
	var list: VBoxContainer = scroll.get_node_or_null("List")
	return list


func _on_cancel_pressed() -> void:
	_cancel()


func _cancel() -> void:
	emit_signal("canceled")
	queue_free()


func _focus_default_control() -> void:
	MenuNavigation.restore_focus()


func _focus_first_focusable_control(root: Node) -> bool:
	if root == null or not is_instance_valid(root):
		return false
	if root is Control:
		var control: Control = root
		if control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE:
			control.grab_focus()
			return true
	for child in root.get_children():
		if _focus_first_focusable_control(child):
			return true
	return false


func _get_scroll_container() -> ScrollContainer:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner != null and focus_owner.is_visible_in_tree():
		var focused_scroll: ScrollContainer = _find_scroll_container_upwards(focus_owner, self)
		if focused_scroll != null:
			return focused_scroll
	return _find_first_scroll_container(self)


func _find_scroll_container_upwards(node: Node, root: Node) -> ScrollContainer:
	var current: Node = node
	while current != null:
		if current is ScrollContainer and current.is_visible_in_tree():
			return current
		if current == root:
			break
		current = current.get_parent()
	return null


func _find_first_scroll_container(root: Node) -> ScrollContainer:
	if root == null or not is_instance_valid(root):
		return null
	if root is ScrollContainer and root.is_visible_in_tree():
		return root
	for child in root.get_children():
		var found: ScrollContainer = _find_first_scroll_container(child)
		if found != null:
			return found
	return null


func _get_content_pack_manager() -> Node:
	if get_tree() == null:
		return null
	var list = get_tree().get_nodes_in_group("ContentPackManager")
	if list != null and list.size() > 0:
		return list[0]
	return get_tree().root.find_child("ContentPackManager", true, false)


func _ensure_content_pack_manager() -> void:
	if get_tree() == null:
		return
	var existing = get_tree().get_nodes_in_group("ContentPackManager")
	if existing != null and existing.size() > 0:
		return
	var mgr := ContentPackManager.new()
	mgr.name = "ContentPackManager"
	get_tree().root.call_deferred("add_child", mgr)
	mgr.call_deferred("load_all_packs")


func _get_level_manager() -> Node:
	if get_tree() == null:
		return null
	var list = get_tree().get_nodes_in_group("LevelManager")
	if list != null and list.size() > 0:
		return list[0]
	return get_tree().root.find_child("LevelManager", true, false)


func _menu_navigation_scope() -> Dictionary:
	if not visible:
		return {}
	if _current_screen in [&"character", &"buddy", &"level"] and is_instance_valid(_browser):
		return {"root": _browser, "page": String(_current_screen), "default": _browser}
	return {"root": panel, "page": String(_current_screen), "cancel": _show_parent_menu if _current_screen != &"parent" else _cancel}




func _prepare_browser() -> void:
	panel.hide()
	if not is_instance_valid(_browser):
		_browser = CenteredMenuBrowser.new()
		get_node("Root").add_child(_browser)
		_browser.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_browser.show()


func set_environment_context(context: Node3D) -> void:
	_environment_context = context


func _resolve_weather_target() -> Node:
	if not is_instance_valid(_environment_context):
		return null
	var candidates: Array[Node] = []
	for candidate: Node in get_tree().get_nodes_in_group(&"environment_weather_system"):
		if candidate is Node3D and candidate.get_world_3d() == _environment_context.get_world_3d():
			candidates.append(candidate)
	var branch: Node = _environment_context
	while branch:
		var local: Array[Node] = []
		for candidate: Node in candidates:
			if branch == candidate or branch.is_ancestor_of(candidate):
				local.append(candidate)
		if local.size() == 1:
			return local[0]
		if local.size() > 1:
			var environment: Environment = _environment_context.get_world_3d().environment
			for candidate: Node in local:
				for world_environment: Node in candidate.find_children("*", "WorldEnvironment", true, false):
					if environment and world_environment.environment == environment:
						return candidate
			return null
		branch = branch.get_parent()
	return null


func _show_weather_menu() -> void:
	_current_screen = &"weather"
	panel.show()
	if is_instance_valid(_browser):
		_browser.hide()
	_clear_vbox()
	_weather_changes.clear()
	_weather_target = _resolve_weather_target()
	_add_title("Weather")
	_weather_status = Label.new()
	_weather_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_weather_status)
	if not is_instance_valid(_weather_target):
		_weather_status.text = "No weather system is available in this space."
	else:
		var state: Dictionary = _weather_target.call("get_terminal_weather_state")
		_weather_status.text = "Changes apply to the current weather and time space." if state["editable"] else "Only the host can change weather and time online."
		var list: VBoxContainer = _add_scroll_list()
		var presets: Array = state["presets"]
		var weather_label: Label = Label.new()
		weather_label.text = "Weather"
		list.add_child(weather_label)
		var weather: OptionButton = OptionButton.new()
		weather.name = "WeatherPreset"
		weather.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		weather.fit_to_longest_item = false
		weather.custom_minimum_size.y = 48.0
		for preset: Dictionary in presets:
			weather.add_item(preset["name"])
			if preset["id"] == state["weather_id"]:
				weather.select(weather.item_count - 1)
		weather.disabled = not state["editable"] or presets.is_empty()
		list.add_child(weather)
		weather.item_selected.connect(func(index: int) -> void: _weather_changes["weather_id"] = presets[index]["id"])
		var dynamic: CheckButton = CheckButton.new()
		dynamic.text = "Automatic weather"
		dynamic.button_pressed = state["dynamic"]
		dynamic.disabled = weather.disabled
		list.add_child(dynamic)
		dynamic.toggled.connect(func(active: bool) -> void: _weather_changes["dynamic"] = active)
		var time_label: Label = Label.new()
		time_label.text = "Time of day — " + _format_weather_time(state["hour"])
		list.add_child(time_label)
		var time: HSlider = HSlider.new()
		time.name = "TimeOfDay"
		time.min_value = 0.0
		time.max_value = 23.75
		time.step = 0.25
		time.value = state["hour"]
		time.editable = state["editable"] and state["has_time"]
		time.custom_minimum_size = Vector2(0.0, 48.0)
		list.add_child(time)
		time.value_changed.connect(func(hour: float) -> void:
			_weather_changes["hour"] = hour
			time_label.text = "Time of day — " + _format_weather_time(hour)
		)
		var progression: CheckButton = CheckButton.new()
		progression.text = "Time progression"
		progression.button_pressed = state["progression"]
		progression.disabled = not time.editable
		list.add_child(progression)
		progression.toggled.connect(func(active: bool) -> void: _weather_changes["progression"] = active)
		var apply: Button = _add_button("Apply", _apply_weather_changes)
		apply.disabled = not state["editable"]
	_add_button("Back", _show_parent_menu)
	MenuNavigation.restore_focus()


func _format_weather_time(hour: float) -> String:
	var minutes: int = roundi(wrapf(hour, 0.0, 24.0) * 60.0) % 1440
	return "%02d:%02d" % [minutes / 60, minutes % 60]


func _apply_weather_changes() -> void:
	if not is_instance_valid(_weather_target) or _resolve_weather_target() != _weather_target:
		_show_weather_menu()
		return
	if _weather_target.call("apply_terminal_weather_changes", _weather_changes):
		_weather_changes.clear()
		_weather_status.text = "Weather and time updated."
	else:
		_weather_status.text = "Weather and time could not be changed."
