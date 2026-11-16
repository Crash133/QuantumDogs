class_name ComboCancelWindow
extends Resource

enum Action { DODGE, BLOCK_PARRY, SWITCH, JUMP, EXECUTE }

@export var action: Action = Action.DODGE
## First inclusive attack tick on which this action may cancel.
@export_range(0, 3600, 1, "suffix:ticks @60Hz") var start_tick: int = 0
## Last inclusive attack tick on which this action may cancel.
@export_range(0, 3600, 1, "suffix:ticks @60Hz") var end_tick: int = 0
@export var enabled: bool = true

func contains(tick: int) -> bool:
	return enabled and tick >= start_tick and tick <= end_tick
