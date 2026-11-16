extends Resource
class_name StyleAward

@export var amount: float = 0.0
@export var rank_index: int = -1
var _action_counts: Array[Dictionary] = []
var action_counts: Array[Dictionary]:
	get:
		return _action_counts.duplicate(true)
	set(value):
		_action_counts = value.duplicate(true)
