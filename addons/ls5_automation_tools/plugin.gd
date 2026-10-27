@tool
extends EditorPlugin

const Authoring = preload("res://addons/ls5_automation_tools/authoring.gd")
const LiveEdit = preload("res://LS5Framework/Scripts/Player/Automation/AutomationLiveEdit.gd")

## Source selected in the edited scene.
var _source_ref: WeakRef
## Automation dock and its scrollable content.
var _dock: ScrollContainer
var _body: VBoxContainer
var _title: Label
var _status: Label
var _preview_label: Label
var _tree: Tree
var _presets: OptionButton
var _add: MenuButton
var _monitor: CheckBox
var _runtime: RichTextLabel
var _slider: HSlider
var _direction: OptionButton
var _gizmo: EditorNode3DGizmoPlugin
var _inspector: EditorInspectorPlugin
var _debugger: EditorDebuggerPlugin
var _remaining: float = 0.0
var _fingerprint: int = 0
var _sent: Dictionary = {}
var _sessions: Dictionary = {}
var _refreshing: bool = false
var _route_buttons: Array[BaseButton] = []


func _enter_tree() -> void:
	add_to_group(&"AutomationEditorTools")
	_gizmo = preload("res://addons/ls5_automation_tools/gizmo.gd").new()
	add_node_3d_gizmo_plugin(_gizmo)
	_inspector = preload("res://addons/ls5_automation_tools/inspector.gd").new()
	_inspector.connect("source_requested", _open_tools)
	add_inspector_plugin(_inspector)
	_debugger = preload("res://addons/ls5_automation_tools/debugger.gd").new()
	_debugger.connect("configuration_requested", _configuration_requested)
	_debugger.connect("diagnostics_received", _diagnostics)
	add_debugger_plugin(_debugger)
	_build_dock()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	EditorInterface.get_selection().selection_changed.connect(_selection_changed)
	_selection_changed()


func _exit_tree() -> void:
	if EditorInterface.get_selection().selection_changed.is_connected(_selection_changed):
		EditorInterface.get_selection().selection_changed.disconnect(_selection_changed)
	remove_node_3d_gizmo_plugin(_gizmo)
	remove_inspector_plugin(_inspector)
	remove_debugger_plugin(_debugger)
	remove_control_from_docks(_dock)
	_dock.queue_free()


func _open_tools(source: AutomationSplineCore) -> void:
	_select_source(source)
	var branch: Control = _dock
	var parent: Node = branch.get_parent()
	while parent:
		if parent is TabContainer:
			var index: int = parent.get_tab_idx_from_control(branch)
			if index >= 0:
				parent.current_tab = index
			break
		if parent is Control:
			branch = parent as Control
		parent = parent.get_parent()


func _source() -> AutomationSplineCore:
	return _source_ref.get_ref() as AutomationSplineCore if _source_ref else null


func _selection_changed() -> void:
	for selected: Node in EditorInterface.get_selection().get_selected_nodes():
		var node: Node = selected
		while node:
			if node is AutomationSplineCore:
				_select_source(node as AutomationSplineCore)
				return
			node = node.get_parent()
	_source_ref = null
	_refresh()


func _select_source(source: AutomationSplineCore) -> void:
	_source_ref = weakref(source)
	_fingerprint = 0
	_refresh()


func _build_dock() -> void:
	_dock = ScrollContainer.new()
	_dock.name = "Automation"
	_dock.custom_minimum_size.x = 240.0 * EditorInterface.get_editor_scale()
	_dock.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dock.add_child(_body)
	_title = Label.new()
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_title)
	_presets = OptionButton.new()
	for preset: String in Authoring.PRESETS:
		_presets.add_item(preset.capitalize())
	_body.add_child(_presets)
	_button("Apply preset behavior", _apply_preset, "Replaces influence arrays and capture distance. Preserves path, transforms, priority, activation mode, and custom volumes.")
	_add = MenuButton.new()
	_add.text = "Add Influence"
	_route_buttons.append(_add)
	for index: int in Authoring.CATALOG.size():
		_add.get_popup().add_item(Authoring.CATALOG[index].label, index)
	_add.get_popup().id_pressed.connect(_add_component)
	_body.add_child(_add)
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.custom_minimum_size.y = 180.0 * EditorInterface.get_editor_scale()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_activated.connect(_edit_component)
	_body.add_child(_tree)
	_button("Edit selected influence", _edit_component)
	var row: HBoxContainer = HBoxContainer.new()
	_body.add_child(row)
	for label: String in ["Up", "Down", "Remove"]:
		var button: Button = Button.new()
		button.text = label
		button.clip_text = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_modify_component.bind(label))
		row.add_child(button)
		_route_buttons.append(button)
	_button("Make selected influence local", _modify_component.bind("Local"), "Duplicates the selected resource and its nested resources for this route.")
	_button("Make all influences local", _local_all)
	_button("Generate / regenerate triggers", _generate, "Replaces only the marked _AutomationVolumes subtree. Custom areas remain intact. Undo restores the previous geometry and references.", false)
	var generation: Label = Label.new()
	generation.text = "Trigger size and spacing: Inspector → Authoring"
	generation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(generation)
	_direction = OptionButton.new()
	_direction.add_item("Preview forward", 1)
	_direction.add_item("Preview reverse", -1)
	_direction.item_selected.connect(_preview_direction)
	_body.add_child(_direction)
	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.001
	_slider.value_changed.connect(_preview_changed)
	_body.add_child(_slider)
	_preview_label = Label.new()
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_preview_label)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_status)
	_monitor = CheckBox.new()
	_monitor.text = "Monitor running players"
	_monitor.toggled.connect(_monitor_changed)
	_body.add_child(_monitor)
	_runtime = RichTextLabel.new()
	_runtime.custom_minimum_size.y = 150.0 * EditorInterface.get_editor_scale()
	_runtime.text = "Run the project with the editor debugger to inspect automation sessions."
	_body.add_child(_runtime)


func _button(label: String, callback: Callable, tooltip: String = "", route_only: bool = true) -> void:
	var button: Button = Button.new()
	button.text = label
	button.clip_text = true
	button.tooltip_text = tooltip
	button.pressed.connect(callback)
	if route_only:
		_route_buttons.append(button)
	_body.add_child(button)


func _refresh() -> void:
	if not _dock:
		return
	_refreshing = true
	var source: AutomationSplineCore = _source()
	_title.text = String(source.name) if source else "Select an automation route or its path"
	var previous: Dictionary = _selection()
	_tree.clear()
	var root: TreeItem = _tree.create_item()
	if source:
		for key: String in Authoring.ARRAYS:
			if source is AutomationDepthProfile:
				break
			var group: TreeItem = _tree.create_item(root)
			group.set_text(0, key.trim_suffix("_traits").capitalize())
			group.set_selectable(0, false)
			var items: Array = source.get(key)
			for index: int in items.size():
				var entry: TreeItem = _tree.create_item(group)
				var component: Resource = items[index]
				entry.set_text(0, component.resource_name if component and component.resource_name else (component.get_script().resource_path.get_file().get_basename() if component else "Empty influence"))
				entry.set_metadata(0, {"array": key, "index": index})
				if previous.get("array") == key and int(previous.get("index", -1)) == index:
					entry.select(0)
		_slider.set_value_no_signal(source.preview_progress)
		_direction.select(0 if source.preview_direction > 0 else 1)
		var warnings: PackedStringArray = source._get_configuration_warnings()
		_status.text = "Validation: ready" if warnings.is_empty() else "Validation:\n• " + "\n• ".join(warnings)
		_preview()
	else:
		_status.text = ""
		_preview_label.text = ""
	for control: Node in _body.get_children():
		if control is BaseButton and control != _monitor:
			control.disabled = source == null or source is AutomationDepthProfile and control in [_add, _presets]
	for button: BaseButton in _route_buttons:
		button.disabled = source == null or source is AutomationDepthProfile
	_slider.editable = source != null
	_refreshing = false


func _preview() -> void:
	var source: AutomationSplineCore = _source()
	if not source:
		return
	var state: Dictionary = Authoring.preview(source)
	if not state.valid:
		_preview_label.text = String(state.message)
		return
	var weights: Dictionary = state.weights
	_preview_label.text = "Preview: %.1f / %.1f m · %s\nStatic ground weights, entry complete · %.1f m/s\nSteering %.2f · Position %.2f · Speed %.2f\nSurface %.2f · Input %.2f\nCyan route · Purple confinement · Red depth/capture · Yellow ramps · Green cursor · Orange depth offsets" % [state.sample.distance, state.length, "forward" if source.preview_direction > 0 else "reverse", state.signed_speed, weights[1], weights[2], weights[4], weights[8], weights[16]]


func _commit(label: String, changes: Dictionary) -> void:
	var source: AutomationSplineCore = _source()
	if not source:
		return
	var undo: EditorUndoRedoManager = get_undo_redo()
	undo.create_action(label, UndoRedo.MERGE_DISABLE, source)
	for key: String in changes:
		undo.add_do_property(source, key, changes[key])
		undo.add_undo_property(source, key, source.get(key))
	undo.add_do_method(self, "_changed", source)
	undo.add_undo_method(self, "_changed", source)
	undo.commit_action()


func _changed(source: AutomationSplineCore) -> void:
	Authoring.refresh(source)
	call_deferred("_refresh")


func _apply_preset() -> void:
	if _source() and not _source() is AutomationDepthProfile:
		_commit("Apply automation preset", Authoring.preset_properties(_presets.selected))


func _add_component(index: int) -> void:
	var source: AutomationSplineCore = _source()
	if not source or source is AutomationDepthProfile:
		return
	var key: String = Authoring.CATALOG[index].array
	var items: Array = source.get(key).duplicate()
	items.append(Authoring.make_component(index))
	_commit("Add automation influence", {key: items})


func _selection() -> Dictionary:
	var item: TreeItem = _tree.get_selected()
	return item.get_metadata(0) if item and item.get_metadata(0) is Dictionary else {}


func _edit_component() -> void:
	var state: Dictionary = _selection()
	if not state.is_empty() and _source():
		var component: Resource = _source().get(state.array)[state.index]
		if component:
			EditorInterface.edit_resource(component)


func _modify_component(operation: String) -> void:
	var state: Dictionary = _selection()
	if state.is_empty() or not _source():
		return
	var items: Array = _source().get(state.array).duplicate()
	var index: int = int(state.index)
	if operation == "Remove":
		items.remove_at(index)
	elif operation == "Local" and items[index]:
		items[index] = items[index].duplicate(true)
		items[index].resource_local_to_scene = true
	else:
		var destination: int = index + (-1 if operation == "Up" else 1)
		if destination < 0 or destination >= items.size():
			return
		var component: Resource = items[index]
		items[index] = items[destination]
		items[destination] = component
	_commit("Edit automation influences", {String(state.array): items})


func _local_all() -> void:
	if _source() and not _source() is AutomationDepthProfile:
		_commit("Make automation influences local", Authoring.local_properties(_source()))


func _generate() -> void:
	var source: AutomationSplineCore = _source()
	if not source:
		return
	var container: Node3D = Authoring.build_triggers(source)
	if not container:
		_status.text = "Generation requires a valid path and an unoccupied _AutomationVolumes name."
		return
	var previous: Node3D = source.get_node_or_null(NodePath(Authoring.GENERATED)) as Node3D
	var owner: Node = EditorInterface.get_edited_scene_root()
	var old_paths: Dictionary = {"start_gate_path": source.start_gate_path, "end_gate_path": source.end_gate_path, "volume_path": source.volume_path}
	var new_paths: Dictionary = {"start_gate_path": NodePath("_AutomationVolumes/Start"), "end_gate_path": NodePath("_AutomationVolumes/End"), "volume_path": NodePath("_AutomationVolumes/Volume")}
	var undo: EditorUndoRedoManager = get_undo_redo()
	undo.create_action("Generate automation triggers", UndoRedo.MERGE_DISABLE, source)
	undo.add_do_method(self, "_replace_triggers", source, previous, container, owner, new_paths)
	undo.add_undo_method(self, "_replace_triggers", source, container, previous, owner, old_paths)
	undo.add_do_reference(container)
	if previous:
		undo.add_undo_reference(previous)
	undo.commit_action()


func _replace_triggers(source: AutomationSplineCore, remove: Node3D, add: Node3D, owner: Node, paths: Dictionary) -> void:
	Authoring.replace_triggers(source, remove, add, owner, paths)
	call_deferred("_refresh")


func _preview_changed(value: float) -> void:
	if not _refreshing and _source():
		_source().preview_progress = value
		_source().update_gizmos()
		_preview()


func _preview_direction(index: int) -> void:
	if not _refreshing and _source():
		_commit("Change automation preview direction", {"preview_direction": 1 if index == 0 else -1})


func _configuration_requested(id: int) -> void:
	var session: EditorDebuggerSession = _debugger.get_session(id)
	_sessions[session.get_instance_id()] = true
	_sent.clear()
	session.send_message("ls5_automation_edit:monitor", [_monitor.button_pressed])


func _monitor_changed(enabled: bool) -> void:
	for session: EditorDebuggerSession in _debugger.get_sessions():
		if session.is_active():
			session.send_message("ls5_automation_edit:monitor", [enabled])


func _diagnostics(data: Array) -> void:
	var lines: PackedStringArray = []
	for record: Dictionary in data:
		lines.append(preload("res://LS5Framework/Scripts/Player/Automation/AutomationDebugOverlay.gd").format_diagnostics(record))
	_runtime.text = "\n".join(lines) if not lines.is_empty() else "No automation players in the running scene."


func _process(delta: float) -> void:
	_remaining -= delta
	if _remaining > 0.0:
		return
	_remaining = 0.25
	var source: AutomationSplineCore = _source()
	if source:
		var fingerprint: int = hash(LiveEdit.snapshot(source))
		if fingerprint != _fingerprint:
			_fingerprint = fingerprint
			Authoring.refresh(source)
			_refresh()
	var root: Node = EditorInterface.get_edited_scene_root()
	if root and not root.scene_file_path.is_empty():
		_scan(root, root)


func _scan(root: Node, node: Node) -> void:
	if node is AutomationSplineCore:
		var state: Dictionary = LiveEdit.snapshot(node)
		var path: NodePath = root.get_path_to(node)
		for session: EditorDebuggerSession in _debugger.get_sessions():
			if not session.is_active():
				_sessions.erase(session.get_instance_id())
				continue
			if not _sessions.has(session.get_instance_id()):
				continue
			var key: String = str(session.get_instance_id()) + root.scene_file_path + String(path)
			var fingerprint: int = hash(state)
			if _sent.get(key) != fingerprint:
				_sent[key] = fingerprint
				session.send_message("ls5_automation_edit:configuration", [root.scene_file_path, path, state])
	for child: Node in node.get_children():
		_scan(root, child)
