class_name FrontEndController
extends Node

signal request_new_game(mode: StringName)
signal request_continue
signal resume_requested
signal quit_to_menu_requested
signal quit_game_requested

var current_screen: StringName = &""
var _screen_nodes: Dictionary = {}
var _history: Array[Dictionary] = []
var _ui_root: Control
var _animation_player: AnimationPlayer
var _prompt: Control
var _menu: Control
var _pause: Control
var _combat_hud: Control
var _continue_button: Button
var _new_game_button: Button
var _continue_reason: Label
var _retry_button: Button
var _pause_status: Label
var _pause_retry: Button
var _pause_retry_action: Callable = Callable()
var _last_requested_action: StringName = &""
var _run_bridge: Node
var _options_controller: Node
var _device_tracker: DeviceTracker
var _combat_hud_presenter: Node
var _selected_mode: StringName = &"Normal"
var quit_application: Callable = Callable()
var _pause_opening := false
var _reduce_motion := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ui_root = get_node_or_null("TitleGarage/UIMain/UI") as Control
	if _ui_root == null:
		push_error("FrontEndRoot is missing TitleGarage/UIMain/UI")
		return
	_animation_player = _ui_root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	_prompt = _ui_root.get_node_or_null("PressAnyButton") as Control
	_menu = _ui_root.get_node_or_null("Menu") as Control
	_pause = _ui_root.get_node_or_null("PauseMenu") as Control
	_combat_hud = _ui_root.get_node_or_null("CombatUI") as Control
	if _prompt == null or _menu == null:
		push_error("Title prototype must contain PressAnyButton and Menu screens")
		return
	_screen_nodes = {
		&"prompt": _prompt,
		&"menu": _menu,
		&"pause": _pause,
		&"combat_hud": _combat_hud,
	}
	_screen_nodes[&"options"] = _ui_root.get_node("OptionsPanel") as Control
	_screen_nodes[&"reward"] = _ui_root.get_node("RewardScreen") as Control
	_screen_nodes[&"difficulty"] = _ui_root.get_node("NewGamePanel") as Control
	_screen_nodes[&"overwrite"] = _ui_root.get_node("ConfirmPanel") as Control
	_screen_nodes[&"defeat"] = _ui_root.get_node("DefeatSummary") as Control
	_build_main_menu_actions()
	_wire_flow_screens()
	_wire_pause_actions()
	_set_default_quit()
	_device_tracker = $DeviceTracker
	_device_tracker.gamepad_disconnected.connect(_on_gamepad_disconnected)
	_options_controller = $OptionsController
	_options_controller.attach_panel(_screen_nodes[&"options"], _device_tracker)
	_reduce_motion = bool(_options_controller.settings.get("reduce_motion", false))
	_options_controller.settings_changed.connect(_on_options_changed)
	_combat_hud_presenter = $CombatHudPresenter
	_combat_hud_presenter.reduce_motion = _reduce_motion
	if _combat_hud != null:
		_combat_hud_presenter.attach_hud(_combat_hud)
	set_run_bridge($RunUiBridge)
	_set_screen(&"prompt")
	if not _reduce_motion and _animation_player != null and _animation_player.has_animation(&"PressIntro"):
		_animation_player.play(&"PressIntro")

func show_screen(screen: StringName, return_focus: Control = null) -> void:
	if not _screen_nodes.has(screen): return
	if current_screen != &"":
		var focus := return_focus
		if focus == null:
			focus = get_viewport().gui_get_focus_owner()
		_history.append({"screen": current_screen, "focus": focus})
	_set_screen(screen, return_focus)

func go_back() -> void:
	if _history.is_empty(): return
	var previous: Dictionary = _history.pop_back()
	var focus := previous.get("focus") as Control
	_set_screen(StringName(previous.get("screen", &"menu")), focus)

func open_pause() -> void:
	if _pause_opening or _pause == null: return
	_pause_opening = true
	get_tree().paused = true
	if _pause != null: _pause.process_mode = Node.PROCESS_MODE_ALWAYS
	show_screen(&"pause")
	_pause_opening = false

func close_pause() -> void:
	if current_screen != &"pause": return
	get_tree().paused = false
	resume_requested.emit()
	go_back()

func _input(event: InputEvent) -> void:
	if current_screen == &"prompt" and _is_entry_press(event):
		get_viewport().set_input_as_handled()
		_open_menu_from_prompt()
		return
	if _is_echo(event): return
	var pause_pressed := InputMap.has_action(&"pause") and event.is_action_pressed(&"pause")
	var cancel_pressed := _is_cancel_press(event)
	if pause_pressed:
		get_viewport().set_input_as_handled()
		if current_screen == &"combat_hud":
			open_pause()
		elif current_screen == &"pause":
			close_pause()
		elif current_screen == &"reward":
			open_pause()
		elif current_screen == &"options" and _options_controller != null and _options_controller.handle_cancel_input():
			pass
		elif current_screen == &"defeat":
			_return_to_menu()
		elif current_screen in [&"difficulty", &"overwrite", &"options"]:
			go_back()
		return
	if not cancel_pressed: return
	get_viewport().set_input_as_handled()
	if current_screen == &"combat_hud":
		open_pause()
	elif current_screen == &"pause":
		close_pause()
	elif current_screen == &"reward":
		open_pause()
	elif current_screen == &"options" and _options_controller != null and _options_controller.handle_cancel_input():
		return
	elif current_screen == &"defeat":
		_return_to_menu()
	else:
		go_back()
		return
	if current_screen in [&"menu", &"difficulty", &"overwrite", &"options", &"pause", &"reward", &"defeat"] and event.is_action_pressed(&"ui_cancel") and not _is_echo(event):
		get_viewport().set_input_as_handled()
		if current_screen == &"pause":
			close_pause()
		elif current_screen == &"reward":
			open_pause()
		else:
			go_back()

func _is_entry_press(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	if event is InputEventMouseButton:
		return event.pressed
	if event is InputEventJoypadButton:
		return event.pressed
	return false

func _is_cancel_press(event: InputEvent) -> bool:
	if InputMap.has_action(&"ui_cancel") and event.is_action_pressed(&"ui_cancel"): return true
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE: return true
	return event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B

func _is_echo(event: InputEvent) -> bool:
	return event is InputEventKey and event.echo

func _open_menu_from_prompt() -> void:
	current_screen = &"menu"
	_history.clear()
	if not _reduce_motion and _animation_player != null and _animation_player.has_animation(&"PressOut"):
		_animation_player.play(&"PressOut")
		await _animation_player.animation_finished
	_set_screen(&"menu")
	if not _reduce_motion and _animation_player != null and _animation_player.has_animation(&"MenuIntro"):
		_animation_player.play(&"MenuIntro")
	_set_default_focus(_menu)

func _set_screen(screen: StringName, focus: Control = null) -> void:
	for node in _screen_nodes.values():
		if node is CanvasItem and is_instance_valid(node): node.hide()
	var target: Control = _screen_nodes.get(screen) as Control
	if target == null:
		current_screen = screen
		return
	target.show()
	current_screen = screen
	# In combat the mouse is captured so moving it orbits the camera; every menu frees it.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if screen == &"combat_hud" else Input.MOUSE_MODE_VISIBLE
	_configure_focus_order(target)
	if focus != null and is_instance_valid(focus) and focus.is_visible_in_tree() and (not focus is BaseButton or not (focus as BaseButton).disabled):
		focus.grab_focus()
	else:
		_set_default_focus(target)

func _set_default_focus(screen: Control) -> void:
	if screen == null: return
	for node in screen.find_children("*", "Control", true, false):
		var control := node as Control
		if control != null and control.focus_mode != Control.FOCUS_NONE and control.is_visible_in_tree() and (not control is BaseButton or not (control as BaseButton).disabled):
			control.grab_focus()
			return

func _configure_focus_order(screen: Control) -> void:
	if screen == null: return
	var focusable: Array[Control] = []
	for node in screen.find_children("*", "Control", true, false):
		var control := node as Control
		if control == null or control.focus_mode == Control.FOCUS_NONE or not control.is_visible_in_tree(): continue
		if control is BaseButton and (control as BaseButton).disabled: continue
		focusable.append(control)
	for index in range(focusable.size()):
		var control := focusable[index]
		var previous := focusable[(index - 1 + focusable.size()) % focusable.size()]
		var next := focusable[(index + 1) % focusable.size()]
		control.focus_previous = control.get_path_to(previous)
		control.focus_next = control.get_path_to(next)
		control.focus_neighbor_top = control.get_path_to(previous)
		control.focus_neighbor_bottom = control.get_path_to(next)

func set_run_bridge(bridge: Node) -> void:
	if is_instance_valid(_run_bridge):
		for signal_name in [&"level_started", &"reward_offered", &"transition_failed", &"run_ended", &"level_transition_committed"]:
			var callback := Callable(self, "_on_bridge_" + String(signal_name))
			if _run_bridge.is_connected(signal_name, callback): _run_bridge.disconnect(signal_name, callback)
			if _run_bridge.get_parent() == self: _run_bridge.queue_free()
	_run_bridge = bridge
	if _run_bridge == null: return
	if _run_bridge.get_parent() == null: add_child(_run_bridge)
	for signal_name in [&"level_started", &"reward_offered", &"transition_failed", &"run_ended", &"level_transition_committed"]:
		var callback := Callable(self, "_on_bridge_" + String(signal_name))
		if _run_bridge.has_signal(signal_name) and not _run_bridge.is_connected(signal_name, callback):
			_run_bridge.connect(signal_name, callback)
	_refresh_continue()

func _set_default_quit() -> void:
	quit_application = func() -> void: get_tree().quit()

func _wire_flow_screens() -> void:
	var normal := find_child("NormalButton", true, false) as Button
	var challenger := find_child("ChallengerButton", true, false) as Button
	var chaos := find_child("ChaosButton", true, false) as Button
	var back := find_child("BackButton", true, false) as Button
	var confirm := find_child("ConfirmButton", true, false) as Button
	var cancel := find_child("CancelButton", true, false) as Button
	var return_menu := find_child("ReturnToMenuButton", true, false) as Button
	if normal != null: normal.pressed.connect(func(): _choose_mode(&"Normal"))
	if challenger != null: challenger.pressed.connect(func(): _choose_mode(&"Challenger"))
	if chaos != null: chaos.pressed.connect(func(): _choose_mode(&"Chaos"))
	if back != null: back.pressed.connect(go_back)
	if confirm != null: confirm.pressed.connect(_confirm_new_game)
	if cancel != null: cancel.pressed.connect(go_back)
	if return_menu != null: return_menu.pressed.connect(_return_to_menu)

func _choose_mode(mode: StringName) -> void:
	_selected_mode = mode
	if _run_bridge != null and _run_bridge.has_method("continue_available") and _run_bridge.continue_available():
		show_screen(&"overwrite")
	else:
		_start_selected_run()

func _confirm_new_game() -> void:
	_start_selected_run()

func _start_selected_run() -> void:
	_last_requested_action = &"new_game"
	if _run_bridge == null or not _run_bridge.has_method("start_new_run"):
		_set_status("Run services are unavailable.")
		return
	var started: bool = _run_bridge.start_new_run(_selected_mode)
	if not started:
		_set_status(_bridge_error("Could not start this run."))
		show_screen(&"menu")
		return
	_history.clear()
	_set_title_visible(false)
	show_screen(&"combat_hud")

func _request_continue() -> void:
	_last_requested_action = &"continue"
	if _run_bridge == null or not _run_bridge.has_method("continue_run"): return
	if not _run_bridge.continue_run():
		_set_status(_bridge_error("Continue is unavailable."))
		_refresh_continue()
		return
	_history.clear()
	_set_title_visible(false)
	show_screen(&"combat_hud")

func handle_run_ended(summary: Dictionary) -> void:
	var depth := find_child("DepthLabel", true, false) as Label
	var points := find_child("StylePointsLabel", true, false) as Label
	if depth != null: depth.text = "DEPTH REACHED: %s" % str(summary.get("depth", 0))
	if points != null: points.text = "STYLE POINTS EARNED: %s" % str(summary.get("style_points_earned", 0.0))
	_refresh_continue()
	get_tree().paused = false
	_history.clear()
	show_screen(&"defeat")

func _return_to_menu() -> void:
	if _run_bridge != null and _run_bridge.has_method("leave_run"):
		var error: Error = _run_bridge.leave_run()
		if error != OK:
			_set_pause_error(_bridge_error("Could not leave the run."), _return_to_menu)
			return
	_clear_pause_error()
	get_tree().paused = false
	_set_title_visible(true)
	_history.clear()
	_refresh_continue()
	show_screen(&"menu")

func _quit_game() -> void:
	if _run_bridge != null and _run_bridge.has_method("leave_run"):
		var error: Error = _run_bridge.leave_run()
		if error != OK:
			if current_screen == &"pause": _set_pause_error(_bridge_error("Could not save the current run state."), _quit_game)
			else: _set_status(_bridge_error("Could not save the current run state."))
			return
	_clear_pause_error()
	get_tree().paused = false
	quit_game_requested.emit()
	if quit_application.is_valid(): quit_application.call()

func _bridge_error(fallback: String) -> String:
	if _run_bridge != null and "last_flow_error" in _run_bridge and not String(_run_bridge.last_flow_error).is_empty():
		return String(_run_bridge.last_flow_error)
	return fallback

func _set_status(message: String) -> void:
	if _continue_reason != null:
		_continue_reason.text = message
		_continue_reason.visible = not message.is_empty()
	if _retry_button != null: _retry_button.visible = not message.is_empty()

func _retry_menu_action() -> void:
	if _run_bridge == null: return
	if _run_bridge.has_method("prepare_menu") and _run_bridge.prepare_menu() != OK:
		_set_status(_bridge_error("Could not reconcile the active run."))
		return
	_set_status("")
	_refresh_continue()
	if _last_requested_action == &"continue": _request_continue()
	elif _last_requested_action == &"new_game": _start_selected_run()

func _refresh_continue() -> void:
	if _continue_button == null: return
	var available: bool = _run_bridge != null and _run_bridge.has_method("continue_available") and bool(_run_bridge.continue_available())
	_continue_button.visible = available
	_continue_button.disabled = false

func _set_title_visible(is_visible: bool) -> void:
	var garage := get_node_or_null("TitleGarage") as Node3D
	if garage != null: garage.visible = is_visible

func _on_bridge_level_started(_depth: int, _context: StageContext) -> void:
	_set_title_visible(false)
	if _combat_hud_presenter != null and _run_bridge != null:
		for property in _run_bridge.get_property_list():
			if property.name == "controller":
				var run: RunController = _run_bridge.get("controller")
				if run != null: _combat_hud_presenter.bind(run.player, run.style_system, run, _device_tracker)
				break
	if current_screen in [&"menu", &"difficulty", &"overwrite"]: show_screen(&"combat_hud")

func _on_bridge_reward_offered(_offer: Dictionary) -> void:
	if _run_bridge != null:
		var run: RunController
		for property in _run_bridge.get_property_list():
			if property.name == "controller":
				run = _run_bridge.get("controller")
				break
		if run != null:
			var reward_screen: Control = _screen_nodes[&"reward"] as Control
			reward_screen.call("bind", run.service, run.coordinator, run)
			reward_screen.call("present", _offer, run.service.profile_snapshot())
			if not reward_screen.is_connected("pause_requested", open_pause): reward_screen.connect("pause_requested", open_pause)
			if not reward_screen.is_connected("closed", _on_reward_closed): reward_screen.connect("closed", _on_reward_closed)
	show_screen(&"reward")

func _on_bridge_transition_failed(error: String) -> void:
	_set_status(error)
	if current_screen == &"reward":
		var reward_screen: Control = _screen_nodes[&"reward"] as Control
		reward_screen.call("set_transition_error", error)
	if current_screen == &"combat_hud": open_pause()

func _on_bridge_run_ended(summary: Dictionary) -> void:
	handle_run_ended(summary)

func _on_bridge_level_transition_committed(_result: Resource, _context: StageContext) -> void:
	_on_reward_closed()

func _on_reward_closed() -> void:
	get_tree().paused = false
	show_screen(&"combat_hud")

func _on_gamepad_disconnected(_device_id: int) -> void:
	get_tree().paused = true
	if current_screen != &"pause": open_pause()
	_set_default_focus(_pause)

func _on_options_changed(settings: Dictionary) -> void:
	_reduce_motion = bool(settings.get("reduce_motion", false))
	if _combat_hud_presenter != null: _combat_hud_presenter.reduce_motion = _reduce_motion

func _build_main_menu_actions() -> void:
	var column := _menu.get_node_or_null("PanelContainer/MarginContainer/VBoxContainer") as VBoxContainer
	if column == null: return
	_continue_button = column.get_node_or_null("ContinueButton") as Button
	_new_game_button = column.get_node_or_null("NewGameButton") as Button
	var options_button := column.get_node_or_null("OptionsButton") as Button
	var quit_button := column.get_node_or_null("QuitButton") as Button
	if _continue_button != null:
		_continue_button.focus_mode = Control.FOCUS_ALL
		_continue_button.hide()
		var continue_label := _continue_button.get_node_or_null("Label") as Label
		if continue_label != null: continue_label.text = "CONTINUE"
		_continue_button.pressed.connect(func(): request_continue.emit(); _request_continue())
		_continue_reason = column.get_node("ContinueReason") as Label
		_retry_button = column.get_node("RetryButton") as Button
		_retry_button.pressed.connect(_retry_menu_action)
	if _new_game_button != null:
		_new_game_button.focus_mode = Control.FOCUS_ALL
		var label := _new_game_button.get_node_or_null("Label") as Label
		if label != null: label.text = "NEW GAME"
		_new_game_button.pressed.connect(func(): show_screen(&"difficulty", _new_game_button))
	if options_button != null:
		options_button.focus_mode = Control.FOCUS_ALL
		options_button.pressed.connect(_open_options.bind(options_button))
	if quit_button != null:
		quit_button.focus_mode = Control.FOCUS_ALL
		quit_button.pressed.connect(_quit_game)
	_configure_focus_order(_menu)

func _wire_pause_actions() -> void:
	if _pause == null: return
	var buttons := _pause.find_children("*", "Button", true, false)
	for node in buttons:
		var button := node as Button
		if button != null: button.focus_mode = Control.FOCUS_ALL
	var resume := _pause.find_child("ResumeButton", true, false) as Button
	var options := _pause.find_child("OptionsButton", true, false) as Button
	var menu := _pause.find_child("QuitToMenuButton", true, false) as Button
	var quit := _pause.find_child("QuitGameButton", true, false) as Button
	var column := _pause.find_child("VBoxContainer", true, false) as VBoxContainer
	if column != null:
		_pause_status = column.get_node("PauseStatus") as Label
		_pause_retry = column.get_node("PauseRetryButton") as Button
		_pause_retry.pressed.connect(_retry_pause_action)
	if resume != null: resume.pressed.connect(close_pause)
	if options != null: options.pressed.connect(_open_options.bind(options))
	if menu != null: menu.pressed.connect(func(): quit_to_menu_requested.emit(); _return_to_menu())
	if quit != null: quit.pressed.connect(_quit_game)

func _set_pause_error(message: String, retry_action: Callable) -> void:
	if _pause_status != null: _pause_status.text = message; _pause_status.show()
	if _pause_retry != null: _pause_retry.show()
	_pause_retry_action = retry_action
	show_screen(&"pause")

func _clear_pause_error() -> void:
	if _pause_status != null: _pause_status.hide()
	if _pause_retry != null: _pause_retry.hide()
	_pause_retry_action = Callable()

func _retry_pause_action() -> void:
	if _pause_retry_action.is_valid(): _pause_retry_action.call()

func _open_options(invoking: Control) -> void:
	if _options_controller != null and _run_bridge != null:
		for property in _run_bridge.get_property_list():
			if property.name == "controller":
				var run: RunController = _run_bridge.get("controller")
				if run != null: _options_controller.set_combat_controller(run.player.combat_controller)
				break
	show_screen(&"options", invoking)
