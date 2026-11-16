class_name PromptGlyphs
extends RefCounted

# Text glyphs are presentation placeholders; labels always follow the active binding.
const XBOX_BUTTONS := ["A", "B", "X", "Y", "Back", "Guide", "Menu", "L3", "R3", "LB", "RB", "D-pad Up", "D-pad Down", "D-pad Left", "D-pad Right"]
const PLAYSTATION_BUTTONS := ["×", "○", "□", "△", "Create", "PS", "Options", "L3", "R3", "L1", "R1", "D-pad Up", "D-pad Down", "D-pad Left", "D-pad Right"]

static func get_glyph(action: StringName, device: DeviceTracker.Device) -> String:
	if not InputMap.has_action(action):
		return "Unbound"
	for event in InputMap.action_get_events(action):
		var gamepad := event is InputEventJoypadButton or event is InputEventJoypadMotion
		if gamepad != (device != DeviceTracker.Device.KEYBOARD_MOUSE):
			continue
		return _event_label(event, device)
	return "Unbound"

static func _event_label(event: InputEvent, device: DeviceTracker.Device) -> String:
	if event is InputEventJoypadButton:
		var labels := PLAYSTATION_BUTTONS if device == DeviceTracker.Device.PLAYSTATION else XBOX_BUTTONS
		return labels[event.button_index] if event.button_index < labels.size() else event.as_text()
	if event is InputEventJoypadMotion:
		if event.axis == JOY_AXIS_TRIGGER_LEFT:
			return "L2" if device == DeviceTracker.Device.PLAYSTATION else "LT"
		if event.axis == JOY_AXIS_TRIGGER_RIGHT:
			return "R2" if device == DeviceTracker.Device.PLAYSTATION else "RT"
		var stick := "Left Stick" if event.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y] else "Right Stick"
		var direction := ("Left" if event.axis_value < 0.0 else "Right") if event.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_RIGHT_X] else ("Up" if event.axis_value < 0.0 else "Down")
		return "%s %s" % [stick, direction]
	var label := event.as_text()
	if event is InputEventKey:
		label = OS.get_keycode_string(event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode)
	elif event is InputEventMouseButton:
		label = {MOUSE_BUTTON_LEFT: "LMB", MOUSE_BUTTON_RIGHT: "RMB", MOUSE_BUTTON_MIDDLE: "MMB"}.get(event.button_index, event.as_text())
	if event is InputEventWithModifiers:
		var modifiers: Array[String] = []
		if event.ctrl_pressed: modifiers.append("Ctrl")
		if event.alt_pressed: modifiers.append("Alt")
		if event.shift_pressed: modifiers.append("Shift")
		if event.meta_pressed: modifiers.append("Meta")
		modifiers.append(label)
		return " + ".join(modifiers)
	return label
