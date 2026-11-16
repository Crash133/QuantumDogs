class_name ProgressionRewardViewModel
extends RefCounted

signal purchase_requested(stat_id: StringName)
signal selection_submitted(ids: Array[StringName])
signal closed
signal changed
var offer: Dictionary = {}
var snapshot: Dictionary = {}
var error_message := ""
var _service: ProgressionService
var _coordinator: StageRewardCoordinator
var _controller: RunController

func present(value: Dictionary, profile_snapshot: Dictionary) -> void:
	offer = value.duplicate(true)
	snapshot = profile_snapshot.duplicate(true)
	error_message = ""
	changed.emit()

func bind_service(service: ProgressionService) -> void:
	if _service != null and _service.profile_changed.is_connected(_refresh): _service.profile_changed.disconnect(_refresh)
	_service = service
	_service.profile_changed.connect(_refresh)
	if not purchase_requested.is_connected(_purchase): purchase_requested.connect(_purchase)
	if not selection_submitted.is_connected(_select): selection_submitted.connect(_select)

func _refresh(value: Dictionary) -> void:
	snapshot = value.duplicate(true)
	changed.emit()

func bind_coordinator(coordinator: StageRewardCoordinator) -> void:
	_coordinator = coordinator

func bind_controller(controller: RunController) -> void:
	if _controller != null and _controller.level_transition_committed.is_connected(_close_on_transition):
		_controller.level_transition_committed.disconnect(_close_on_transition)
	_controller = controller
	if _controller != null: _controller.level_transition_committed.connect(_close_on_transition)

func _close_on_transition(_result: Resource, _context: StageContext) -> void:
	closed.emit()

func purchase_stat(stat_id: StringName) -> void:
	purchase_requested.emit(stat_id)

func submit_selection(ids: Array[StringName]) -> void:
	selection_submitted.emit(ids.duplicate())

func _purchase(id: StringName) -> void:
	var result := _service.purchase_stat(id)
	error_message = result.get("error", "")
	if result.get("save_error", OK) != OK: error_message = "Profile save failed; purchases remain in memory"
	changed.emit()

func _select(ids: Array[StringName]) -> void:
	# Set before selecting: the transition can fail synchronously inside
	# select_reward_ids, and its error must not be overwritten afterwards.
	error_message = "Waiting for arena"
	if _service.select_reward_ids(ids, offer):
		offer["selection_complete"] = true
	else:
		error_message = "Select the required distinct rewards"
	changed.emit()
