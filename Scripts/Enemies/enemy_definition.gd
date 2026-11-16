class_name EnemyDefinition
extends Resource

@export var enemy_id: StringName
@export var role: StringName = &"common"
@export var scene: PackedScene
@export var max_health: float = 100.0
@export var move_speed: float = 3.0
@export var engagement_range: float = 2.0
@export var hover_height: float = 2.0
@export var spawn_tags: Array[StringName] = []
@export var attack: EnemyAttackDefinition
@export_range(0.0, 1.0) var parry_chance: float = 0.0
@export var parry_cooldown_ticks: int = 60

func validate() -> Array[String]:
	var errors: Array[String] = []
	if enemy_id.is_empty(): errors.append("enemy_id is empty")
	if role not in [&"common", &"drone", &"elite"]: errors.append("unsupported role")
	if scene == null: errors.append("scene is missing")
	if max_health <= 0.0 or move_speed < 0.0: errors.append("invalid health or speed")
	if role == &"drone" and hover_height <= 0.0: errors.append("drone hover_height must be positive")
	if attack == null: errors.append("attack is missing")
	elif not attack.validate().is_empty(): errors.append_array(attack.validate())
	if parry_cooldown_ticks < 0: errors.append("invalid parry cooldown")
	return errors
