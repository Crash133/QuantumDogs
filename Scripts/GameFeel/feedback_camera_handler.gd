class_name FeedbackCameraHandler
extends Node

## Applies camera trauma through the rig's CameraShake. The only combat-impact
## caller of CameraShake.add_shake(). One shake per correlation key and window.

@export_range(0.0, 1.0, 0.01, "suffix:s") var dedupe_window_seconds: float = 0.12
## Multiplier applied to every trauma value (a later Options hook).
@export_range(0.0, 1.0, 0.05) var trauma_scale: float = 1.0

## Millisecond clock; replaced in tests.
var clock: Callable = Time.get_ticks_msec

var _rig: CameraRig
var _reduced_motion: bool = false
var _seen: Dictionary = {}

func bind(rig: CameraRig) -> void:
	_rig = rig
	_seen.clear()

func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled

## Returns true when trauma was actually added.
func apply(trauma: float, correlation_key: StringName) -> bool:
	if _reduced_motion or trauma <= 0.0 or not is_instance_valid(_rig):
		return false
	var shaker := _rig.get_shaker()
	if not is_instance_valid(shaker):
		return false
	var now: int = clock.call()
	var window := int(dedupe_window_seconds * 1000.0)
	for key in _seen.keys():
		if now - int(_seen[key]) > window:
			_seen.erase(key)
	if correlation_key != &"":
		if _seen.has(correlation_key):
			return false
		_seen[correlation_key] = now
	shaker.add_shake(clampf(trauma * trauma_scale, 0.0, 1.0))
	return true
