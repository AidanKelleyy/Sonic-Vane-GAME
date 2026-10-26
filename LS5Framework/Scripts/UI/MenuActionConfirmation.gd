extends Control

var _callback: Callable
## Displays the action being confirmed.
var _heading: RichTextLabel
## Describes the result before an action is executed.
var _body: RichTextLabel
## Returns to the originating action without executing it.
var _cancel: Button
## Executes the pending action after an explicit confirmation.
var _confirm: Button
## Keeps the dialog within the available viewport.
var _panel: Panel
## Places the explicit action before Cancel while keeping Cancel as the default focus.
var _buttons: HBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.005, 0.015, 0.04, 0.88)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = Panel.new()
	add_child(_panel)
	_heading = RichTextLabel.new()
	_heading.add_theme_font_size_override("normal_font_size", 28)
	_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_heading.scroll_active = false
	_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heading.set_meta(&"crt_background_exempt", true)
	_panel.add_child(_heading)
	_body = RichTextLabel.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.scroll_active = false
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.set_meta(&"crt_background_exempt", true)
	_panel.add_child(_body)
	_buttons = HBoxContainer.new()
	_panel.add_child(_buttons)
	_cancel = Button.new()
	_cancel.text = "Cancel"
	_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel.pressed.connect(hide)
	_confirm = Button.new()
	_confirm.text = "Continue"
	_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm.pressed.connect(_execute)
	_buttons.add_child(_confirm)
	_buttons.add_child(_cancel)
	resized.connect(_layout)
	MenuNavigation.register_menu(self, _menu_navigation_scope, 80)
	hide()
	_layout()


func open(title: String, body: String, callback: Callable, confirm_text: String = "Continue") -> void:
	_heading.text = title
	_body.text = body
	_callback = callback
	_confirm.text = confirm_text
	MenuNavigation.forget_focus(self)
	show()
	_layout()
	MenuNavigation.restore_focus()


func _execute() -> void:
	hide()
	if _callback.is_valid():
		_callback.call()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause")):
		hide()
		get_viewport().set_input_as_handled()


func _menu_navigation_scope() -> Dictionary:
	return {"root": self, "default": _cancel, "cancel": hide} if is_visible_in_tree() else {}


func _layout() -> void:
	if not _panel:
		return
	var width: float = minf(640.0, maxf(size.x - 48.0, 1.0))
	var inner_width: float = maxf(width - 40.0, 1.0)
	var heading_height: float = _text_height(_heading, inner_width)
	var body_height: float = _text_height(_body, inner_width)
	var button_height: float = maxf(52.0, _buttons.get_combined_minimum_size().y)
	_heading.position = Vector2(20.0, 20.0)
	_heading.size = Vector2(inner_width, heading_height)
	_body.position = Vector2(20.0, _heading.position.y + heading_height + 12.0)
	_body.size = Vector2(inner_width, body_height)
	_buttons.position = Vector2(20.0, _body.position.y + body_height + 18.0)
	_buttons.size = Vector2(inner_width, button_height)
	_panel.size = Vector2(width, _buttons.position.y + button_height + 20.0)
	_panel.position = (size - _panel.size) * 0.5


func _text_height(label: RichTextLabel, width: float) -> float:
	var paragraph: TextParagraph = TextParagraph.new()
	paragraph.width = width
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	var font: Font = label.get_theme_font("normal_font")
	var font_size: int = label.get_theme_font_size("normal_font_size")
	paragraph.add_string(label.text, font, font_size)
	return maxf(paragraph.get_size().y, font.get_height(font_size))
