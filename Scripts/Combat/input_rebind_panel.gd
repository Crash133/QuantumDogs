class_name CombatRebindPanel
extends VBoxContainer

signal capture_changed(active: bool)

var config_path: String = InputRebinder.CONFIG_PATH
var ui_exclusion: Control
var _rebinder: InputRebinder = InputRebinder.new()
var _picker: OptionButton
var _message: Label
var _swap: Button
var _capturing: bool = false
var _was_paused: bool = false
var _action: StringName
var _pending_event: InputEvent

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rebinder.ensure_actions()
	_rebinder.duplicate_binding_found.connect(_on_duplicate)
	_picker = OptionButton.new()
	for action in InputRebinder.BINDABLE_ACTIONS:
		_picker.add_item(String(action))
	add_child(_picker)
	var row := HBoxContainer.new()
	add_child(row)
	_button(row, "Capture", func() -> void: begin_rebind(StringName(_picker.get_item_text(_picker.selected))))
	_swap = _button(row, "Swap", confirm_swap)
	_swap.visible = false
	_button(row, "Cancel", cancel_rebind)
	_button(row, "Defaults", _restore_defaults)
	_message = Label.new()
	_message.text = "Capture a key/button, or click the arena for mouse bindings."
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_font_size_override(&"font_size", 12)
	_message.custom_minimum_size.x = 316.0
	add_child(_message)

func begin_rebind(action: StringName) -> void:
	if not action in InputRebinder.BINDABLE_ACTIONS:
		return
	if _capturing:
		cancel_rebind()
	_action = action
	_pending_event = null
	_was_paused = get_tree().paused
	_capturing = true
	get_tree().paused = true
	_swap.visible = false
	_message.text = "Binding %s: press a key/button or click the arena." % action
	capture_changed.emit(true)

func is_capturing() -> bool:
	return _capturing

func _input(event: InputEvent) -> void:
	if not _capturing:
		return
	if event is InputEventMouseButton:
		var exclusion := ui_exclusion if is_instance_valid(ui_exclusion) else self
		if exclusion.get_global_rect().has_point(event.position):
			return
	if _pending_event != null:
		if event.is_action_pressed(&"ui_accept"):
			confirm_swap()
		elif event.is_action_pressed(&"ui_cancel"):
			cancel_rebind()
		get_viewport().set_input_as_handled()
		return
	if _binding_from_event(event) == null:
		return
	try_capture(event)
	get_viewport().set_input_as_handled()

func try_capture(event: InputEvent) -> Error:
	if not _capturing or _pending_event != null:
		return ERR_BUSY
	var binding := _binding_from_event(event)
	if binding == null:
		return ERR_INVALID_PARAMETER
	var error := _rebinder.rebind(_action, binding, false, config_path)
	if error != ERR_ALREADY_EXISTS:
		_message.text = "%s → %s" % [_action, binding.as_text()] if error == OK else "Binding save failed: %s" % error_string(error)
		_finish_capture()
	return error

func confirm_swap() -> Error:
	if not _capturing or _pending_event == null:
		return ERR_INVALID_PARAMETER
	var error := _rebinder.rebind(_action, _pending_event, true, config_path)
	_message.text = "Swapped %s." % _action if error == OK else "Binding save failed: %s" % error_string(error)
	_finish_capture()
	return error

func cancel_rebind() -> void:
	if _capturing:
		_message.text = "Capture cancelled."
		_finish_capture()

func _on_duplicate(action: StringName, other: StringName, event: InputEvent) -> void:
	_pending_event = event
	_message.text = "%s is used by %s. Swap with %s or cancel." % [event.as_text(), other, action]
	_swap.visible = true
	_swap.grab_focus()

func _finish_capture() -> void:
	_capturing = false
	_pending_event = null
	_swap.visible = false
	for action in InputRebinder.BINDABLE_ACTIONS:
		Input.action_release(action)
	get_tree().paused = _was_paused
	capture_changed.emit(false)

func _restore_defaults() -> void:
	cancel_rebind()
	_rebinder.reset_defaults()
	var error := _rebinder.save_bindings(config_path)
	_message.text = "Default bindings restored." if error == OK else "Default save failed: %s" % error_string(error)

func _binding_from_event(event: InputEvent) -> InputEvent:
	var binding: InputEvent
	if event is InputEventKey and event.pressed and not event.echo:
		var key := InputEventKey.new()
		key.physical_keycode = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		binding = key
	elif event is InputEventMouseButton and event.pressed:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = event.button_index
		binding = mouse
	elif event is InputEventJoypadButton and event.pressed:
		var button := InputEventJoypadButton.new()
		button.button_index = event.button_index
		binding = button
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		var axis := InputEventJoypadMotion.new()
		axis.axis = event.axis
		axis.axis_value = signf(event.axis_value)
		binding = axis
	if binding == null:
		return null
	binding.device = -1
	if binding is InputEventWithModifiers:
		binding.alt_pressed = event.alt_pressed
		binding.shift_pressed = event.shift_pressed
		binding.ctrl_pressed = event.ctrl_pressed
		binding.meta_pressed = event.meta_pressed
		if binding is InputEventKey:
			if binding.physical_keycode == KEY_SHIFT: binding.shift_pressed = false
			if binding.physical_keycode == KEY_ALT: binding.alt_pressed = false
			if binding.physical_keycode == KEY_CTRL: binding.ctrl_pressed = false
			if binding.physical_keycode == KEY_META: binding.meta_pressed = false
	return binding

func _exit_tree() -> void:
	if _capturing:
		get_tree().paused = _was_paused

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
