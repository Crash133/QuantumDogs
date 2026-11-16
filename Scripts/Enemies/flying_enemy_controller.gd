class_name FlyingEnemyController
extends EnemyRoleController

func _step_movement(allow_attack: bool = true) -> void:
	if not is_instance_valid(player_node): return
	var to_player := player_node.global_position - enemy.global_position
	to_player.y = 0.0
	var distance := to_player.length()
	if distance < definition.engagement_range * 0.8:
		enemy.direction = -to_player.normalized()
	elif distance > definition.engagement_range:
		enemy.direction = to_player.normalized()
	else:
		enemy.direction = Vector3(-to_player.z, 0.0, to_player.x).normalized()
		if allow_attack:
			request_attack()
