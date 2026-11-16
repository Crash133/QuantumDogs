extends RefCounted
class_name SpawnPacingMetrics

@export var style_result: float = 0.5
@export var living_enemy_ratio: float = 0.5
@export var player_health_ratio: float = 0.5

func normalized_style_result() -> float:
	return _normalized_or_neutral(style_result)

func normalized_living_enemy_ratio() -> float:
	return _normalized_or_neutral(living_enemy_ratio)

func normalized_player_health_ratio() -> float:
	return _normalized_or_neutral(player_health_ratio)

func _normalized_or_neutral(value: float) -> float:
	if not is_finite(value) or value < 0.0 or value > 1.0:
		return 0.5
	return value
