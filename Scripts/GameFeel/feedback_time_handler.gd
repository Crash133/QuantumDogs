class_name FeedbackTimeHandler
extends Node

## The single owner of whole-game hit stop. One lease at a time: it remembers the
## time scale it found, ends on a wall clock (so a pause cannot strand it) and
## restores that scale only if nobody else changed it meanwhile.

## Longest total stop, however many cues overlap.
@export_range(0.05, 1.0, 0.01, "suffix:s") var max_lease_seconds: float = 0.25
## Same correlation key inside this window adds no second stop.
@export_range(0.0, 1.0, 0.01, "suffix:s") var dedupe_window_seconds: float = 0.12

## Millisecond clock; replaced in tests. Must not be scaled by Engine.time_scale.
var clock: Callable = Time.get_ticks_msec

var _active: bool = false
var _previous_scale: float = 1.0
var _lease_scale: float = 1.0
var _start_msec: int = 0
var _end_msec: int = 0
var _seen: Dictionary = {}

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # Keep running while the tree is paused.

func is_stopping() -> bool:
	return _active

## Returns true when a stop was started or extended.
func request_stop(duration_seconds: float, scale: float, correlation_key: StringName) -> bool:
	if duration_seconds <= 0.0:
		return false
	var now: int = clock.call()
	_prune(now)
	if correlation_key != &"":
		if _seen.has(correlation_key):
			return false
		_seen[correlation_key] = now
	var length_ms := int(duration_seconds * 1000.0)
	scale = clampf(scale, 0.0, 1.0)
	if not _active:
		_active = true
		_previous_scale = Engine.time_scale
		_start_msec = now
		_end_msec = now + length_ms
		_lease_scale = minf(scale, _previous_scale)
		Engine.time_scale = _lease_scale
		_cap_end()
		return true
	_end_msec = maxi(_end_msec, now + length_ms)
	_cap_end()
	# Only touch the scale while we still own it; the strongest overlap wins.
	if is_equal_approx(Engine.time_scale, _lease_scale) and scale < _lease_scale:
		_lease_scale = scale
		Engine.time_scale = scale
	return true

func clear() -> void:
	_release()
	_seen.clear()

func _process(_delta: float) -> void:
	var _probe := ScriptCostProbe.start()
	_process_body(_delta)
	ScriptCostProbe.stop(&"feel.time", _probe)

func _process_body(_delta: float) -> void:
	if _active and int(clock.call()) >= _end_msec:
		_release()

func _exit_tree() -> void:
	_release()

func _cap_end() -> void:
	_end_msec = mini(_end_msec, _start_msec + int(max_lease_seconds * 1000.0))

func _release() -> void:
	if not _active:
		return
	_active = false
	# A different owner changed the scale during the lease: leave theirs alone.
	if is_equal_approx(Engine.time_scale, _lease_scale):
		Engine.time_scale = _previous_scale

func _prune(now: int) -> void:
	var window := int(dedupe_window_seconds * 1000.0)
	for key in _seen.keys():
		if now - int(_seen[key]) > window:
			_seen.erase(key)
