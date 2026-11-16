class_name TargetingService
extends Node3D

@export var tuning: CombatTuning
@export var target_group: StringName = &"combatants"

var locked_target: Node3D

func _ready() -> void:
	add_to_group("targeting_services")
	process_physics_priority = -2

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(locked_target):
		locked_target = null
		return
	var max_range := tuning.lock_range if tuning != null else 20.0
	if not locked_target.is_inside_tree() or locked_target.is_queued_for_deletion() or (locked_target.has_method("is_alive") and not locked_target.is_alive()) or locked_target.global_position.distance_squared_to(global_position) > max_range * max_range:
		clear_lock()

func toggle_lock(origin: Vector3, facing: Vector3) -> Node3D:
	var candidates := _candidates(origin, facing, true)
	if candidates.is_empty():
		locked_target = null
		return null
	if locked_target != null and is_instance_valid(locked_target):
		var current_index := candidates.find(locked_target)
		locked_target = candidates[(current_index + 1) % candidates.size()] if current_index >= 0 else candidates[0]
	else:
		locked_target = candidates[0]
	return locked_target

func clear_lock() -> void:
	locked_target = null

func find_best_lockable(origin: Vector3, facing: Vector3) -> Node3D:
	var candidates := _candidates(origin, facing, true)
	return candidates[0] if not candidates.is_empty() else null

func find_executable(origin: Vector3, facing: Vector3) -> Node3D:
	var candidates := _candidates(origin, facing, false) # knocked-down commons are not lockable
	if is_instance_valid(locked_target) and locked_target in candidates:
		candidates.erase(locked_target)
		candidates.push_front(locked_target)
	for candidate in candidates:
		if candidate.has_method("is_executable"):
			if candidate.is_executable():
				return candidate
			continue
		if not bool(candidate.get("elite")) or not candidate.has_method("is_staggered") or not candidate.is_staggered():
			continue
		if candidate.has_method("is_execution_shockwave_locked") and bool(candidate.call("is_execution_shockwave_locked")):
			continue
		var meter: HeatMeter = candidate.get_heat_meter() if candidate.has_method("get_heat_meter") else null
		if meter != null and meter.value >= meter.maximum:
			return candidate
	return null

## Closest live combatant whose center is within twice its authored body radius.
## Generic/debug combatants without a radius use the project's 0.45 m enemy default.
func find_nearby_lunge_target(origin: Vector3, radius_multiplier: float = 2.0) -> Node3D:
	var best: Node3D
	var best_distance_squared := INF
	for node in get_tree().get_nodes_in_group(target_group):
		if not node is Node3D or node == self or node.is_queued_for_deletion():
			continue
		if node.has_method("is_alive") and not bool(node.call("is_alive")):
			continue
		var candidate := node as Node3D
		var radius := _body_radius(candidate) * maxf(0.0, radius_multiplier)
		var offset := candidate.global_position - origin
		offset.y = 0.0
		var distance_squared := offset.length_squared()
		if distance_squared > radius * radius:
			continue
		if distance_squared < best_distance_squared or (is_equal_approx(distance_squared, best_distance_squared) and (best == null or candidate.name < best.name)):
			best = candidate
			best_distance_squared = distance_squared
	return best

func _body_radius(candidate: Node3D) -> float:
	if candidate.has_method("get_combat_hurtbox_radius"):
		return maxf(0.0, float(candidate.call("get_combat_hurtbox_radius")))
	var authored: Variant = candidate.get("combat_hurtbox_radius")
	if authored != null:
		return maxf(0.0, float(authored))
	for child in candidate.get_children():
		if child is HurtboxProxy:
			return child.radius
	return 0.45

## Live target in range whose combat centre is drawn closest to the middle of
## the camera's view. Targets behind the camera are ignored.
func find_nearest_to_screen_center(camera: Camera3D, origin: Vector3) -> Node3D:
	if camera == null:
		return null
	var middle := camera.get_viewport().get_visible_rect().size * 0.5
	var best: Node3D
	var best_distance := INF
	for candidate in _candidates(origin, -camera.global_basis.z, false):
		var point: Vector3 = candidate.get_combat_center() if candidate.has_method("get_combat_center") else candidate.global_position
		if camera.is_position_behind(point):
			continue
		var distance := camera.unproject_position(point).distance_squared_to(middle)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best

func get_attack_direction(origin: Vector3, facing: Vector3, input_direction: Vector3, magnetism: float) -> Vector3:
	var base := input_direction.normalized() if input_direction.length_squared() > 0.001 else facing.normalized()
	var range_limit := tuning.magnetism_range if tuning != null else 6.0
	var cone := tuning.magnetism_cone_degrees if tuning != null else 45.0
	var best: Node3D
	var best_distance := range_limit
	for candidate in _candidates(origin, base, false, range_limit):
		var offset := candidate.global_position - origin
		var distance := offset.length()
		if is_zero_approx(distance) or distance > best_distance or rad_to_deg(acos(clampf(base.dot(offset.normalized()), -1.0, 1.0))) > cone:
			continue
		best = candidate
		best_distance = distance
	if best == null:
		return base
	return base.slerp((best.global_position - origin).normalized(), clampf(magnetism, 0.0, 1.0)).normalized()

func _candidates(origin: Vector3, direction: Vector3, lockable_only: bool, range_limit: float = -1.0) -> Array[Node3D]:
	var result: Array[Node3D] = []
	var max_range := tuning.lock_range if tuning != null else 20.0
	if range_limit >= 0.0:
		max_range = range_limit
	for node in get_tree().get_nodes_in_group(target_group):
		if not node is Node3D or node == self or node.is_queued_for_deletion() or (node.has_method("is_alive") and not node.is_alive()):
			continue
		var candidate := node as Node3D
		if candidate.global_position.distance_squared_to(origin) > max_range * max_range:
			continue
		if lockable_only and not bool(candidate.get("elite")) and not bool(candidate.get("flying")):
			continue
		result.append(candidate)
	result.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		var a_angle := direction.normalized().angle_to((a.global_position - origin).normalized())
		var b_angle := direction.normalized().angle_to((b.global_position - origin).normalized())
		if is_equal_approx(a_angle, b_angle):
			return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin)
		return a_angle < b_angle
	)
	return result
