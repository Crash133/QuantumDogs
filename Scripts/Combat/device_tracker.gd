class_name DeviceTracker
extends Node

signal device_changed(device: int)
signal gamepad_disconnected(device_id: int)

enum Device { KEYBOARD_MOUSE, XBOX, PLAYSTATION }

var current_device: Device = Device.KEYBOARD_MOUSE
var active_joypad_id: int = -1
@export var motion_threshold: float = 0.2

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

func _input(event: InputEvent) -> void:
	var next := current_device
	if event is InputEventKey:
		if not event.pressed or event.echo:
			return
		next = Device.KEYBOARD_MOUSE
		active_joypad_id = -1
	elif event is InputEventMouse:
		if event is InputEventMouseButton and not event.pressed:
			return
		if event is InputEventMouseMotion and event.relative.is_zero_approx():
			return
		next = Device.KEYBOARD_MOUSE
		active_joypad_id = -1
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if event is InputEventJoypadButton and not event.pressed:
			return
		if event is InputEventJoypadMotion and absf(event.axis_value) <= motion_threshold:
			return
		active_joypad_id = event.device
		next = classify_joy_name(Input.get_joy_name(event.device))
	if next != current_device:
		current_device = next
		device_changed.emit(current_device)

static func classify_joy_name(joy_name: String) -> Device:
	var lower := joy_name.to_lower()
	return Device.PLAYSTATION if "playstation" in lower or "dualshock" in lower or "dualsense" in lower or "ps4" in lower or "ps5" in lower else Device.XBOX

func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action(&"pause") and event.is_action_pressed(&"pause", false, true):
		get_tree().paused = not get_tree().paused
		get_viewport().set_input_as_handled()

func _on_joy_connection_changed(device_id: int, connected: bool) -> void:
	if connected or device_id != active_joypad_id:
		return
	get_tree().paused = true
	gamepad_disconnected.emit(device_id)
	active_joypad_id = -1
