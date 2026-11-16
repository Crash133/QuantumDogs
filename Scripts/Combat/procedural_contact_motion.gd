class_name ProceduralContactMotion
extends SkeletonModifier3D

## Bounded CCD modifier for a mounted, authored weapon Tip. It changes only
## calibrated skeleton rotations; the held weapon, marker and gameplay body
## remain owned by their existing scene and movement systems.

signal contact_reached(action_id: int, point: Vector3)
signal ended(action_id: int, reason: StringName)

@export_group("Solver")
## Maximum total CCD rotation per calibrated joint, independent of render rate.
@export_range(30.0, 1080.0, 10.0, "suffix:deg/s") var maximum_joint_speed_degrees_per_second: float = 480.0
## Maximum CCD passes per render/physics evaluation.
@export_range(1, 12, 1) var iterations_per_evaluation: int = 3
## Extra CCD passes for execution only; parry continues using iterations_per_evaluation.
@export_range(1, 12, 1) var execution_iterations_per_evaluation: int = 3
## Execution-only joint speed cap; keeps rapid finisher alignment bounded while parry stays conservative.
@export_range(30.0, 2400.0, 10.0, "suffix:deg/s") var execution_maximum_joint_speed_degrees_per_second: float = 480.0
## Minimum number of continuous-cast spans used to validate the curved route.
@export_range(4, 32, 1) var route_samples: int = 12
## Maximum deviation between an adaptively refined Bezier span and its cast chord.
@export_range(0.001, 0.02, 0.001, "suffix:m") var route_curve_error_tolerance: float = 0.004
## Maximum adaptive splits per configured span; unresolved curvature inflates the envelope conservatively.
@export_range(0, 6, 1) var route_max_subdivision_depth: int = 4

static var _next_action_id: int = 1

var is_moving: bool = false
var current_action_id: int = 0
var desired_tip_world: Vector3 = Vector3.ZERO
var _unit: WeaponUnit
var _profile: WeaponContactProfile
var _skeleton: Skeleton3D
var _actor: Node3D
var _attacker: Object
var _tip_attachment: BoneAttachment3D
var _collision_exclusions: Array[RID] = []
var _envelope_shape: SphereShape3D
var _envelope_query: PhysicsShapeQueryParameters3D
var _bone_ids: Array[int] = []
var _execution_base_rotations: Dictionary = {}
var _hand_bone_id: int = -1
## Flattened rigs: chain bone id -> bones it must carry (chain bones nearer the hand + hand followers).
var _carried: Dictionary = {}
## Every bone this action overrides (chain bones, plus carried bones on flattened rigs).
var _overridden: Array[int] = []
var _shoulder_bone_id: int = -1
var _elbow_bone_id: int = -1
var _tip_in_hand: Transform3D = Transform3D.IDENTITY
var _start: Vector3 = Vector3.ZERO
var _control_a: Vector3 = Vector3.ZERO
var _control_b: Vector3 = Vector3.ZERO
var _finish: Vector3 = Vector3.ZERO
var _elapsed: float = 0.0
var _endpoint_settle_elapsed: float = 0.0
var _hold_elapsed: float = 0.0
var _recovery_elapsed: float = 0.0
var _last_progress: float = 0.0
var _has_reported_contact: bool = false
var _pending_contact_evaluation: bool = false
var _is_recovering: bool = false
var _active: bool = false
var _for_execution: bool = false
var _action_duration: float = 0.0
var _contact_hold_seconds: float = 0.0
var _recovery_seconds: float = 0.0

## Begin a Tip interception at a world point on the incoming melee volume.
## Returns an Error so a confirmed defense can remain successful if presentation
## is unavailable or unreachable.
func begin(unit: WeaponUnit, target_world: Vector3, profile: WeaponContactProfile, attacker: Object = null) -> Error:
	return _begin(unit, target_world, profile, attacker, false)

## Execution uses the same authored Tip, calibrated solver and collision route,
## with its own bounded contact and recovery timing.
func begin_execution(unit: WeaponUnit, target_world: Vector3, profile: WeaponContactProfile, victim: Object) -> Error:
	return _begin(unit, target_world, profile, victim, true)

func _begin(unit: WeaponUnit, target_world: Vector3, profile: WeaponContactProfile, attacker: Object, for_execution: bool) -> Error:
	abort(&"replaced")
	if unit == null or not is_instance_valid(unit) or not unit.is_inside_tree() or unit.tip == null or not is_instance_valid(unit.tip):
		return ERR_INVALID_PARAMETER
	if profile == null or not target_world.is_finite():
		return ERR_INVALID_PARAMETER
	_skeleton = get_skeleton()
	if not is_instance_valid(_skeleton):
		return ERR_UNCONFIGURED
	var calibration := profile.rig_calibration
	if calibration == null or not calibration.validate().is_empty():
		return ERR_INVALID_DATA
	var calibration_errors := calibration.validate_against_skeleton(_skeleton)
	if not calibration_errors.is_empty():
		push_warning("WeaponContactProfile rig_calibration is invalid for the mounted skeleton: %s" % "; ".join(calibration_errors))
		return ERR_INVALID_DATA
	_bone_ids.clear()
	var correction_bones := calibration.execution_correction_bones if for_execution and not calibration.execution_correction_bones.is_empty() else calibration.correction_bones
	for bone_name in correction_bones:
		var bone_id := _skeleton.find_bone(String(bone_name))
		if bone_id < 0:
			return ERR_DOES_NOT_EXIST
		if not _bone_ids.has(bone_id):
			_bone_ids.append(bone_id)
	_hand_bone_id = _skeleton.find_bone(String(calibration.hand_bone))
	_shoulder_bone_id = _skeleton.find_bone(String(calibration.shoulder_bone))
	_elbow_bone_id = _skeleton.find_bone(String(calibration.elbow_bone))
	if _hand_bone_id < 0 or _bone_ids.is_empty() or _bone_ids[0] != _hand_bone_id:
		return ERR_INVALID_DATA
	_carried.clear()
	_overridden = _bone_ids.duplicate()
	if calibration.flattened_rig:
		var followers: Array[int] = []
		for follower_name in calibration.hand_followers:
			followers.append(_skeleton.find_bone(String(follower_name)))
		# Carry along the full arm (correction_bones lists every segment hand -> shoulder),
		# so an execution chain that skips twist segments still moves them.
		var arm: Array[int] = []
		for arm_bone in calibration.correction_bones:
			arm.append(_skeleton.find_bone(String(arm_bone)))
		var shoulder := _skeleton.find_bone(String(calibration.shoulder_bone))
		if not arm.has(shoulder):
			arm.append(shoulder)
		for index in arm.size():
			var carried: Array[int] = arm.slice(0, index)
			carried.append_array(followers)
			_carried[arm[index]] = carried
		for bone_id in arm + followers:
			if not _overridden.has(bone_id):
				_overridden.append(bone_id)
	_tip_attachment = _find_tip_attachment(unit.tip, _skeleton)
	_refresh_tip_attachment()
	_start = unit.tip.global_position
	if not _start.is_finite() or _start.distance_to(target_world) > profile.maximum_contact_reach:
		return ERR_PARAMETER_RANGE_ERROR
	var maximum_direct_tip_travel := calibration.execution_tip_correction_limit if for_execution else calibration.grip_correction_limit
	if _start.distance_to(target_world) > maximum_direct_tip_travel:
		return ERR_PARAMETER_RANGE_ERROR
	var shoulder_world := _skeleton.to_global(_skeleton.get_bone_global_pose(_shoulder_bone_id).origin)
	var elbow_world := _skeleton.to_global(_skeleton.get_bone_global_pose(_elbow_bone_id).origin)
	var hand_world := _skeleton.to_global(_skeleton.get_bone_global_pose(_hand_bone_id).origin)
	var calibrated_reach := shoulder_world.distance_to(target_world)
	var chain_tip_correction := calibration.execution_tip_correction_limit if for_execution else calibration.grip_correction_limit
	var maximum_chain_reach := shoulder_world.distance_to(elbow_world) + elbow_world.distance_to(hand_world) + hand_world.distance_to(_start) + chain_tip_correction
	if calibrated_reach < calibration.minimum_reach or calibrated_reach > minf(calibration.maximum_reach, maximum_chain_reach):
		return ERR_PARAMETER_RANGE_ERROR
	_execution_base_rotations.clear()
	if for_execution:
		for bone_id in _bone_ids:
			_execution_base_rotations[bone_id] = _skeleton.get_bone_global_pose(bone_id).basis.get_rotation_quaternion()
	_unit = unit
	_profile = profile
	_for_execution = for_execution
	_action_duration = profile.execution_contact_duration if for_execution else profile.parry_duration
	_contact_hold_seconds = profile.execution_contact_hold_seconds if for_execution else profile.parry_contact_hold_seconds
	_recovery_seconds = profile.execution_recovery_seconds if for_execution else profile.parry_recovery_seconds
	_attacker = attacker if typeof(attacker) == TYPE_OBJECT and is_instance_valid(attacker) else null
	_actor = _find_actor(_skeleton)
	if _actor == null:
		_clear_action()
		return ERR_UNCONFIGURED
	_cache_collision_exclusions()
	var hand_local := _skeleton.get_bone_global_pose(_hand_bone_id)
	var tip_skeleton_local := _skeleton.global_transform.affine_inverse() * unit.tip.global_transform
	_tip_in_hand = hand_local.affine_inverse() * tip_skeleton_local
	_finish = target_world
	var direction := (_finish - _start).normalized()
	var side := Vector3.UP.cross(direction).normalized()
	if side.is_zero_approx():
		side = Vector3.RIGHT
	var distance := _start.distance_to(_finish)
	var sideways := side * profile.curve_sideways_offset
	var lift := Vector3.UP * profile.curve_height_offset
	_control_a = _start.lerp(_finish, 1.0 / 3.0) + sideways + lift * profile.curve_lift_fraction
	_control_b = _start.lerp(_finish, 2.0 / 3.0) - sideways + lift * profile.curve_lift_fraction
	# Keep control points bounded when unusual offsets are authored.
	var control_limit := maxf(distance, 0.01) * 1.5
	_control_a = _start + (_control_a - _start).limit_length(control_limit)
	_control_b = _finish + (_control_b - _finish).limit_length(control_limit)
	_envelope_shape = SphereShape3D.new()
	_envelope_shape.radius = profile.parry_envelope_radius
	_envelope_query = PhysicsShapeQueryParameters3D.new()
	_envelope_query.shape = _envelope_shape
	_envelope_query.collision_mask = profile.parry_collision_mask
	_envelope_query.collide_with_areas = true
	_envelope_query.collide_with_bodies = true
	_envelope_query.exclude = _collision_exclusions
	if not _route_is_clear():
		_clear_action()
		return ERR_BUSY
	current_action_id = _next_action_id
	_next_action_id += 1
	_elapsed = 0.0
	_endpoint_settle_elapsed = 0.0
	_last_progress = 0.0
	_has_reported_contact = false
	_pending_contact_evaluation = false
	desired_tip_world = _start
	is_moving = true
	_active = true
	var modifier_callable := Callable(self, "_on_modifier_processed")
	if not modification_processed.is_connected(modifier_callable):
		modification_processed.connect(modifier_callable)
	return OK

## Advance using the participant's local actor clock. The motion samples a fixed
## elapsed-time curve, so arrival is independent of render frame count.
func evaluate(delta_seconds: float) -> void:
	if not is_moving:
		return
	if not is_finite(delta_seconds) or delta_seconds < 0.0:
		abort(&"invalid_delta")
		return
	if not is_instance_valid(_unit) or _unit.is_queued_for_deletion() or not is_instance_valid(_unit.tip) or not is_instance_valid(_profile):
		abort(&"weapon_lost")
		return
	if _has_reported_contact:
		if not _is_recovering:
			_hold_elapsed += delta_seconds
			if _hold_elapsed >= _contact_hold_seconds:
				_is_recovering = true
				_recovery_elapsed = 0.0
		else:
			_recovery_elapsed = minf(_recovery_elapsed + delta_seconds, _recovery_seconds)
		return
	_elapsed = minf(_elapsed + delta_seconds, _action_duration)
	var progress := clampf(_elapsed / maxf(_action_duration, 0.001), 0.0, 1.0)
	_last_progress = maxf(_last_progress, progress)
	if _for_execution and _last_progress >= 1.0:
		_endpoint_settle_elapsed += delta_seconds
	var eased := eased_progress(_elapsed, _action_duration, _profile.contact_curve)
	desired_tip_world = bezier_point(_start, _control_a, _control_b, _finish, eased)

## End the visual action and release every temporary bone override.
func abort(reason: StringName) -> void:
	if not _active and not is_moving:
		_clear_overrides()
		return
	var old_action := current_action_id
	_clear_overrides()
	_clear_action()
	ended.emit(old_action, reason)

## Cubic Bezier helper shared by runtime and deterministic preview/tests.
static func bezier_point(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, progress: float) -> Vector3:
	var t := clampf(progress, 0.0, 1.0)
	var u := 1.0 - t
	return p0 * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + p3 * (t * t * t)

## Map participant-local elapsed time to normalized monotonic route progress.
static func eased_progress(elapsed: float, duration: float, curve: Curve = null) -> float:
	var raw := clampf(elapsed / maxf(duration, 0.001), 0.0, 1.0)
	var eased := curve.sample_baked(raw) if curve != null else raw * raw * (3.0 - 2.0 * raw)
	return clampf(eased, 0.0, 1.0)

func _process_modification() -> void:
	_apply_ccd(1.0 / 60.0)

func _process_modification_with_delta(delta: float) -> void:
	_apply_ccd(delta)

func _apply_ccd(delta: float) -> void:
	if not _active or not is_moving or not is_instance_valid(_skeleton) or not is_instance_valid(_unit):
		return
	if not is_instance_valid(_unit.tip):
		abort(&"weapon_tip_lost")
		return
	if not is_finite(delta) or delta <= 0.0:
		return
	if not _point_is_clear(desired_tip_world):
		abort(&"blocked")
		return
	# Parry animation keeps advancing, so rebuild its correction from the live
	# pose each evaluation. Execution pauses its animation; retain the initial
	# correction basis so CCD can accumulate toward the reserved center.
	var frame_base_rotations: Dictionary = {}
	if _for_execution:
		frame_base_rotations = _execution_base_rotations
	else:
		for bone_id in _overridden:
			_skeleton.set_bone_global_pose_override(bone_id, Transform3D.IDENTITY, 0.0, true)
		_skeleton.force_update_all_bone_transforms()
		_refresh_tip_attachment()
		for bone_id in _bone_ids:
			frame_base_rotations[bone_id] = _skeleton.get_bone_global_pose(bone_id).basis.get_rotation_quaternion()
	if _is_recovering and _recovery_elapsed >= _recovery_seconds:
		var recovered_action := current_action_id
		_clear_overrides()
		is_moving = false
		_active = false
		ended.emit(recovered_action, &"contact")
		_clear_action()
		return
	var target_world := desired_tip_world
	if _is_recovering:
		var animated_tip_world := _start if _for_execution else _predicted_tip_world()
		var recovery_progress := _recovery_elapsed / maxf(_recovery_seconds, 0.001)
		target_world = _finish.lerp(animated_tip_world, _smoothstep(clampf(recovery_progress, 0.0, 1.0)))
	var target_local := _skeleton.to_local(target_world)
	var solve_iterations := execution_iterations_per_evaluation if _for_execution else iterations_per_evaluation
	for _iteration in solve_iterations:
		_apply_pole_constraint(target_local, frame_base_rotations, delta)
		var effector := _skeleton.to_local(_unit.tip.global_position)
		for bone_id in _bone_ids:
			var joint_pose := _skeleton.get_bone_global_pose(bone_id)
			var from_joint := effector - joint_pose.origin
			var to_target := target_local - joint_pose.origin
			if from_joint.length_squared() <= 0.000001 or to_target.length_squared() <= 0.000001:
				continue
			var desired_rotation := Quaternion(from_joint.normalized(), to_target.normalized())
			var joint_speed := execution_maximum_joint_speed_degrees_per_second if _for_execution else maximum_joint_speed_degrees_per_second
			var maximum_step := deg_to_rad(joint_speed) * delta / float(maxi(1, solve_iterations))
			var weight := minf(1.0, maximum_step / maxf(desired_rotation.get_angle(), 0.000001))
			var current_rotation := joint_pose.basis.get_rotation_quaternion()
			var candidate_rotation := Quaternion.IDENTITY.slerp(desired_rotation, weight) * current_rotation
			candidate_rotation = _limit_joint_yaw(int(bone_id), candidate_rotation, frame_base_rotations)
			joint_pose.basis = Basis(candidate_rotation).scaled(joint_pose.basis.get_scale())
			_skeleton.set_bone_global_pose_override(bone_id, joint_pose, influence, true)
			_carry(bone_id, candidate_rotation * current_rotation.inverse(), joint_pose.origin)
			_skeleton.force_update_all_bone_transforms()
			_refresh_tip_attachment()
			effector = _skeleton.to_local(_unit.tip.global_position)
	_pending_contact_evaluation = _last_progress >= 1.0 and not _has_reported_contact

func _on_modifier_processed() -> void:
	if not _pending_contact_evaluation or not _active or not is_moving:
		return
	_pending_contact_evaluation = false
	if not is_instance_valid(_unit) or not is_instance_valid(_unit.tip) or _profile == null:
		abort(&"weapon_lost")
		return
	_refresh_tip_attachment()
	var actual_tip := _unit.tip.global_position
	if actual_tip.distance_to(_finish) <= _profile.contact_tolerance:
		_has_reported_contact = true
		_hold_elapsed = 0.0
		var finished_action := current_action_id
		contact_reached.emit(finished_action, actual_tip)
	elif not _for_execution or _endpoint_settle_elapsed >= _profile.execution_contact_settle_seconds:
		var predicted_tip := _predicted_tip_world()
		var corrections := _format_corrections(_execution_base_rotations) if _for_execution else ""
		push_warning("Procedural contact unreachable: evaluated Tip %.3f m from target (target=%s evaluated=%s predicted=%s corrections=%s); action=%d execution=%s" % [actual_tip.distance_to(_finish), _finish, actual_tip, predicted_tip, corrections, current_action_id, _for_execution])
		abort(&"unreachable")

func _predicted_tip_world() -> Vector3:
	var hand_local := _skeleton.get_bone_global_pose(_hand_bone_id)
	return (_skeleton.global_transform * hand_local * _tip_in_hand).origin

func _apply_pole_constraint(target_local: Vector3, base_rotations: Dictionary, delta: float) -> void:
	if _shoulder_bone_id < 0 or _elbow_bone_id < 0 or _profile == null:
		return
	var shoulder_pose := _skeleton.get_bone_global_pose(_shoulder_bone_id)
	var elbow_pose := _skeleton.get_bone_global_pose(_elbow_bone_id)
	var axis := (target_local - shoulder_pose.origin).normalized()
	if axis.is_zero_approx():
		return
	var current_elbow := elbow_pose.origin - shoulder_pose.origin
	current_elbow -= axis * current_elbow.dot(axis)
	var pole_direction := _profile.rig_calibration.execution_pole_direction
	if not _for_execution or pole_direction.is_zero_approx():
		pole_direction = _profile.rig_calibration.pole_direction
	if _for_execution and is_instance_valid(_attacker) and _attacker is Node and (_attacker as Node).has_method("is_execution_airborne") and bool((_attacker as Node).call("is_execution_airborne")):
		var airborne_pole := _profile.rig_calibration.airborne_execution_pole_direction
		if not airborne_pole.is_zero_approx():
			pole_direction = airborne_pole
	var pole := pole_direction.normalized()
	pole -= axis * pole.dot(axis)
	if current_elbow.length_squared() < 0.000001 or pole.length_squared() < 0.000001:
		return
	var signed_angle := atan2(axis.dot(current_elbow.normalized().cross(pole.normalized())), current_elbow.normalized().dot(pole.normalized()))
	var joint_speed := execution_maximum_joint_speed_degrees_per_second if _for_execution else maximum_joint_speed_degrees_per_second
	var maximum_step := minf(deg_to_rad(_yaw_correction_limit()), deg_to_rad(joint_speed) * delta)
	signed_angle = clampf(signed_angle, -maximum_step, maximum_step)
	var candidate := Quaternion(axis, signed_angle) * shoulder_pose.basis.get_rotation_quaternion()
	candidate = _limit_joint_yaw(_shoulder_bone_id, candidate, base_rotations)
	var shoulder_rotation := shoulder_pose.basis.get_rotation_quaternion()
	shoulder_pose.basis = Basis(candidate).scaled(shoulder_pose.basis.get_scale())
	_skeleton.set_bone_global_pose_override(_shoulder_bone_id, shoulder_pose, influence, true)
	_carry(_shoulder_bone_id, candidate * shoulder_rotation.inverse(), shoulder_pose.origin)
	_skeleton.force_update_all_bone_transforms()
	_refresh_tip_attachment()

func _limit_joint_yaw(bone_id: int, candidate: Quaternion, base_rotations: Dictionary) -> Quaternion:
	var base: Quaternion = base_rotations.get(bone_id, candidate)
	var relative := base.inverse() * candidate
	var euler := Basis(relative).get_euler()
	var maximum_yaw := deg_to_rad(_yaw_correction_limit())
	euler.y = clampf(wrapf(euler.y, -PI, PI), -maximum_yaw, maximum_yaw)
	return base * Basis.from_euler(euler).get_rotation_quaternion()

func _format_corrections(base_rotations: Dictionary) -> String:
	var details := PackedStringArray()
	for bone_id in _bone_ids:
		var base: Quaternion = base_rotations.get(bone_id, Quaternion.IDENTITY)
		var current := _skeleton.get_bone_global_pose(bone_id).basis.get_rotation_quaternion()
		var euler := Basis(base.inverse() * current).get_euler()
		details.append("%s:(%.1f,%.1f,%.1f)" % [
			_skeleton.get_bone_name(bone_id), rad_to_deg(euler.x), rad_to_deg(euler.y), rad_to_deg(euler.z)
		])
	return ",".join(details)

func _route_is_clear() -> bool:
	if _profile == null or not is_instance_valid(_skeleton):
		return false
	var world := _skeleton.get_world_3d()
	if world == null or _envelope_query == null:
		return false
	_envelope_shape.radius = _profile.parry_envelope_radius
	_envelope_query.transform = Transform3D(Basis.IDENTITY, _start)
	_envelope_query.motion = Vector3.ZERO
	if not world.direct_space_state.intersect_shape(_envelope_query, 1).is_empty():
		return false
	for span_index in range(route_samples):
		var t0 := float(span_index) / float(route_samples)
		var t1 := float(span_index + 1) / float(route_samples)
		var section := _bezier_subcurve(t0, t1)
		if not _cast_curve_section(world, section, 0):
			return false
	_envelope_shape.radius = _profile.parry_envelope_radius
	return true

## Cast each chord continuously, inflating by a convex-hull bound on curve error.
## The bound makes the sphere sweep cover the entire cubic span between casts.
func _cast_curve_section(world: World3D, control: PackedVector3Array, depth: int) -> bool:
	var chord_start: Vector3 = control[0]
	var chord_end: Vector3 = control[3]
	var curve_error := maxf(_distance_to_segment(control[1], chord_start, chord_end), _distance_to_segment(control[2], chord_start, chord_end))
	if curve_error > route_curve_error_tolerance and depth < route_max_subdivision_depth:
		var halves := _split_bezier(control)
		return _cast_curve_section(world, halves[0], depth + 1) and _cast_curve_section(world, halves[1], depth + 1)
	_envelope_shape.radius = _profile.parry_envelope_radius + curve_error
	_envelope_query.transform = Transform3D(Basis.IDENTITY, chord_start)
	_envelope_query.motion = chord_end - chord_start
	var cast: PackedFloat32Array = world.direct_space_state.cast_motion(_envelope_query)
	return cast.size() >= 2 and cast[0] >= 1.0 - 0.00001

func _bezier_subcurve(start_progress: float, end_progress: float) -> PackedVector3Array:
	var duration := end_progress - start_progress
	var start := bezier_point(_start, _control_a, _control_b, _finish, start_progress)
	var finish := bezier_point(_start, _control_a, _control_b, _finish, end_progress)
	return PackedVector3Array([
		start,
		start + _bezier_tangent(start_progress) * duration / 3.0,
		finish - _bezier_tangent(end_progress) * duration / 3.0,
		finish,
	])

func _bezier_tangent(progress: float) -> Vector3:
	var t := clampf(progress, 0.0, 1.0)
	var u := 1.0 - t
	return 3.0 * _u_control_a() * u * u + 6.0 * (_control_b - _control_a) * u * t + 3.0 * (_finish - _control_b) * t * t

func _u_control_a() -> Vector3:
	return _control_a - _start

func _split_bezier(control: PackedVector3Array) -> Array[PackedVector3Array]:
	var a := control[0].lerp(control[1], 0.5)
	var b := control[1].lerp(control[2], 0.5)
	var c := control[2].lerp(control[3], 0.5)
	var d := a.lerp(b, 0.5)
	var e := b.lerp(c, 0.5)
	var middle := d.lerp(e, 0.5)
	return [PackedVector3Array([control[0], a, d, middle]), PackedVector3Array([middle, e, c, control[3]])]

static func _distance_to_segment(point: Vector3, start: Vector3, finish: Vector3) -> float:
	var segment := finish - start
	var length_squared := segment.length_squared()
	var progress := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0) if length_squared > 0.000001 else 0.0
	return point.distance_to(start + segment * progress)

func _point_is_clear(point: Vector3) -> bool:
	if not is_instance_valid(_skeleton) or _envelope_query == null:
		return false
	var world := _skeleton.get_world_3d()
	if world == null:
		return false
	_envelope_query.transform = Transform3D(Basis.IDENTITY, point)
	_envelope_shape.radius = _profile.parry_envelope_radius
	_envelope_query.motion = Vector3.ZERO
	return world.direct_space_state.intersect_shape(_envelope_query, 1).is_empty()

func _cache_collision_exclusions() -> void:
	_collision_exclusions.clear()
	_add_collision_exclusions(_actor)
	if _attacker is Node:
		_add_collision_exclusions(_attacker as Node)

func _add_collision_exclusions(root: Node) -> void:
	if not is_instance_valid(root):
		return
	if root is CollisionObject3D:
		_collision_exclusions.append((root as CollisionObject3D).get_rid())
	for candidate in root.find_children("*", "CollisionObject3D", true, false):
		var collision_object := candidate as CollisionObject3D
		if is_instance_valid(collision_object):
			_collision_exclusions.append(collision_object.get_rid())

func _find_actor(node: Node) -> Node3D:
	var cursor := node
	while cursor != null:
		if cursor is CharacterBody3D:
			return cursor as Node3D
		cursor = cursor.get_parent()
	return null

func _find_tip_attachment(tip: Node3D, skeleton: Skeleton3D) -> BoneAttachment3D:
	var ancestor := tip.get_parent()
	while ancestor != null and ancestor != skeleton:
		if ancestor is BoneAttachment3D:
			var attachment := ancestor as BoneAttachment3D
			return attachment if attachment.get_skeleton() == skeleton else null
		ancestor = ancestor.get_parent()
	return null

func _refresh_tip_attachment() -> void:
	if is_instance_valid(_tip_attachment) and _tip_attachment.get_skeleton() == _skeleton:
		_tip_attachment.on_skeleton_update()

## Flattened rigs: rotate the bones a corrected joint would carry in a hierarchy
## by the same delta about that joint. No-op on hierarchical rigs (_carried empty).
func _carry(bone_id: int, delta: Quaternion, pivot: Vector3) -> void:
	for carried_id: int in _carried.get(bone_id, []):
		var pose := _skeleton.get_bone_global_pose(carried_id)
		pose.basis = Basis(delta) * pose.basis
		pose.origin = pivot + delta * (pose.origin - pivot)
		_skeleton.set_bone_global_pose_override(carried_id, pose, influence, true)

func _clear_overrides() -> void:
	if is_instance_valid(_skeleton):
		for bone_id in _overridden:
			_skeleton.set_bone_global_pose_override(bone_id, Transform3D.IDENTITY, 0.0, true)
		_skeleton.force_update_all_bone_transforms()
		_refresh_tip_attachment()

func _clear_action() -> void:
	is_moving = false
	_active = false
	_unit = null
	_profile = null
	_actor = null
	_attacker = null
	_tip_attachment = null
	_collision_exclusions.clear()
	_envelope_query = null
	_envelope_shape = null
	_bone_ids.clear()
	_carried.clear()
	_overridden.clear()
	_hand_bone_id = -1
	_shoulder_bone_id = -1
	_elbow_bone_id = -1
	_tip_in_hand = Transform3D.IDENTITY
	_start = Vector3.ZERO
	_control_a = Vector3.ZERO
	_control_b = Vector3.ZERO
	_finish = Vector3.ZERO
	_elapsed = 0.0
	_endpoint_settle_elapsed = 0.0
	_hold_elapsed = 0.0
	_recovery_elapsed = 0.0
	_last_progress = 0.0
	_is_recovering = false
	_for_execution = false
	_pending_contact_evaluation = false
	_execution_base_rotations.clear()
	_action_duration = 0.0
	_contact_hold_seconds = 0.0
	_recovery_seconds = 0.0
	desired_tip_world = Vector3.ZERO
	var modifier_callable := Callable(self, "_on_modifier_processed")
	if modification_processed.is_connected(modifier_callable):
		modification_processed.disconnect(modifier_callable)
	_skeleton = null

func _exit_tree() -> void:
	abort(&"scene_teardown")

func _smoothstep(value: float) -> float:
	return value * value * (3.0 - 2.0 * value)

func _yaw_correction_limit() -> float:
	if _profile == null or _profile.rig_calibration == null:
		return 0.0
	return _profile.rig_calibration.execution_yaw_correction_limit_degrees if _for_execution else _profile.rig_calibration.yaw_correction_limit_degrees
