extends Resource
class_name SpawnPacingTuning

@export_range(1, 100000, 1) var base_interval_ticks: int = 60
@export_range(1, 100000, 1) var min_interval_ticks: int = 1
@export_range(1, 100000, 1) var max_interval_ticks: int = 600
@export var style_curve: Curve
@export var living_enemy_curve: Curve
@export var player_health_curve: Curve

func _init() -> void:
	if style_curve == null:
		style_curve = _neutral_curve()
	if living_enemy_curve == null:
		living_enemy_curve = _neutral_curve()
	if player_health_curve == null:
		player_health_curve = _neutral_curve()

func _neutral_curve() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 1.0))
	return curve
