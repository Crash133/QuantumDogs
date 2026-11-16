class_name OptionsController
extends Node

signal display_preview_changed(active: bool, seconds_left: int)
signal settings_changed(settings: Dictionary)

const ACTION_LABELS := {&"switch_1": "MANTIS BLADES", &"switch_2": "SABER", &"switch_3": "ROCKET LANCE", &"switch_4": "GREATSWORD"}
const REBIND_ACTIONS: Array[StringName] = [&"light", &"heavy", &"dash", &"jump", &"block", &"execute", &"shoot", &"switch_1", &"switch_2", &"switch_3", &"switch_4"]
const SETTINGS_STORE_SCRIPT = preload("res://Scripts/UI/options_store.gd")
var store: RefCounted = SETTINGS_STORE_SCRIPT.new()
var rebinder := InputRebinder.new()
var settings: Dictionary = {}
var original_display: Dictionary = {}
var preview_active := false
var capture_action: StringName = &""
var pending_action: StringName = &""
var pending_event: InputEvent
var panel: Control
var active_combat: CombatController
var bindings_path := "user://input_bindings.cfg"
var _timer: Timer
var _device_tracker: DeviceTracker

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	settings = store.load_settings()
	rebinder.ensure_actions()
	rebinder.load_bindings()
	rebinder.duplicate_binding_found.connect(_on_duplicate_binding_found)
	_apply(settings)

func attach_panel(options_panel: Control, tracker: DeviceTracker = null) -> void:
	panel = options_panel
	_device_tracker = tracker
	if _device_tracker != null and not _device_tracker.device_changed.is_connected(_on_device_changed):
		_device_tracker.device_changed.connect(_on_device_changed)
	if panel == null: return
	_bind_controls()
	_refresh_controls()

func set_combat_controller(combat: CombatController) -> void:
	active_combat = combat

func apply(new_settings: Dictionary, combat: CombatController = null) -> Error:
	settings = store._validated(new_settings)
	_apply(settings, combat if combat != null else active_combat)
	var error: Error = store.save_settings(settings)
	if error == OK: settings_changed.emit(settings.duplicate(true))
	return error

func begin_display_preview(candidate: Dictionary = {}) -> void:
	if not preview_active:
		original_display = _current_display_settings()
	if not candidate.is_empty():
		settings.display_mode = candidate.get("display_mode", settings.display_mode)
		settings.resolution = candidate.get("resolution", settings.resolution)
		settings.vsync = candidate.get("vsync", settings.vsync)
	_apply_display(settings)
	preview_active = true
	_ensure_timer()
	if is_inside_tree(): _timer.start(12.0)
	display_preview_changed.emit(true, 12)
	_show_preview_controls()

func confirm_display_preview() -> void:
	if not preview_active: return
	preview_active = false
	if _timer != null: _timer.stop()
	store.save_settings(settings)
	display_preview_changed.emit(false, 0)
	_show_preview_controls()

func revert_display_preview() -> void:
	if not preview_active: return
	preview_active = false
	if _timer != null: _timer.stop()
	_apply_display(original_display)
	settings.display_mode = original_display.display_mode
	settings.resolution = original_display.resolution
	settings.vsync = original_display.vsync
	display_preview_changed.emit(false, 0)
	_show_preview_controls()
	_refresh_controls()

func _on_preview_timeout() -> void:
	revert_display_preview()

func _ensure_timer() -> void:
	if _timer != null: return
	_timer = Timer.new()
	_timer.name = "DisplayPreviewTimer"
	_timer.one_shot = true
	_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_timer)
	_timer.timeout.connect(_on_preview_timeout)

func _bind_controls() -> void:
	for id in [&"MasterVolume", &"MusicVolume", &"SfxVolume"]:
		var slider := panel.find_child(id, true, false) as HSlider
		if slider != null:
			slider.value_changed.connect(func(value: float) -> void:
				var key: String = {"MasterVolume": "master_volume", "MusicVolume": "music_volume", "SfxVolume": "sfx_volume"}[String(id)]
				settings[key] = value
				apply(settings))
	var battery := panel.find_child("BatteryDrainCheck", true, false) as CheckButton
	if battery != null: battery.toggled.connect(func(value: bool) -> void: settings.battery_drain_enabled = value; apply(settings))
	var reduce := panel.find_child("ReduceMotionCheck", true, false) as CheckButton
	if reduce != null: reduce.toggled.connect(func(value: bool) -> void: settings.reduce_motion = value; apply(settings))
	var vsync := panel.find_child("VSyncCheck", true, false) as CheckButton
	if vsync != null: vsync.toggled.connect(_on_display_control_changed.bind(&"vsync"))
	var mode := panel.find_child("DisplayModeOption", true, false) as OptionButton
	if mode != null: mode.item_selected.connect(func(index: int) -> void: _on_display_control_changed([&"windowed", &"fullscreen", &"borderless"][index], &"display_mode"))
	var resolution := panel.find_child("ResolutionOption", true, false) as OptionButton
	if resolution != null: resolution.item_selected.connect(func(index: int) -> void: _on_display_control_changed([Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)][index], &"resolution"))
	for button in panel.find_children("*", "Button", true, false):
		var b := button as Button
		if b.name.begins_with("Bind_"): b.pressed.connect(_begin_capture.bind(StringName(String(b.name).trim_prefix("Bind_"))))
	var confirm := panel.find_child("ConfirmDisplayButton", true, false) as Button
	if confirm != null: confirm.pressed.connect(confirm_display_preview)
	var revert := panel.find_child("RevertDisplayButton", true, false) as Button
	if revert != null: revert.pressed.connect(revert_display_preview)
	var reset := panel.find_child("ResetBindingsButton", true, false) as Button
	if reset != null: reset.pressed.connect(_reset_bindings)
	var swap := panel.find_child("SwapBindingButton", true, false) as Button
	if swap != null: swap.pressed.connect(_confirm_binding_swap)
	var cancel := panel.find_child("CancelBindingButton", true, false) as Button
	if cancel != null: cancel.pressed.connect(_cancel_binding)
	var back := panel.find_child("OptionsBackButton", true, false) as Button
	if back != null: back.pressed.connect(_on_back)

func _on_display_control_changed(value: Variant, key: StringName) -> void:
	settings[String(key)] = value
	begin_display_preview(settings)

func _refresh_controls() -> void:
	if panel == null: return
	for pair in [["MasterVolume", "master_volume"], ["MusicVolume", "music_volume"], ["SfxVolume", "sfx_volume"]]:
		var slider := panel.find_child(pair[0], true, false) as HSlider
		if slider != null: slider.set_value_no_signal(float(settings[pair[1]]))
	var mode := panel.find_child("DisplayModeOption", true, false) as OptionButton
	if mode != null: mode.select([&"windowed", &"fullscreen", &"borderless"].find(settings.display_mode))
	var resolution := panel.find_child("ResolutionOption", true, false) as OptionButton
	if resolution != null: resolution.select([Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)].find(settings.resolution))
	var vsync := panel.find_child("VSyncCheck", true, false) as CheckButton
	if vsync != null: vsync.set_pressed_no_signal(settings.vsync)
	var battery := panel.find_child("BatteryDrainCheck", true, false) as CheckButton
	if battery != null: battery.set_pressed_no_signal(settings.battery_drain_enabled)
	var reduce := panel.find_child("ReduceMotionCheck", true, false) as CheckButton
	if reduce != null: reduce.set_pressed_no_signal(settings.reduce_motion)
	for action in REBIND_ACTIONS:
		var button := panel.find_child("Bind_" + String(action), true, false) as Button
		if button != null: button.text = "%s  %s" % [ACTION_LABELS.get(action, String(action).to_upper().replace("_", " ")), _binding_text(action)]

func _current_display_settings() -> Dictionary:
	var mode := DisplayServer.window_get_mode()
	return {"display_mode": &"fullscreen" if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else (&"borderless" if mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN else &"windowed"), "resolution": DisplayServer.window_get_size(), "vsync": DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED}

func _apply(settings_to_apply: Dictionary, combat: CombatController = null) -> void:
	_apply_display(settings_to_apply)
	for pair in [["Master", "master_volume"], ["Music", "music_volume"], ["SFX", "sfx_volume"]]:
		var bus := AudioServer.get_bus_index(pair[0])
		if bus >= 0:
			var value := float(settings_to_apply[pair[1]])
			AudioServer.set_bus_mute(bus, value <= 0.001)
			AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(value, 0.001)))
	if combat != null:
		combat.battery_drain_enabled = bool(settings_to_apply.battery_drain_enabled)
		if combat.battery != null: combat.battery.drain_enabled = bool(settings_to_apply.battery_drain_enabled)

func _apply_display(values: Dictionary) -> void:
	var mode: StringName = StringName(values.get("display_mode", &"windowed"))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if mode == &"fullscreen" else (DisplayServer.WINDOW_MODE_FULLSCREEN if mode == &"borderless" else DisplayServer.WINDOW_MODE_WINDOWED))
	var size: Vector2i = values.get("resolution", Vector2i(1600, 900))
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(values.get("vsync", true)) else DisplayServer.VSYNC_DISABLED)

func _show_preview_controls() -> void:
	if panel == null: return
	for id in [&"ConfirmDisplayButton", &"RevertDisplayButton"]:
		var button := panel.find_child(id, true, false) as Button
		if button != null: button.visible = preview_active

func _begin_capture(action: StringName) -> void:
	capture_action = action
	var status := panel.find_child("BindingStatus", true, false) as Label
	if status != null: status.text = "PRESS A KEY OR BUTTON • ESC CANCELS"

func _input(event: InputEvent) -> void:
	if capture_action == &"": return
	if event.is_action_pressed(&"ui_cancel") or (InputMap.has_action(&"pause") and event.is_action_pressed(&"pause")):
		_cancel_binding()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo or event is InputEventMouseButton and event.pressed or event is InputEventJoypadButton and event.pressed:
		var action := capture_action
		capture_action = &""
		pending_action = action
		pending_event = event
		var error: Error = rebinder.rebind(action, event, false, bindings_path)
		if error == ERR_ALREADY_EXISTS:
			var conflict := panel.find_child("BindingConflict", true, false) as Control
			if conflict != null:
				conflict.show()
				var swap := conflict.find_child("SwapBindingButton", true, false) as Button
				if swap != null: swap.grab_focus()
		elif error == OK:
			_refresh_controls()

func _on_duplicate_binding_found(_action: StringName, _conflict: StringName, _event: InputEvent) -> void: pass

func _confirm_binding_swap() -> void:
	if pending_action == &"" or pending_event == null: return
	rebinder.rebind(pending_action, pending_event, true)
	pending_action = &""
	pending_event = null
	var conflict := panel.find_child("BindingConflict", true, false) as Control
	if conflict != null: conflict.hide()
	_refresh_controls()

func _cancel_binding() -> void:
	capture_action = &""
	pending_action = &""
	pending_event = null
	var conflict := panel.find_child("BindingConflict", true, false) as Control
	if conflict != null: conflict.hide()
	var status := panel.find_child("BindingStatus", true, false) as Label
	if status != null: status.text = ""

func handle_cancel_input() -> bool:
	var conflict := panel.find_child("BindingConflict", true, false) as Control if panel != null else null
	if capture_action != &"" or (conflict != null and conflict.visible):
		_cancel_binding()
		return true
	return false

func _reset_bindings() -> void:
	rebinder.reset_defaults()
	rebinder.save_bindings(bindings_path)
	_refresh_controls()

func _binding_text(action: StringName) -> String:
	var events := InputMap.action_get_events(action)
	return events[0].as_text().replace(" (Physical)", "") if not events.is_empty() else "UNBOUND"

func _on_back() -> void:
	if preview_active: revert_display_preview()
	if capture_action != &"": _cancel_binding()
	if panel != null: panel.hide()
	var root_ui := get_parent() as FrontEndController
	if root_ui != null: root_ui.go_back()

func _on_device_changed(device: int) -> void:
	if panel == null: return
	var label := panel.find_child("OptionsDeviceLabel", true, false) as Label
	if label != null: label.text = "INPUT: " + ["KEYBOARD / MOUSE", "XBOX CONTROLLER", "PLAYSTATION CONTROLLER"][device]
