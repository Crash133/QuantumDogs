class_name AerialFollow
extends RefCounted

var tuning: CombatTuning
var target: Node3D
var ticks_left: int = 0
var approach_offset: Vector3 = Vector3.ZERO
var source_center_offset: Vector3 = Vector3.ZERO
var _opportunities: Dictionary = {}

func record_launch(enemy: Node3D, tick: int) -> void:
	if tuning == null or not _eligible(enemy):
		return
	_opportunities[enemy.get_instance_id()] = {"target": weakref(enemy), "opened": tick, "expires": tick + tuning.aerial_follow_window_ticks}

func step(tick: int) -> bool:
	for id in _opportunities.keys():
		var entry: Dictionary = _opportunities[id]
		if tick > int(entry.expires) or not _eligible(entry.target.get_ref()):
			_opportunities.erase(id)
	if is_instance_valid(target):
		ticks_left -= 1
		if ticks_left <= 0 or not _eligible(target):
			cancel()
	return is_instance_valid(target)

func try_start(origin: Vector3, facing: Vector3, pressed_tick: int, tick: int, locked: Node3D = null, center_offset: Vector3 = Vector3.ZERO) -> bool:
	var selected: Node3D
	var nearest := INF
	for entry in _opportunities.values():
		var candidate := entry.target.get_ref() as Node3D
		if not _eligible(candidate) or pressed_tick <= int(entry.opened) or tick > int(entry.expires):
			continue
		var distance := origin.distance_squared_to(candidate.global_position)
		if distance > tuning.lock_range * tuning.lock_range:
			continue
		if candidate == locked:
			selected = candidate
			break
		if distance < nearest:
			nearest = distance
			selected = candidate
	if selected == null:
		return false
	target = selected
	var side := origin - target.global_position
	side.y = 0.0
	if side.is_zero_approx():
		side = -facing
		side.y = 0.0
	if side.is_zero_approx():
		side = Vector3.BACK
	approach_offset = side.normalized() * tuning.aerial_follow_distance
	source_center_offset = center_offset
	ticks_left = maxi(1, tuning.aerial_follow_timeout_ticks)
	_opportunities.clear()
	return true

func destination() -> Vector3:
	if not is_instance_valid(target):
		return Vector3.ZERO
	var center: Vector3 = target.get_combat_center() if target.has_method("get_combat_center") else target.global_position
	return center + approach_offset - source_center_offset

func cancel() -> void:
	target = null
	ticks_left = 0
	_opportunities.clear()

func _eligible(enemy: Object) -> bool:
	return is_instance_valid(enemy) and enemy is Node3D and not enemy.is_queued_for_deletion() and enemy.has_method("is_alive") and enemy.is_alive() and enemy.has_method("is_combat_airborne") and enemy.is_combat_airborne()
