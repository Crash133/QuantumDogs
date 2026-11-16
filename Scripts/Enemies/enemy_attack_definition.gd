class_name EnemyAttackDefinition
extends Resource

@export var attack_id: StringName
@export var hit_spec: HitSpec
@export var windup_ticks: int = 20
@export var active_ticks: int = 6
@export var recovery_ticks: int = 24
@export var range_meters: float = 2.0
@export var telegraph_cue: StringName
@export var shape: StringName = &"sphere"
@export var shape_size: Vector3 = Vector3.ONE

func validate() -> Array[String]:
	var errors: Array[String] = []
	if attack_id.is_empty(): errors.append("attack_id is empty")
	if hit_spec == null: errors.append("hit_spec is missing")
	if windup_ticks < 1 or active_ticks < 1 or recovery_ticks < 0: errors.append("invalid attack tick windows")
	if range_meters <= 0.0: errors.append("range_meters must be positive")
	return errors
