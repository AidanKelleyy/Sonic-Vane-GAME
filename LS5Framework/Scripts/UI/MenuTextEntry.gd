extends Control

## Text field receiving the confirmed entry.
var _editor: LineEdit
## Preview buffer kept separate from the originating field until confirmation.
var _preview: LineEdit
## Contains the controller keyboard and editing actions.
var _content: VBoxContainer
## Keeps the keyboard inside the current viewport.
var _panel: PanelContainer
## Initial keyboard focus target.
var _first_key: Button
var _uppercase: bool = true
var _keys: Array[Button] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.005, 0.015, 0.04, 0.90)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	add_child(_panel)
	_content = VBoxContainer.new()
	_panel.add_child(_content)
	var title: Label = Label.new()
	title.text = "TEXT ENTRY"
	title.add_theme_font_size_override("font_size", 26)
	_content.add_child(title)
	_preview = LineEdit.new()
	_preview.focus_mode = Control.FOCUS_NONE
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_preview)
	for letters: String in ["1234567890", "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM-_"]:
		var row: HBoxContainer = HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 4)
		_content.add_child(row)
		for letter: String in letters:
			var button: Button = _button(row, letter, func() -> void: _append(letter.to_upper() if _uppercase else letter.to_lower()))
			button.add_theme_font_size_override("font_size", 20)
			_keys.append(button)
			if not _first_key:
				_first_key = button
	var punctuation: HBoxContainer = HBoxContainer.new()
	punctuation.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_child(punctuation)
	for character: String in [".", ":", "/", "@"]:
		_button(punctuation, character, func() -> void: _append(character))
	_button(punctuation, "Space", func() -> void: _append(" "))
	var actions: HBoxContainer = HBoxContainer.new()
	_content.add_child(actions)
	_button(actions, "Case", _toggle_case)
	_button(actions, "Backspace", _backspace)
	_button(actions, "Clear", func() -> void: _preview.text = "")
	var footer: HBoxContainer = HBoxContainer.new()
	_content.add_child(footer)
	_button(footer, "Cancel", hide)
	_button(footer, "Done", _commit)
	get_node("/root/MenuNavigation").register_menu(self, _menu_navigation_scope, 90)
	resized.connect(_layout)
	hide()


func open(editor: LineEdit) -> void:
	_editor = editor
	_preview.text = editor.text
	_preview.secret = editor.secret
	get_node("/root/MenuNavigation").forget_focus(self)
	show()
	_layout()
	get_node("/root/MenuNavigation").restore_focus()


func _append(character: String) -> void:
	if not is_instance_valid(_editor) or (_editor.max_length > 0 and _preview.text.length() >= _editor.max_length):
		return
	_preview.text += character
	_preview.caret_column = _preview.text.length()


func _backspace() -> void:
	_preview.text = _preview.text.left(maxi(0, _preview.text.length() - 1))


func _toggle_case() -> void:
	_uppercase = not _uppercase
	for button: Button in _keys:
		button.text = button.text.to_upper() if _uppercase else button.text.to_lower()


func _commit() -> void:
	if is_instance_valid(_editor):
		_editor.text = _preview.text
		_editor.set_meta(&"menu_editing", false)
		_editor.text_changed.emit(_editor.text)
		_editor.text_submitted.emit(_editor.text)
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		hide()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_BACKSPACE:
			_backspace()
			get_viewport().set_input_as_handled()
		elif event.unicode >= 32:
			_append(String.chr(event.unicode))
			get_viewport().set_input_as_handled()


func _menu_navigation_scope() -> Dictionary:
	return {"root": self, "default": _first_key, "cancel": hide} if is_visible_in_tree() else {}


func _process(_delta: float) -> void:
	if visible and not is_instance_valid(_editor):
		hide()


func _button(row: HBoxContainer, text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	row.add_child(button)
	return button


func _layout() -> void:
	if not _panel:
		return
	_panel.size.x = minf(900.0, maxf(size.x - 48.0, 1.0))
	_panel.size.y = _panel.get_combined_minimum_size().y
	_panel.position = (size - _panel.size) * 0.5
