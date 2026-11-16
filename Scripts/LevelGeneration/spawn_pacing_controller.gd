extends RefCounted
class_name SpawnPacingController

const MetricsType = preload("res://Scripts/LevelGeneration/spawn_pacing_metrics.gd")
const TuningType = preload("res://Scripts/LevelGeneration/spawn_pacing_tuning.gd")

func get_interval_ticks(metrics: MetricsType, tuning: TuningType) -> int:
	if tuning == null:
		return 60
	var base := maxi(tuning.base_interval_ticks, 1)
	var minimum := maxi(tuning.min_interval_ticks, 1)
	var maximum := maxi(tuning.max_interval_ticks, minimum)
	var style_value := 0.5 if metrics == null else metrics.normalized_style_result()
	var living_value := 0.5 if metrics == null else metrics.normalized_living_enemy_ratio()
	var health_value := 0.5 if metrics == null else metrics.normalized_player_health_ratio()
	var multiplier := _curve_multiplier(tuning.style_curve, style_value)
	multiplier *= _curve_multiplier(tuning.living_enemy_curve, living_value)
	multiplier *= _curve_multiplier(tuning.player_health_curve, health_value)
	var calculated := roundi(float(base) * multiplier)
	return clampi(calculated, minimum, maximum)

func _curve_multiplier(curve: Curve, value: float) -> float:
	if curve == null or curve.point_count == 0:
		return 1.0
	var sample := curve.sample(clampf(value, 0.0, 1.0))
	if not is_finite(sample) or sample <= 0.0:
		return 1.0
	return sample
