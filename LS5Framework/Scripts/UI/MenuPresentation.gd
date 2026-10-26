extends RefCounted


static func create_theme() -> Theme:
	var theme: Theme = load("res://LS5Framework/Scenes/MainMenu/MenuBlue_DarkContainers.tres").duplicate()
	theme.default_font_size = 24
	var normal: StyleBoxFlat = _box(Color(0.025, 0.065, 0.15, 0.97), Color(0.12, 0.28, 0.52), 1)
	var hover: StyleBoxFlat = _box(Color(0.055, 0.16, 0.30), Color(0.28, 0.56, 0.78), 1)
	var focus: StyleBoxFlat = _box(Color(0.025, 0.18, 0.32, 0.65), Color(0.42, 0.90, 1.0), 3)
	focus.border_width_left = 8
	var pressed: StyleBoxFlat = _box(Color(0.10, 0.32, 0.57), Color(0.90, 0.81, 0.32), 2)
	for type: String in ["Button", "OptionButton", "CheckBox", "CheckButton", "ColorPickerButton"]:
		theme.set_stylebox("normal", type, normal)
		theme.set_stylebox("hover", type, hover)
		theme.set_stylebox("focus", type, focus)
		theme.set_stylebox("pressed", type, pressed)
		theme.set_color("font_color", type, Color(0.93, 0.96, 1.0))
		theme.set_color("font_focus_color", type, Color(1.0, 1.0, 1.0))
		theme.set_color("font_disabled_color", type, Color(0.50, 0.57, 0.67))
	for type: String in ["Panel", "PanelContainer"]:
		theme.set_stylebox("panel", type, _box(Color(0.012, 0.03, 0.075, 0.98), Color(0.10, 0.31, 0.58), 2))
	for type: String in ["HSlider", "VSlider", "SpinBox", "ItemList", "LineEdit"]:
		theme.set_stylebox("focus", type, focus)
	theme.set_constant("separation", "VBoxContainer", 10)
	theme.set_constant("separation", "HBoxContainer", 14)
	theme.set_color("font_color", "Label", Color(0.91, 0.95, 1.0))
	return theme


static func _box(fill: Color, outline: Color, width: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = outline
	style.set_border_width_all(width)
	style.set_corner_radius_all(5)
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	return style


static func button_label(button: JoyButton) -> String:
	return String(InputBindingGlyphs.describe_binding({"type": "joy_button", "button": button}, InputBindingGlyphs.Style.AUTO, -1, false).get("label", ""))
