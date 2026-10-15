extends Node3D

## Camera used to inspect the example volumes.
@export var preview_camera: Camera3D
## Parent containing the example water objects.
@export var examples_root: Node3D
## Label displaying the selected example and controls.
@export var description_label: Label
## Button selecting the preceding example.
@export var previous_button: Button
## Button selecting the following example.
@export var next_button: Button

var _index: int = 0
var _yaw: float = 0.65
var _pitch: float = 0.4
var _zoom: float = 1.0
var _dragging: bool = false
var _titles: Array[String] = [
	"Pool · top surface, stepped waves and caustics",
	"Tilted box · closed boundary, all faces runnable",
	"Sideways wall · local top runnable with matching player orientation",
	"Water sphere · curved boundary, all faces runnable",
	"Clear cylinder · highlights only, optional refraction",
	"CSG union · joined water arms, baked boundary",
	"CSG cutout · dry opening through the water",
]

func _ready() -> void:
	previous_button.pressed.connect(_select.bind(-1))
	next_button.pressed.connect(_select.bind(1))
	next_button.grab_focus()
	_select(0)

func _select(step: int) -> void:
	_index = posmod(_index + step, examples_root.get_child_count())
	_zoom = 1.0
	description_label.text = "%d / %d  %s\nOrbit: right mouse drag / right stick   Zoom: wheel / triggers   Select: buttons / LB / RB" % [_index + 1, examples_root.get_child_count(), _titles[_index]]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = maxf(_zoom * 0.9, 0.45)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = minf(_zoom * 1.1, 2.5)
	elif event is InputEventMouseMotion and _dragging:
		_yaw -= event.relative.x * 0.005
		_pitch = clampf(_pitch + event.relative.y * 0.005, -1.3, 1.3)
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			_select(-1)
		elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			_select(1)

func _process(delta: float) -> void:
	if not Input.get_connected_joypads().is_empty():
		var device: int = Input.get_connected_joypads()[0]
		var look: Vector2 = Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
		if look.length() > 0.2:
			_yaw -= look.x * delta * 1.7
			_pitch = clampf(_pitch + look.y * delta * 1.7, -1.3, 1.3)
		_zoom = clampf(_zoom + (Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT) - Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT)) * delta, 0.45, 2.5)
	var volume: AdventureWaterVolume = examples_root.get_child(_index) as AdventureWaterVolume
	var center: Vector3 = volume.to_global(volume._bounds.get_center())
	var radius: float = maxf(volume._bounds.size.length() * 0.9, 400.0) * _zoom
	preview_camera.global_position = center + Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * radius
	preview_camera.look_at(center)
