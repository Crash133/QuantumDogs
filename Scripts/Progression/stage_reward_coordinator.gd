class_name StageRewardCoordinator
extends RefCounted

signal show_reward(offer: Dictionary)
signal transition_ready(result: Resource, next_context: StageContext)
signal transition_failed(error: String)
enum State { IDLE, CINEMATIC, REWARD, WAITING_FOR_ARENA, READY_TO_TRANSITION, FAILED }
static var _request_serial := 0
var service: ProgressionService
var state := State.IDLE
var request_id := 0
var current_offer: Dictionary = {}
var arena_result: Resource
var next_context: StageContext
var _selection_ready := false
var _cinematic_ready := false
var _completion_received := false
var _cleared_depth := -1

## Cinematic consumer contract: play_downed(), completed signal.
## Generator consumer contract: request_arena_generation(context, request_id).
func begin_stage_clear(context: StageContext, runtime_adapter, cinematic: Node) -> void:
	if service == null or service.run.ended or context == null or not is_instance_valid(cinematic): return
	if state not in [State.IDLE, State.READY_TO_TRANSITION, State.FAILED]: return
	if state != State.FAILED and _cleared_depth == service.run.ascent_depth: return
	if context.ascent_depth != service.run.ascent_depth + 1: return
	if not cinematic.has_signal("completed") or not cinematic.has_method("play_downed"):
		transition_failed.emit("Cinematic requires completed signal and play_downed()")
		return
	_cleared_depth = service.run.ascent_depth
	_request_serial += 1
	request_id = _request_serial
	next_context = context.duplicate(true)
	arena_result = null
	_selection_ready = service.run.reward_resolved
	_cinematic_ready = false
	_completion_received = false
	state = State.CINEMATIC
	if not service.reward_selected.is_connected(on_reward_selection_complete): service.reward_selected.connect(on_reward_selection_complete)
	if not service.run_ended.is_connected(cancel): service.run_ended.connect(cancel)
	cinematic.connect("completed", _on_cinematic_completed.bind(request_id), CONNECT_ONE_SHOT)
	# Both calls occur in this tick; synchronous generation also sees initialized state.
	runtime_adapter.request_arena_generation(next_context.duplicate(true), request_id)
	cinematic.call("play_downed")

func _on_cinematic_completed(id: int) -> void:
	if id != request_id or state != State.CINEMATIC or service.run.ended: return
	_cinematic_ready = true
	state = State.REWARD
	if service.run.reward_resolved:
		# Generation retry preserves this stage's accepted reward and deck.
		_selection_ready = true
		current_offer["selection_complete"] = true
	else:
		current_offer = service.build_reward_offer(service.run.get_weapon_draft_band(service.catalog) != &"")
	show_reward.emit(current_offer.duplicate(true))
	_try_transition()

func on_reward_selection_complete() -> void:
	if state not in [State.REWARD, State.WAITING_FOR_ARENA] or not service.run.reward_resolved: return
	_selection_ready = true
	if arena_result == null: state = State.WAITING_FOR_ARENA
	_try_transition()

func on_generation_completed(id: int, result: Resource) -> void:
	if id != request_id or _completion_received or state not in [State.CINEMATIC, State.REWARD, State.WAITING_FOR_ARENA]: return
	_completion_received = true
	if result == null or result.get("success") != true or not is_instance_valid(result.get("root")):
		state = State.FAILED
		transition_failed.emit("Invalid arena result" if result == null else str(result.get("error")))
		return
	arena_result = result
	_try_transition()

func _try_transition() -> void:
	if service.run.ended or state in [State.READY_TO_TRANSITION, State.FAILED]: return
	if _cinematic_ready and _selection_ready and arena_result != null:
		state = State.READY_TO_TRANSITION
		transition_ready.emit(arena_result, next_context.duplicate(true))

func cancel() -> void:
	state = State.FAILED
	request_id = -1
	transition_failed.emit("Run ended")
