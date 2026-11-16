class_name StatUpgradeDefinition
extends Resource

@export var stat_id: StringName
@export var max_level: int = 0
@export var cost_by_level: PackedFloat32Array = []

func is_valid() -> bool:
	if stat_id == &"" or max_level <= 0 or cost_by_level.size() != max_level:
		return false
	var previous := 0.0
	for cost in cost_by_level:
		if not is_finite(cost) or cost <= previous:
			return false
		previous = cost
	return true
