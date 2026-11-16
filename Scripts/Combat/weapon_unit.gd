@tool
class_name WeaponUnit
extends Node3D

## Stable identity for this independently contactable part of the equipped weapon.
@export var unit_id: StringName
## Position-only marker at the authored strike tip. Rotation and scale are ignored.
@export var tip: Node3D
## Position-only marker at the grip used for reach and calibration measurements.
@export var grip: Node3D
## Optional second mount point, used to align a forearm-mounted weapon to its
## authored bone head while Grip remains aligned to the hand.
@export var grip_start: Node3D
## Optional end point for a hand grip. When reference bones are configured, this
## aligns to the midpoint between the thumb bone head and index bone tail.
@export var grip_end: Node3D
## Authored orientation reference. Its local axes align to the weapon's
## character_weapon_transform basis when this unit is mounted to a hand.
@export var orientation_guide: Node3D
## Skeleton bone whose head Grip Start should match. Empty means Grip Start is unused.
@export var grip_start_bone: StringName = &""
## Skeleton bone head used as the first endpoint for Grip End's target midpoint.
@export var grip_end_thumb_head_bone: StringName = &""
## Skeleton bone whose tail is the second endpoint for Grip End's target midpoint.
@export var grip_end_index_tail_bone: StringName = &""

func validate() -> Array[String]:
	var errors: Array[String] = []
	var label := _diagnostic_label()
	if unit_id == &"":
		errors.append("WeaponUnit %s has an empty unit_id" % label)
	if tip == null or not is_instance_valid(tip):
		errors.append("WeaponUnit %s requires an assigned Tip node" % label)
	elif tip.rotation != Vector3.ZERO or tip.scale != Vector3.ONE:
		errors.append("WeaponUnit %s Tip must be position-only (zero rotation, unit scale)" % label)
	if grip == null or not is_instance_valid(grip):
		errors.append("WeaponUnit %s requires an assigned Grip node" % label)
	elif grip.rotation != Vector3.ZERO or grip.scale != Vector3.ONE:
		errors.append("WeaponUnit %s Grip must be position-only (zero rotation, unit scale)" % label)
	if grip_start != null and is_instance_valid(grip_start):
		if grip_start.rotation != Vector3.ZERO or grip_start.scale != Vector3.ONE:
			errors.append("WeaponUnit %s Grip Start must be position-only (zero rotation, unit scale)" % label)
		if grip_start_bone == &"":
			errors.append("WeaponUnit %s Grip Start requires an assigned target bone" % label)
	if grip_end != null and is_instance_valid(grip_end):
		if grip_end.rotation != Vector3.ZERO or grip_end.scale != Vector3.ONE:
			errors.append("WeaponUnit %s Grip End must be position-only (zero rotation, unit scale)" % label)
		if grip_end_thumb_head_bone == &"" or grip_end_index_tail_bone == &"":
			errors.append("WeaponUnit %s Grip End requires thumb-head and index-tail target bones" % label)
	if orientation_guide == null or not is_instance_valid(orientation_guide):
		errors.append("WeaponUnit %s requires an assigned OrientationGuide node" % label)
	elif orientation_guide.scale != Vector3.ONE:
		errors.append("WeaponUnit %s OrientationGuide must use unit scale" % label)
	return errors

func _diagnostic_label() -> String:
	if is_inside_tree():
		return String(get_path())
	if unit_id != &"":
		return String(unit_id)
	return String(name) if not String(name).is_empty() else "unnamed"
