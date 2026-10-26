extends Node

const HOVER: AudioStream = preload("res://LS5Framework/Sounds/Menu/ui_hover.wav")
const PRESS: AudioStream = preload("res://LS5Framework/Sounds/Menu/ui_down.wav")
const RELEASE: AudioStream = preload("res://LS5Framework/Sounds/Menu/ui_release.wav")

## Menu whose static and generated controls receive UI feedback.
var host: Control
## Plays navigation and pointer-hover feedback.
var _hover: AudioStreamPlayer
## Plays button-down feedback.
var _press: AudioStreamPlayer
## Plays activation feedback independently of pause and warning sounds.
var _release: AudioStreamPlayer
var _hover_suppressed_until: int = 0
var _activation_pending: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hover = _player(HOVER, -15.91, 0.9)
	_press = _player(PRESS, -9.0)
	_release = _player(RELEASE, -9.0)
	_bind_branch(host)
	get_tree().node_added.connect(_on_node_added)
	MenuNavigation.action_cancelled.connect(func(scope_root: Control) -> void:
		if host and host.is_ancestor_of(scope_root):
			_play_release()
	)


func _player(stream: AudioStream, volume: float, pitch: float = 1.0) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = stream
	player.bus = &"UI"
	player.volume_db = volume
	player.pitch_scale = pitch
	add_child(player)
	return player


func _on_node_added(node: Node) -> void:
	if host and host.is_ancestor_of(node):
		_bind_instance.call_deferred(node.get_instance_id())


func _bind_instance(instance_id: int) -> void:
	var node: Node = instance_from_id(instance_id) as Node
	if is_instance_valid(node):
		_bind_branch(node)


func _bind_branch(node: Node) -> void:
	if node is Control and not node.has_meta(&"pause_audio_bound"):
		node.set_meta(&"pause_audio_bound", true)
		(node as Control).focus_entered.connect(_play_hover)
		if node is BaseButton:
			var button: BaseButton = node as BaseButton
			button.mouse_entered.connect(_play_hover)
			button.button_down.connect(_play_press)
			button.pressed.connect(_play_release)
			if button is OptionButton:
				(button as OptionButton).get_popup().popup_hide.connect(_play_release)
			elif button is ColorPickerButton:
				(button as ColorPickerButton).get_popup().popup_hide.connect(_play_release)
		elif node is Range and not (node is ScrollBar):
			(node as Range).value_changed.connect(func(_value: float) -> void:
				if (node as Control).has_focus():
					_play_hover()
			)
	for child: Node in node.get_children():
		_bind_branch(child)


func _active() -> bool:
	return is_instance_valid(host) and host.is_visible_in_tree() and bool(host.get("_is_open"))


func _play_hover() -> void:
	if _active() and Time.get_ticks_msec() > _hover_suppressed_until and not Input.is_action_pressed(&"ui_accept") and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_hover.play()


func _play_press() -> void:
	if _active():
		_activation_pending = true
		_hover_suppressed_until = Time.get_ticks_msec() + 150
		_press.play()


func _play_release() -> void:
	if _active() or _activation_pending:
		_activation_pending = false
		_hover_suppressed_until = Time.get_ticks_msec() + 150
		_press.stop()
		_release.play()


func play_back() -> void:
	_play_release()
