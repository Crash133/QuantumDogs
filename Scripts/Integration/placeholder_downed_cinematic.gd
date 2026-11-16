class_name PlaceholderDownedCinematic
extends Node

## Satisfies StageRewardCoordinator's cinematic contract (play_downed(), completed).
## shortcut: timer only, no camera/animation; replace with Presentation's downed cinematic.

signal completed

@export var duration_ticks: int = 90
var played_count: int = 0
var _ticks_left: int = -1

func play_downed() -> void:
	played_count += 1
	_ticks_left = duration_ticks

func _physics_process(_delta: float) -> void:
	if _ticks_left < 0:
		return
	_ticks_left -= 1
	if _ticks_left <= 0:
		_ticks_left = -1
		completed.emit()
