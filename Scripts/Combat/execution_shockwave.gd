class_name ExecutionShockwave
extends RefCounted

## Applies the one-shot no-damage pulse at a confirmed execution contact.
## Enemy reactions tick on their existing local clocks; this utility owns no
## persistent state and never changes global time or shared tuning Resources.

static func apply(tree: SceneTree, center: Vector3, player: Object, victim: Object, tuning: CombatTuning) -> int:
	if tree == null or tuning == null or not center.is_finite() or tuning.execution_shockwave_radius <= 0.0:
		return 0
	var affected := 0
	var radius_squared := tuning.execution_shockwave_radius * tuning.execution_shockwave_radius
	var stun_seconds := maxf(0.0, tuning.execution_shockwave_stun_seconds)
	var lock_seconds := maxf(stun_seconds, tuning.execution_shockwave_execution_lock_seconds)
	for candidate: Node in tree.get_nodes_in_group("enemy_combatants"):
		if candidate == player or candidate == victim or not is_instance_valid(candidate) or not candidate is Node3D:
			continue
		var enemy := candidate as Node3D
		if enemy.is_queued_for_deletion() or not enemy.has_method("is_alive") or not bool(enemy.call("is_alive")):
			continue
		if enemy.global_position.distance_squared_to(center) > radius_squared:
			continue
		if not enemy.has_method("apply_execution_shockwave"):
			continue
		enemy.call("apply_execution_shockwave", stun_seconds, lock_seconds, maxf(0.0, tuning.execution_shockwave_slam_speed))
		affected += 1
	_spawn_visual(tree, center, tuning)
	return affected

static func _spawn_visual(tree: SceneTree, center: Vector3, tuning: CombatTuning) -> void:
	if tuning.execution_shockwave_vfx == null:
		return
	var parent := tree.current_scene if is_instance_valid(tree.current_scene) else tree.root
	if parent == null:
		return
	var effect := tuning.execution_shockwave_vfx.instantiate() as Node3D
	if effect == null:
		return
	parent.add_child(effect)
	effect.global_position = center
	if effect.has_method("configure"):
		effect.call("configure", tuning.execution_shockwave_radius)
