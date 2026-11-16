@tool
class_name WeaponRigCalibration
extends Resource

## Hand/grip offset and authored arm-chain constraints for procedural contact.
@export_group("Arm Chain")
## Proximal arm joint used to preserve the authored elbow plane.
@export var shoulder_bone: StringName
## Elbow joint that the pole direction controls.
@export var elbow_bone: StringName
## Distal arm joint carrying the mounted weapon Grip.
@export var hand_bone: StringName
## Stable skeleton bone names ordered from the hand outward for bounded CCD.
@export var correction_bones: Array[StringName] = []
## Optional execution-only chain. Use this to exclude twist bones that distort the hand during a finisher.
## When empty, execution falls back to correction_bones.
@export var execution_correction_bones: Array[StringName] = []
## The rig was exported with a flattened bone hierarchy (e.g. LaceGame.glb), so no
## bone carries another. The solver then moves the chain itself: turning a correction
## bone also turns every chain bone nearer the hand, plus hand_followers, about that
## joint. Chains are still listed hand -> shoulder; parent-chain checks are skipped.
@export var flattened_rig: bool = false
## Flattened rigs only: bones that move rigidly with hand_bone (the fingers).
@export var hand_followers: Array[StringName] = []
## Pole direction in rig space; used to keep the elbow bend stable.
@export var pole_direction: Vector3 = Vector3.RIGHT
## Execution-only pole direction. Zero uses pole_direction; this keeps parry calibration independent.
@export var execution_pole_direction: Vector3 = Vector3.ZERO
## Airborne-execution pole direction. Zero uses execution_pole_direction or pole_direction.
@export var airborne_execution_pole_direction: Vector3 = Vector3.ZERO
## Expected bone segment lengths in skeleton-local metres, before scene/model scale.
@export_range(0.0, 3.0, 0.01, "suffix:m") var upper_arm_length: float = 0.35
@export_range(0.0, 3.0, 0.01, "suffix:m") var forearm_length: float = 0.35
## Allowed absolute difference between authored and live skeleton-local segment lengths.
@export_range(0.0, 0.2, 0.005, "suffix:m") var arm_length_tolerance: float = 0.08

@export_group("Reach and Correction")
## Minimum shoulder-to-target distance in world metres; zero disables the near bound.
@export_range(0.0, 3.0, 0.01, "suffix:m") var minimum_reach: float = 0.05
## Maximum shoulder-to-target distance in world metres.
@export_range(0.0, 5.0, 0.01, "suffix:m") var maximum_reach: float = 1.4
## Maximum actual Tip displacement from its animated start in world metres.
@export_range(0.0, 0.5, 0.001, "suffix:m") var grip_correction_limit: float = 0.12
## Maximum yaw offset from the currently evaluated animation pose per corrected bone.
@export_range(0.0, 45.0, 0.1, "suffix:deg") var yaw_correction_limit_degrees: float = 12.0
## Execution-only Tip travel from the evaluated pose; parry retains grip_correction_limit.
@export_range(0.0, 1.0, 0.01, "suffix:m") var execution_tip_correction_limit: float = 0.65
## Execution-only per-bone yaw correction. This never changes parry solver limits.
@export_range(0.0, 45.0, 0.1, "suffix:deg") var execution_yaw_correction_limit_degrees: float = 45.0

func validate() -> Array[String]:
	var errors: Array[String] = []
	if maximum_reach < minimum_reach:
		errors.append("WeaponRigCalibration maximum_reach must be >= minimum_reach")
	if upper_arm_length <= 0.0 or forearm_length <= 0.0:
		errors.append("WeaponRigCalibration arm lengths must be positive")
	if not is_finite(execution_tip_correction_limit) or execution_tip_correction_limit < 0.0 or execution_tip_correction_limit > 1.0:
		errors.append("WeaponRigCalibration execution_tip_correction_limit must be finite and in [0, 1] metre")
	if not is_finite(execution_yaw_correction_limit_degrees) or execution_yaw_correction_limit_degrees < 0.0 or execution_yaw_correction_limit_degrees > 45.0:
		errors.append("WeaponRigCalibration execution_yaw_correction_limit_degrees must be finite and in [0, 45] degrees")
	if pole_direction.is_zero_approx() or not pole_direction.is_finite():
		errors.append("WeaponRigCalibration pole_direction must be finite and nonzero")
	if not execution_pole_direction.is_finite():
		errors.append("WeaponRigCalibration execution_pole_direction must be finite")
	if not airborne_execution_pole_direction.is_finite():
		errors.append("WeaponRigCalibration airborne_execution_pole_direction must be finite")
	if shoulder_bone == &"" or elbow_bone == &"" or hand_bone == &"":
		errors.append("WeaponRigCalibration shoulder_bone, elbow_bone, and hand_bone are required")
	if not is_finite(arm_length_tolerance) or arm_length_tolerance < 0.0:
		errors.append("WeaponRigCalibration arm_length_tolerance must be finite and nonnegative")
	for chain in [correction_bones, execution_correction_bones]:
		var seen_bones: Dictionary = {}
		for bone_name in chain:
			if bone_name == &"" or seen_bones.has(bone_name):
				errors.append("WeaponRigCalibration correction chains must contain unique nonempty bone names")
				break
			seen_bones[bone_name] = true
	if not flattened_rig and not hand_followers.is_empty():
		errors.append("WeaponRigCalibration hand_followers are only used with flattened_rig")
	return errors

## Validate the named chain and authored segment lengths against the mounted rig.
## Bone lengths are measured in skeleton-local space so model scale does not alter calibration.
func validate_against_skeleton(skeleton: Skeleton3D) -> Array[String]:
	var errors := validate()
	if not is_instance_valid(skeleton):
		errors.append("WeaponRigCalibration requires a live Skeleton3D")
		return errors
	var shoulder_id := skeleton.find_bone(String(shoulder_bone))
	var elbow_id := skeleton.find_bone(String(elbow_bone))
	var hand_id := skeleton.find_bone(String(hand_bone))
	if shoulder_id < 0 or elbow_id < 0 or hand_id < 0:
		errors.append("WeaponRigCalibration bone names must exist on the mounted Skeleton3D")
		return errors
	if not flattened_rig and (not _is_ancestor(skeleton, shoulder_id, elbow_id) or not _is_ancestor(skeleton, elbow_id, hand_id)):
		errors.append("WeaponRigCalibration requires shoulder_bone -> elbow_bone -> hand_bone ancestry")
	errors.append_array(_validate_chain(skeleton, correction_bones, hand_id, elbow_id, shoulder_id, "correction_bones"))
	if not execution_correction_bones.is_empty():
		errors.append_array(_validate_chain(skeleton, execution_correction_bones, hand_id, elbow_id, shoulder_id, "execution_correction_bones"))
	for follower in hand_followers:
		if skeleton.find_bone(String(follower)) < 0:
			errors.append("WeaponRigCalibration hand_followers bone '%s' is missing from the mounted Skeleton3D" % follower)
	if errors.size() > 0:
		return errors
	var shoulder_pose := skeleton.get_bone_global_pose(shoulder_id)
	var elbow_pose := skeleton.get_bone_global_pose(elbow_id)
	var hand_pose := skeleton.get_bone_global_pose(hand_id)
	var measured_upper := shoulder_pose.origin.distance_to(elbow_pose.origin)
	var measured_forearm := elbow_pose.origin.distance_to(hand_pose.origin)
	if absf(measured_upper - upper_arm_length) > arm_length_tolerance:
		errors.append("WeaponRigCalibration upper_arm_length differs from the mounted rig by more than arm_length_tolerance")
	if absf(measured_forearm - forearm_length) > arm_length_tolerance:
		errors.append("WeaponRigCalibration forearm_length differs from the mounted rig by more than arm_length_tolerance")
	return errors

func _validate_chain(skeleton: Skeleton3D, bone_names: Array[StringName], hand_id: int, elbow_id: int, shoulder_id: int, property_name: String) -> Array[String]:
	var errors: Array[String] = []
	var correction_ids: Array[int] = []
	for bone_name in bone_names:
		var bone_id := skeleton.find_bone(String(bone_name))
		if bone_id < 0:
			errors.append("WeaponRigCalibration %s bone '%s' is missing from the mounted Skeleton3D" % [property_name, bone_name])
			return errors
		correction_ids.append(bone_id)
	if correction_ids.is_empty() or correction_ids[0] != hand_id:
		errors.append("WeaponRigCalibration %s must start at hand_bone and proceed outward" % property_name)
	else:
		for index in range(1, correction_ids.size()):
			if not flattened_rig and not _is_ancestor(skeleton, correction_ids[index], correction_ids[index - 1]):
				errors.append("WeaponRigCalibration %s must follow the hand-to-shoulder parent chain" % property_name)
				break
	if not correction_ids.has(elbow_id) or not correction_ids.has(shoulder_id):
		errors.append("WeaponRigCalibration %s must include elbow_bone and shoulder_bone" % property_name)
	return errors

static func _is_ancestor(skeleton: Skeleton3D, ancestor_id: int, bone_id: int) -> bool:
	var parent_id := bone_id
	while parent_id >= 0:
		if parent_id == ancestor_id:
			return true
		parent_id = skeleton.get_bone_parent(parent_id)
	return false
