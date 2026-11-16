class_name RewardScreen
extends Control

signal closed
signal pause_requested

var view_model := ProgressionRewardViewModel.new()
var controller: RunController
var _panel: Control
var _status: Label
var _retry: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = find_child("ProgressionRewardPanel", true, false) as Control
	_status = find_child("RewardStatus", true, false) as Label
	_retry = find_child("RetryButton", true, false) as Button
	if _retry != null: _retry.pressed.connect(_retry_transition)
	var pause := find_child("RewardPauseButton", true, false) as Button
	if pause != null: pause.pressed.connect(func(): pause_requested.emit())
	view_model.changed.connect(_refresh)
	view_model.closed.connect(func(): closed.emit())
	var title := find_child("Title", true, false) as Label
	if title != null: RewardStyle.label(title, 30, RewardStyle.PALE)
	if _status != null: RewardStyle.label(_status, 14, RewardStyle.CYAN, false)
	for button_name in ["RetryButton", "RewardPauseButton"]:
		var action := find_child(button_name, true, false) as Button
		if action != null:
			action.add_theme_font_override("font", RewardStyle.FONT)
			action.add_theme_font_size_override("font_size", 14)
			action.add_theme_stylebox_override("normal", RewardStyle.box(RewardStyle.PANEL, Color(0.25, 0.9, 1.0, 0.4)))
			action.add_theme_stylebox_override("hover", RewardStyle.box(RewardStyle.PANEL_RAISED, RewardStyle.CYAN))
	if _panel != null: _panel.call("set_view_model", view_model)

func bind(service: ProgressionService, coordinator: StageRewardCoordinator, run_controller: RunController) -> void:
	controller = run_controller
	view_model.bind_service(service)
	view_model.bind_coordinator(coordinator)
	view_model.bind_controller(run_controller)

func present(offer: Dictionary, profile_snapshot: Dictionary) -> void:
	view_model.present(offer, profile_snapshot)
	if _panel != null: _panel.call("set_view_model", view_model)
	_refresh()

func set_transition_error(error: String) -> void:
	view_model.error_message = error
	if _retry != null: _retry.show()
	_refresh()

func _refresh() -> void:
	if not is_node_ready(): return
	if _status != null:
		_status.text = view_model.error_message if not view_model.error_message.is_empty() else ("CHOICE LOCKED • WAITING FOR ARENA" if view_model.offer.get("selection_complete", false) else "SELECT YOUR UPGRADE")
	if _retry != null:
		_retry.visible = not view_model.error_message.is_empty() and controller != null
	if _panel != null: _panel.call("refresh")

func _retry_transition() -> void:
	if controller == null: return
	if _status != null: _status.text = "RETRYING ARENA GENERATION…"
	if _retry != null: _retry.disabled = true
	controller.retry_stage_clear()

func set_retry_available(available: bool) -> void:
	if _retry != null:
		_retry.visible = available
		_retry.disabled = false

