class_name DifficultyProfile
extends Resource

@export var mode: StringName
@export var band: StringName
@export var depth_start: int = 0
@export var base_parameters: Dictionary = {}
@export var per_depth_delta: Dictionary = {}
@export var max_parameters: Dictionary = {}

func is_valid() -> bool:
	if depth_start < 0 or base_parameters.is_empty() or base_parameters.size() != per_depth_delta.size() or base_parameters.size() != max_parameters.size():
		return false
	for key in base_parameters:
		for values in [base_parameters, per_depth_delta, max_parameters]:
			if not values.has(key) or not (values[key] is float or values[key] is int) or not is_finite(float(values[key])):
				return false
		if per_depth_delta[key] < 0 or max_parameters[key] < base_parameters[key]:
			return false
	return true

func get_parameters_at(depth: int) -> Dictionary:
	var result := {}
	for key in base_parameters:
		result[key] = minf(base_parameters[key] + maxi(0, depth - depth_start) * per_depth_delta[key], max_parameters[key])
	return result
