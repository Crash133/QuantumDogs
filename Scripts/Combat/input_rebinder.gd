class_name InputRebinder
extends RefCounted

signal duplicate_binding_found(action: StringName, conflicting_action: StringName, event: InputEvent)

const CONFIG_PATH := "user://input_bindings.cfg"
const BINDABLE_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_forward", &"move_backwards",
	&"look_left", &"look_right", &"look_up", &"look_down",
	&"light", &"heavy", &"dash", &"jump", &"block", &"execute", &"shoot",
	&"switch_1", &"switch_2", &"switch_3", &"switch_4", &"cam_reset", &"cam_lock", &"pause"
]

func ensure_actions() -> void:
	var defaults := _default_events()
	for action in BINDABLE_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		if InputMap.action_get_events(action).is_empty():
			for event in defaults[action]:
				InputMap.action_add_event(action, event)

func reset_defaults() -> void:
	var defaults := _default_events()
	for action in BINDABLE_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		InputMap.action_erase_events(action)
		for event in defaults[action]:
			InputMap.action_add_event(action, event)

func load_bindings(path: String = CONFIG_PATH) -> Error:
	# Validate the entire file before applying any saved binding.
	reset_defaults()
	var config := ConfigFile.new()
	var error := config.load(path)
	if error != OK:
		return error
	var saved: Dictionary = {}
	for action in BINDABLE_ACTIONS:
		if not config.has_section_key("bindings", String(action)):
			continue
		var events: Variant = config.get_value("bindings", String(action))
		if not events is Array or events.is_empty():
			push_warning("Invalid binding list for %s; using defaults" % action)
			return ERR_INVALID_DATA
		for event in events:
			if not event is InputEvent or not _valid_binding(event):
				push_warning("Invalid binding for %s; using defaults" % action)
				return ERR_INVALID_DATA
		saved[action] = events
	for action in saved:
		InputMap.action_erase_events(action)
		for event in saved[action]:
			InputMap.action_add_event(action, event)
	return OK

func save_bindings(path: String = CONFIG_PATH) -> Error:
	ensure_actions()
	var config := ConfigFile.new()
	for action in BINDABLE_ACTIONS:
		config.set_value("bindings", String(action), InputMap.action_get_events(action))
	return config.save(path)

func rebind(action: StringName, event: InputEvent, swap_duplicate: bool = false, path: String = CONFIG_PATH) -> Error:
	if not BINDABLE_ACTIONS.has(action) or event == null or not _valid_binding(event):
		return ERR_INVALID_PARAMETER
	ensure_actions()
	var duplicate_action: StringName = &""
	var duplicate_event: InputEvent
	for candidate in BINDABLE_ACTIONS:
		if candidate == action:
			continue
		for existing in InputMap.action_get_events(candidate):
			if _same_binding(existing, event):
				duplicate_action = candidate
				duplicate_event = existing
				break
		if duplicate_action != &"":
			break
	if duplicate_action != &"" and not swap_duplicate:
		push_warning("%s is already bound to %s; confirm a swap to bind %s" % [event.as_text(), duplicate_action, action])
		duplicate_binding_found.emit(action, duplicate_action, event)
		return ERR_ALREADY_EXISTS
	var displaced: InputEvent
	for existing in InputMap.action_get_events(action):
		if _is_gamepad(existing) == _is_gamepad(event):
			if displaced == null:
				displaced = existing
			InputMap.action_erase_event(action, existing)
	InputMap.action_add_event(action, event)
	if duplicate_action != &"":
		InputMap.action_erase_event(duplicate_action, duplicate_event)
		if displaced != null:
			InputMap.action_add_event(duplicate_action, displaced)
	return save_bindings(path)

func _same_binding(first: InputEvent, second: InputEvent) -> bool:
	return first.is_match(second, true) and second.is_match(first, true)

func _is_gamepad(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion

func _valid_binding(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.physical_keycode != KEY_NONE or event.keycode != KEY_NONE
	if event is InputEventMouseButton:
		return event.button_index > 0
	if event is InputEventJoypadButton:
		return event.button_index >= 0 and event.button_index < JOY_BUTTON_MAX
	if event is InputEventJoypadMotion:
		return event.axis >= 0 and event.axis < JOY_AXIS_MAX and absf(event.axis_value) > 0.0
	return false

func _default_events() -> Dictionary:
	return {
		&"move_left": [_key(KEY_A), _joy_axis(JOY_AXIS_LEFT_X, -1.0)],
		&"move_right": [_key(KEY_D), _joy_axis(JOY_AXIS_LEFT_X)],
		&"move_forward": [_key(KEY_W), _joy_axis(JOY_AXIS_LEFT_Y, -1.0)],
		&"move_backwards": [_key(KEY_S), _joy_axis(JOY_AXIS_LEFT_Y)],
		&"look_left": [_joy_axis(JOY_AXIS_RIGHT_X, -1.0)],
		&"look_right": [_joy_axis(JOY_AXIS_RIGHT_X)],
		&"look_up": [_joy_axis(JOY_AXIS_RIGHT_Y, -1.0)],
		&"look_down": [_joy_axis(JOY_AXIS_RIGHT_Y)],
		&"light": [_mouse(MOUSE_BUTTON_LEFT), _joy_button(JOY_BUTTON_X)],
		&"heavy": [_mouse(MOUSE_BUTTON_LEFT, true), _joy_button(JOY_BUTTON_Y)],
		&"dash": [_key(KEY_SHIFT), _joy_button(JOY_BUTTON_B)],
		&"jump": [_key(KEY_SPACE), _joy_button(JOY_BUTTON_A)],
		&"block": [_mouse(MOUSE_BUTTON_RIGHT), _joy_button(JOY_BUTTON_LEFT_SHOULDER)],
		&"execute": [_key(KEY_E), _joy_axis(JOY_AXIS_TRIGGER_LEFT)],
		&"shoot": [_key(KEY_Q), _joy_axis(JOY_AXIS_TRIGGER_RIGHT)],
		&"switch_1": [_key(KEY_1), _joy_button(JOY_BUTTON_DPAD_UP)],
		# D-pad directions match the HUD weapon d-pad: Saber down, Lance left, Greatsword right.
		&"switch_2": [_key(KEY_2), _joy_button(JOY_BUTTON_DPAD_DOWN)],
		&"switch_3": [_key(KEY_3), _joy_button(JOY_BUTTON_DPAD_LEFT)],
		&"switch_4": [_key(KEY_4), _joy_button(JOY_BUTTON_DPAD_RIGHT)],
		&"cam_reset": [_mouse(MOUSE_BUTTON_MIDDLE, false, true), _joy_button(JOY_BUTTON_LEFT_STICK)],
		&"cam_lock": [_mouse(MOUSE_BUTTON_MIDDLE), _joy_button(JOY_BUTTON_RIGHT_STICK)],
		&"pause": [_key(KEY_ESCAPE), _joy_button(JOY_BUTTON_START)],
	}

func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event

func _mouse(button: MouseButton, use_alt: bool = false, use_shift: bool = false) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.alt_pressed = use_alt
	event.shift_pressed = use_shift
	return event

func _joy_button(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	return event

func _joy_axis(axis: JoyAxis, value: float = 1.0) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event
