class_name SlicedArenaGeneration
extends Node

## Non-blocking arena generation for Progression's submitter contract. Runs one
## job at a time on the main thread, yielding to the next frame whenever the
## frame budget is spent (ArenaGenerator.generate_sliced). Threads are not used:
## tiles create physics shapes, which is unsafe off the main thread with this
## project's physics settings.

@export var frame_budget_usec: int = 4000
## Copied onto every request (see ArenaGenerationRequest.max_concurrent).
var max_concurrent: int = 0
var _queue: Array = []
var _busy := false
var _slice_started := 0

## payload: ProgressionRuntimeAdapter.make_arena_request_payload(); on_done(request_id, result).
func submit(payload: Dictionary, request_id: int, on_done: Callable) -> void:
	_queue.append([payload, request_id, on_done])
	if not _busy:
		_run_next()

func is_busy() -> bool:
	return _busy

## Progression sends `arena_profile`; Level Generation's request field is `profile`.
static func make_request(payload: Dictionary) -> ArenaGenerationRequest:
	var profile = payload.get("arena_profile")
	var encounter = payload.get("encounter")
	if not profile is ArenaProfile or not encounter is EncounterDefinition or not payload.get("run_seed") is int or not payload.get("ascent_depth") is int:
		return null
	var request := ArenaGenerationRequest.new()
	request.run_seed = payload.run_seed
	request.ascent_depth = payload.ascent_depth
	request.profile = profile
	request.encounter = encounter
	return request

func _run_next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var job: Array = _queue.pop_front()
	var request := make_request(job[0])
	var result: ArenaGenerationResult
	if request == null:
		result = ArenaGenerationResult.new()
		result.error = "Arena payload needs ArenaProfile arena_profile, EncounterDefinition encounter, int run_seed/ascent_depth"
	else:
		request.max_concurrent = max_concurrent
		var first_frame := Engine.get_process_frames()
		_slice_started = Time.get_ticks_usec()
		result = await ArenaGenerator.new().generate_sliced(request, _slice)
		result.diagnostics["frames_spanned"] = Engine.get_process_frames() - first_frame
	if not is_inside_tree():
		if is_instance_valid(result.root):
			result.root.free()
		return
	job[2].call(job[1], result)
	_run_next()

func _slice() -> void:
	if Time.get_ticks_usec() - _slice_started < frame_budget_usec:
		return
	await get_tree().process_frame
	_slice_started = Time.get_ticks_usec()
