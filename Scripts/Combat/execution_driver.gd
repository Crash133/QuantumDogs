class_name ExecutionDriver
extends RefCounted

const MIN_FACING_DOT_EPSILON: float = 0.0001
const ROUTE_PROBE_STEP: float = 0.2
const WALKABLE_NORMAL_DOT: float = 0.9


## Owns the reserved target and the approach/contact/recovery phases. The body
## itself still moves through Player.move_and_slide; this class only supplies
## a bounded requested velocity and accepts the resolved pose back.

signal contact_committed(target: Object, world_point: Vector3)
signal ended(reason: StringName)

enum Phase { IDLE, APPROACH, SETTLE_POSE, CONTACT, RECOVERY }

var tuning: CombatTuning
var target: Object
var phase: Phase = Phase.IDLE
var body: CharacterBody3D
var unit: WeaponUnit
var center: Node3D
var profile: WeaponContactProfile
var motion: ProceduralContactMotion
var body_velocity: Vector3 = Vector3.ZERO
var _approach_start: Vector3 = Vector3.ZERO
var approach_position: Vector3 = Vector3.ZERO
var facing_direction: Vector3 = Vector3.FORWARD
var center_snapshot: Vector3 = Vector3.ZERO
var motion_action_id: int = 0
var _elapsed: float = 0.0
var _approach_duration: float = 0.0
var _action_elapsed: float = 0.0
var _committed: bool = false
var _aborting: bool = false
var _expected_body_position: Vector3 = Vector3.ZERO
var _block_ticks: int = 0
var _settle_ticks: int = 0
var _airborne_pose_adjusted: bool = false
var _contact_root_offset: float = 0.0
var _contact_initial_tip_error: float = 0.0
var _contact_root_adjustment_used: float = 0.0
var _pending_contact_root_motion: Vector3 = Vector3.ZERO
var _contact_root_motion_start: Vector3 = Vector3.ZERO
var _contact_root_motion_pending: bool = false
var _contact_root_blocked_ticks: int = 0

func select(targeting_service: TargetingService, origin: Vector3, facing: Vector3) -> void:
	if (target == null or not is_instance_valid(target)) and targeting_service != null:
		target = targeting_service.find_executable(origin, facing)

## Executable (staggered Elite at full Heat, or a knocked-down common), alive and within lock range.
func is_valid(candidate_body: Node3D) -> bool:
	if not is_instance_valid(target) or not target is Node3D:
		return false
	var node := target as Node3D
	if node.is_queued_for_deletion() or not node.has_method("execute"):
		return false
	if node.has_method("is_executable"):
		if not node.is_executable(): # Enemy applies the shockwave lock itself (a downed common stays executable)
			return false
	else:
		if node.has_method("is_execution_shockwave_locked") and bool(node.call("is_execution_shockwave_locked")):
			return false
		if not bool(node.get("elite")):
			return false
		if not node.has_method("is_alive") or not node.is_alive() or not node.has_method("is_staggered") or not node.is_staggered():
			return false
		var meter: HeatMeter = node.get_heat_meter() if node.has_method("get_heat_meter") else null
		if meter == null or meter.value < meter.maximum:
			return false
	return candidate_body != null and candidate_body.global_position.distance_to(node.global_position) <= tuning.lock_range

func target_node() -> Node3D:
	return target as Node3D if is_instance_valid(target) else null

## Validate all authored references and the route before any leases are acquired.
func begin(candidate_body: CharacterBody3D, candidate_target: Node3D, candidate_unit: WeaponUnit, candidate_center: Node3D, candidate_profile: WeaponContactProfile, candidate_motion: ProceduralContactMotion) -> Error:
	if phase != Phase.IDLE or not _live(candidate_body) or not _live(candidate_target) or not _live(candidate_unit) or not _live(candidate_center) or not _live(candidate_motion):
		return ERR_INVALID_PARAMETER
	if candidate_profile == null or tuning == null or not is_valid(candidate_body):
		return ERR_INVALID_DATA
	if candidate_unit.tip == null or not is_instance_valid(candidate_unit.tip) or candidate_profile.execution_tip_id != candidate_unit.unit_id:
		return ERR_INVALID_DATA
	if candidate_center.get_parent() != candidate_target and not candidate_target.is_ancestor_of(candidate_center):
		return ERR_INVALID_DATA
	if candidate_motion.is_moving:
		return ERR_BUSY
	body = candidate_body
	target = candidate_target
	unit = candidate_unit
	center = candidate_center
	profile = candidate_profile
	motion = candidate_motion
	center_snapshot = center.global_position
	if not center_snapshot.is_finite():
		_clear()
		return ERR_INVALID_DATA
	var target_airborne := target.has_method("is_execution_airborne") and bool(target.call("is_execution_airborne"))
	var requested_standoff := profile.execution_standoff_distance
	if target_airborne and profile.airborne_execution_standoff_distance > 0.0:
		requested_standoff = profile.airborne_execution_standoff_distance
	var standoff := maxf(requested_standoff, _combined_body_radius(body, target) + 0.04)
	if standoff >= profile.maximum_contact_reach:
		_clear()
		return ERR_PARAMETER_RANGE_ERROR
	var approach_y := body.global_position.y
	if target_airborne and absf(center_snapshot.y - unit.tip.global_position.y) > profile.maximum_contact_reach * 0.5:
		var current_tip_offset := unit.tip.global_position.y - body.global_position.y
		approach_y = center_snapshot.y - current_tip_offset
	if not _find_feasible_approach(standoff, approach_y):
		_clear()
		return ERR_UNAVAILABLE
	var route_distance := body.global_position.distance_to(approach_position)
	var required_duration := route_distance / maxf(profile.execution_max_speed, 0.001)
	_approach_duration = maxf(profile.execution_duration, required_duration)
	if _approach_duration > profile.execution_timeout:
		_clear()
		return ERR_TIMEOUT
	_elapsed = 0.0
	_action_elapsed = 0.0
	_approach_start = body.global_position
	_committed = false
	_aborting = false
	_block_ticks = 0
	_airborne_pose_adjusted = false
	_contact_root_adjustment_used = 0.0
	_pending_contact_root_motion = Vector3.ZERO
	_contact_root_motion_start = body.global_position
	_contact_root_motion_pending = false
	_contact_root_blocked_ticks = 0
	_expected_body_position = body.global_position
	body_velocity = Vector3.ZERO
	phase = Phase.APPROACH
	return OK

## Called by CombatController before the body movement owner resolves movement.
func advance(delta_seconds: float) -> void:
	if phase == Phase.IDLE:
		return
	if not is_finite(delta_seconds) or delta_seconds < 0.0:
		abort(&"invalid_delta")
		return
	if phase != Phase.RECOVERY:
		_action_elapsed += delta_seconds
		if _action_elapsed > profile.execution_timeout:
			abort(&"timeout")
			return
	if phase == Phase.APPROACH:
		if not _live(body) or not _live(target) or not _live(unit) or not _live(center):
			abort(&"participant_lost")
			return
		_elapsed = minf(_elapsed + delta_seconds, _approach_duration)
		var fraction := clampf(_elapsed / maxf(_approach_duration, 0.001), 0.0, 1.0)
		_expected_body_position = _approach_start.lerp(approach_position, fraction)
		var displacement := _expected_body_position - body.global_position
		body_velocity = displacement / maxf(delta_seconds, 0.000001)
		body_velocity = body_velocity.limit_length(profile.execution_max_speed)
	elif phase in [Phase.CONTACT, Phase.RECOVERY]:
		body_velocity = Vector3.ZERO
		if _live(motion) and motion.is_moving:
			motion.evaluate(delta_seconds)
			if phase == Phase.CONTACT:
				_request_contact_root_adjustment(delta_seconds)
	elif phase == Phase.SETTLE_POSE:
		body_velocity = Vector3.ZERO
		_settle_ticks += 1
		if _settle_ticks >= 1:
			if _realign_airborne_approach_to_evaluated_tip():
				return
			_begin_contact_motion()

func _realign_airborne_approach_to_evaluated_tip() -> bool:
	if _airborne_pose_adjusted or not _live(target) or not _live(unit) or not _live(unit.tip):
		return false
	if not target.has_method("is_execution_airborne") or not bool(target.call("is_execution_airborne")):
		return false
	var tip_error := center_snapshot - unit.tip.global_position
	var solver_limit := profile.rig_calibration.execution_tip_correction_limit if profile.rig_calibration != null else 0.0
	if tip_error.length() <= solver_limit:
		return false
	var vertical_correction := tip_error.y
	if absf(vertical_correction) < 0.01 or absf(vertical_correction) > profile.maximum_contact_reach:
		return false
	var destination := body.global_position + Vector3.UP * vertical_correction
	if body.global_position.distance_to(destination) > tuning.lock_range or body.test_move(body.global_transform, destination - body.global_position):
		abort(&"airborne_pose_route_blocked")
		return true
	approach_position.y = destination.y
	_approach_start = body.global_position
	_approach_duration = maxf(0.05, absf(vertical_correction) / maxf(profile.execution_max_speed, 0.001))
	_elapsed = 0.0
	_block_ticks = 0
	_settle_ticks = 0
	_airborne_pose_adjusted = true
	phase = Phase.APPROACH
	return true

## At the end of the authored Tip curve, request a small root correction through
## Player's normal CharacterBody3D movement. The weapon marker itself is never
## translated or detached to satisfy contact.
func _request_contact_root_adjustment(delta_seconds: float) -> void:
	if not _live(body) or not _live(unit) or not _live(unit.tip) or not _live(motion) or profile == null:
		return
	if motion._last_progress < 1.0 or motion._has_reported_contact:
		return
	if motion._endpoint_settle_elapsed < 2.0 / float(maxi(1, tuning.tick_rate)):
		return # Let the modifier evaluate the endpoint once before changing the root.
	var remaining_budget := profile.execution_contact_root_adjustment_limit - _contact_root_adjustment_used
	if remaining_budget <= 0.0001 or delta_seconds <= 0.000001:
		return
	var error := center_snapshot - unit.tip.global_position
	if not error.is_finite() or error.length() <= profile.contact_tolerance:
		return
	var maximum_step := minf(remaining_budget, profile.execution_max_speed * delta_seconds)
	var correction := error.limit_length(maximum_step)
	if correction.length() <= 0.0001:
		return
	_pending_contact_root_motion = correction
	_contact_root_motion_start = body.global_position
	_contact_root_motion_pending = true
	body_velocity = correction / delta_seconds

## Called immediately after Player.move_and_slide has resolved this frame.
func after_body_move() -> void:
	if phase == Phase.CONTACT and _contact_root_motion_pending:
		if not _live(body):
			abort(&"body_lost")
			return
		var actual_motion := body.global_position - _contact_root_motion_start
		_contact_root_adjustment_used += actual_motion.length()
		if actual_motion.length() + 0.002 < _pending_contact_root_motion.length() * 0.5:
			_contact_root_blocked_ticks += 1
		else:
			_contact_root_blocked_ticks = 0
		_contact_root_motion_pending = false
		_pending_contact_root_motion = Vector3.ZERO
		body_velocity = Vector3.ZERO
		if _contact_root_blocked_ticks >= 2:
			abort(&"contact_root_adjustment_blocked")
		return
	if phase != Phase.APPROACH:
		return
	if not _live(body):
		abort(&"body_lost")
		return
	var error := body.global_position.distance_to(_expected_body_position)
	if error > 0.06:
		_block_ticks += 1
		if _block_ticks >= 2:
			abort(&"body_route_blocked")
		return
	_block_ticks = 0
	if _elapsed + 0.000001 < _approach_duration or body.global_position.distance_to(approach_position) > 0.06:
		return
	if not _live(unit) or not _live(center) or not _live(motion):
		abort(&"contact_reference_lost")
		return
	phase = Phase.SETTLE_POSE
	_settle_ticks = 0

func _begin_contact_motion() -> void:
	if phase != Phase.SETTLE_POSE:
		return
	if not _live(body) or not _live(target) or not _live(unit) or not _live(unit.tip) or not _live(center) or not _live(motion):
		abort(&"contact_reference_lost")
		return
	_contact_root_offset = body.global_position.distance_to(approach_position)
	_contact_initial_tip_error = unit.tip.global_position.distance_to(center_snapshot)
	var error_code := motion.begin_execution(unit, center_snapshot, profile, target)
	if error_code != OK:
		push_warning("Execution contact route rejected by calibrated Tip solver (error=%d, actual_tip=%s center=%s distance=%.3f)" % [error_code, unit.tip.global_position, center_snapshot, unit.tip.global_position.distance_to(center_snapshot)])
		abort(&"contact_route_rejected")
		return
	motion_action_id = motion.current_action_id
	phase = Phase.CONTACT
	_action_elapsed = 0.0

## Called only from the SkeletonModifier's actual evaluated Tip contact signal.
func commit_contact(action_id: int, actual_tip: Vector3) -> bool:
	if phase != Phase.CONTACT or _committed or action_id != motion_action_id or not actual_tip.is_finite():
		return false
	if not _live(unit) or not _live(unit.tip) or not _live(target):
		abort(&"contact_reference_lost")
		return false
	var measured_tip := unit.tip.global_position
	if measured_tip.distance_to(center_snapshot) > profile.contact_tolerance or actual_tip.distance_to(center_snapshot) > profile.contact_tolerance:
		abort(&"tip_outside_contact_tolerance")
		return false
	if not is_valid(body):
		abort(&"eligibility_lost")
		return false
	_committed = true # Guard before execute() can emit reentrant death/loot signals.
	var victim := target_node()
	if victim == null or not victim.execute():
		abort(&"commit_rejected")
		return false
	phase = Phase.RECOVERY
	target = null # Victim may be freed by execute(); recovery uses only the stored contact pose.
	center = null
	contact_committed.emit(victim, actual_tip)
	return true

func motion_ended(action_id: int, reason: StringName) -> void:
	if phase == Phase.IDLE or action_id != motion_action_id:
		return
	if phase == Phase.CONTACT and reason == &"unreachable":
		push_warning("Execution contact diagnostic: root approach offset %.3f m, initial Tip error %.3f m, correction limit %.3f m" % [
			_contact_root_offset,
			_contact_initial_tip_error,
			profile.rig_calibration.execution_tip_correction_limit if profile != null and profile.rig_calibration != null else -1.0,
		])
	if phase == Phase.RECOVERY and reason == &"contact":
		_clear()
		ended.emit(&"completed")
	else:
		abort(reason)

func abort(reason: StringName) -> void:
	if phase == Phase.IDLE or _aborting:
		return
	_aborting = true
	if is_instance_valid(motion) and motion.is_moving:
		motion.abort(reason)
	_clear()
	ended.emit(reason)
	_aborting = false

func is_active() -> bool:
	return phase != Phase.IDLE

func committed() -> bool:
	return _committed

func _route_body_radius(actor: Node) -> float:
	if not is_instance_valid(actor):
		return 0.0
	var shape_node := actor.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null or shape_node.shape == null:
		return 0.0
	if shape_node.shape is CapsuleShape3D:
		return (shape_node.shape as CapsuleShape3D).radius * maxf(actor.global_basis.get_scale().x, actor.global_basis.get_scale().z)
	if shape_node.shape is SphereShape3D:
		return (shape_node.shape as SphereShape3D).radius * maxf(actor.global_basis.get_scale().x, actor.global_basis.get_scale().z)
	return 0.0

func _combined_body_radius(first: Node, second: Node) -> float:
	return _route_body_radius(first) + _route_body_radius(second)

## Grounded characters can overlap the generated arena's smooth concave floor
## slightly while moving. A single long test_move treats that walkable surface as
## a wall and hides any later obstacle. Probe short segments, ignoring only
## upward-facing contacts; walls and undersides still reject the route.
func _route_has_non_floor_blocker(destination: Vector3) -> bool:
	var route := destination - body.global_position
	var distance := route.length()
	if distance <= 0.001:
		return false
	var steps := maxi(1, ceili(distance / ROUTE_PROBE_STEP))
	var previous := body.global_position
	for step_index in range(1, steps + 1):
		var next_position := body.global_position.lerp(destination, float(step_index) / float(steps))
		var probe_transform := body.global_transform
		probe_transform.origin = previous
		var collision := KinematicCollision3D.new()
		var segment := next_position - previous
		if body.test_move(probe_transform, segment, collision):
			if collision.get_normal().dot(Vector3.UP) < WALKABLE_NORMAL_DOT:
				return true
		previous = next_position
	return false

func _find_feasible_approach(standoff: float, approach_y: float) -> bool:
	if profile.rig_calibration == null or not body.has_method("get_execution_tip_world_at"):
		return false
	var best_score := INF
	var best_position := Vector3.ZERO
	var best_facing := Vector3.ZERO
	var closest_tip_error := INF
	const ROOT_ANGLES := 24
	const FACING_ANGLES := 72
	var candidate_vertical_gap := center_snapshot.y - approach_y
	var ring_distance_to_center := Vector2(standoff, candidate_vertical_gap).length()
	var start_distance_to_center := body.global_position.distance_to(center_snapshot)
	var keep_current_root := start_distance_to_center <= ring_distance_to_center + 0.001
	for root_index in range(ROOT_ANGLES + (1 if keep_current_root else 0)):
		var candidate: Vector3
		if keep_current_root and root_index == ROOT_ANGLES:
			candidate = body.global_position
		else:
			var root_angle := TAU * float(root_index) / float(ROOT_ANGLES)
			var radial := Vector3(cos(root_angle), 0.0, sin(root_angle))
			candidate = Vector3(center_snapshot.x, approach_y, center_snapshot.z) - radial * standoff
		var toward_center := Vector3(center_snapshot.x - candidate.x, 0.0, center_snapshot.z - candidate.z)
		if toward_center.length_squared() <= 0.000001:
			toward_center = Vector3(-body.global_basis.z.x, 0.0, -body.global_basis.z.z)
		if toward_center.length_squared() <= 0.000001:
			toward_center = Vector3.FORWARD
		toward_center = toward_center.normalized()
		var route_distance := body.global_position.distance_to(candidate)
		if route_distance > 0.001 and candidate.distance_to(center_snapshot) >= start_distance_to_center - 0.001:
			continue # Never retreat to a worse standoff; if already close, keep the current root.
		if route_distance > tuning.lock_range:
			continue
		if route_distance > 0.001 and _route_has_non_floor_blocker(candidate):
			continue
		for facing_index in range(FACING_ANGLES):
			var facing_angle := TAU * float(facing_index) / float(FACING_ANGLES)
			var candidate_facing := Vector3(cos(facing_angle), 0.0, sin(facing_angle))
			if candidate_facing.dot(toward_center) + MIN_FACING_DOT_EPSILON < profile.execution_min_target_facing_dot:
				continue
			var predicted_tip: Vector3 = body.call("get_execution_tip_world_at", candidate, candidate_facing, unit.tip)
			var tip_error := predicted_tip.distance_to(center_snapshot)
			closest_tip_error = minf(closest_tip_error, tip_error)
			if not predicted_tip.is_finite() or tip_error > profile.rig_calibration.execution_tip_correction_limit + profile.contact_tolerance:
				continue
			# Plan against the authored mount pose; begin_execution will validate
			# the actual Tip again after animation and body movement have settled.
			var score := tip_error + route_distance * 0.01 + (1.0 - candidate_facing.dot(toward_center)) * 0.02
			if score < best_score:
				best_score = score
				best_position = candidate
				best_facing = candidate_facing
	if not is_finite(best_score):
		push_warning("Execution rejected: no collision-free approach exists within %.3f m (closest predicted Tip error %.3f m)" % [tuning.lock_range, closest_tip_error])
		return false
	approach_position = best_position
	facing_direction = best_facing
	return true

func _live(value: Variant) -> bool:
	if value == null or typeof(value) != TYPE_OBJECT or not is_instance_valid(value):
		return false
	return not value is Node or (not (value as Node).is_queued_for_deletion() and (value as Node).is_inside_tree())

func _clear() -> void:
	phase = Phase.IDLE
	target = null
	body = null
	unit = null
	center = null
	profile = null
	motion = null
	body_velocity = Vector3.ZERO
	approach_position = Vector3.ZERO
	facing_direction = Vector3.FORWARD
	center_snapshot = Vector3.ZERO
	_approach_start = Vector3.ZERO
	motion_action_id = 0
	_elapsed = 0.0
	_approach_duration = 0.0
	_action_elapsed = 0.0
	_settle_ticks = 0
	_committed = false
	_block_ticks = 0
	_contact_root_adjustment_used = 0.0
	_pending_contact_root_motion = Vector3.ZERO
	_contact_root_motion_start = Vector3.ZERO
	_contact_root_motion_pending = false
	_contact_root_blocked_ticks = 0
