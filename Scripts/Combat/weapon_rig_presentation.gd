class_name WeaponRigPresentation
extends Node

# A supplied rig stays paired with its own animation tracks. No retargeting,
# animation method tracks, root motion, or presentation state owns combat rules.
@export var player: Player
var visual: Node3D
var animation_player: AnimationPlayer
var _controller: CombatController
var _bridge: CombatAnimationBridge
var _pose_mixer: CombatPoseMixer
var _contact_motion: ProceduralContactMotion
var _weapon: WeaponData
var _weapon_scene: Node3D
var _weapon_units: Dictionary[StringName, WeaponUnit] = {}
var _hitbox_markers: Dictionary[StringName, Node3D] = {}
var _airborne: bool = false
var _landing: bool = false
var _reaction: bool = false
var _rig_mounted: bool = false

func _ready() -> void:
	call_deferred("_initialize")

func _initialize() -> void:
	if player == null or player.combat_controller == null:
		push_error("WeaponRigPresentation requires its Player and CombatController references.")
		return
	_controller = player.combat_controller
	_bridge = player.get_node("CombatAnimationBridge") as CombatAnimationBridge
	_pose_mixer = player.get_node("CombatPoseMixer") as CombatPoseMixer
	_contact_motion = player.get_node_or_null("ProceduralContactMotion") as ProceduralContactMotion
	_bridge.pose_mixer = _pose_mixer
	_controller.combo.weapon_changed.connect(_on_weapon_changed)
	_on_weapon_changed(&"", &"")

func _on_weapon_changed(_previous: StringName, _current: StringName) -> void:
	# _previous is &"" only for the initial bind at spawn (no equip clip then).
	_unmount_rig()
	_weapon = _controller.combo.weapon
	if _weapon == null:
		return
	if _weapon.character_scene == null:
		push_error("Weapon '%s' has no character_scene; assign the Lace rig (e.g. LaceGame.glb) in its WeaponData." % _weapon.id)
		return
	visual = _weapon.character_scene.instantiate() as Node3D
	if visual == null:
		push_error("Weapon '%s' character_scene requires a Node3D root" % _weapon.id)
		return
	visual.name = "CombatWeaponRig"
	player.model_pivot.add_child(visual)
	var players := visual.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		push_error("Weapon '%s' character_scene has no AnimationPlayer" % _weapon.id)
		_unmount_rig()
		return
	animation_player = players[0] as AnimationPlayer
	_bridge.animation_player = animation_player
	_bridge.animation_aliases = _weapon.animation_aliases
	_bridge.air_animation_aliases = _weapon.air_animation_aliases
	_bridge.fallback_animation = _weapon.fallback_animation
	var skeletons := visual.find_children("*", "Skeleton3D", true, false)
	var skeleton := skeletons[0] as Skeleton3D if not skeletons.is_empty() else null
	_pose_mixer.bind_rig(animation_player, skeleton, _weapon.referenced_clips())
	_mount_weapon()
	_rig_mounted = true
	_airborne = _controller.is_airborne
	_landing = false
	# A grounded switch plays the weapon's equip one-shot; _reaction holds it until it ends.
	_reaction = _previous != &"" and not _airborne and _play_pose(&"equip", true)
	if not _reaction:
		_play_pose(&"jump_idle" if _airborne else &"idle")

func _mount_weapon() -> void:
	if _weapon.scene != null and not _weapon.character_unit_bones.is_empty():
		_mount_units()
		return
	if _weapon.scene == null or _weapon.character_weapon_bone == &"":
		return
	for candidate in visual.find_children("*", "Skeleton3D", true, false):
		var skeleton := candidate as Skeleton3D
		if skeleton.find_bone(_weapon.character_weapon_bone) < 0:
			continue
		var hand := BoneAttachment3D.new()
		hand.name = "CombatWeaponHand"
		hand.bone_name = _weapon.character_weapon_bone
		skeleton.add_child(hand)
		_weapon_scene = _weapon.scene.instantiate() as Node3D
		if _weapon_scene == null:
			push_error("WeaponRigPresentation: weapon scene for '%s' must have a Node3D root" % _weapon.id)
			return
		var unit := _find_weapon_unit(_weapon_scene, _weapon.contact_profile.execution_tip_id if _weapon.contact_profile != null else &"")
		_weapon_scene.transform = _mount_transform_for_unit(_weapon_scene, unit, skeleton, _weapon.character_weapon_bone)
		hand.add_child(_weapon_scene)
		_cache_weapon_geometry(_weapon_scene)
		_mount_contact_motion(skeleton)
		return
	push_warning("Weapon rig is missing attachment bone: %s" % _weapon.character_weapon_bone)

## Dual-wield mount: one scene instance per unit bone, each keeping only its own unit.
func _mount_units() -> void:
	var skeleton := _find_skeleton_with_bones(_weapon.character_unit_bones.values())
	if skeleton == null:
		push_warning("Weapon rig is missing unit attachment bones for: %s" % _weapon.id)
		return
	_weapon_units.clear()
	_hitbox_markers.clear()
	_weapon_scene = null
	for unit_id: StringName in _weapon.character_unit_bones:
		var hand := BoneAttachment3D.new()
		hand.name = "CombatWeaponHand_%s" % unit_id
		hand.bone_name = _weapon.character_unit_bones[unit_id]
		skeleton.add_child(hand)
		var root := _weapon.scene.instantiate() as Node3D
		if root == null:
			push_error("WeaponRigPresentation: weapon scene for '%s' must have a Node3D root" % _weapon.id)
			return
		var kept: WeaponUnit
		for candidate in root.find_children("*", "WeaponUnit", true, false):
			var unit := candidate as WeaponUnit
			if unit.unit_id == unit_id:
				kept = unit
			else:
				unit.get_parent().remove_child(unit)
				unit.free()
		if kept == null:
			push_error("WeaponRigPresentation [%s] has no WeaponUnit '%s' for its unit bone" % [_weapon.id, unit_id])
			root.free()
			continue
		# Each hand carries only its own blade: swap the combined mesh for the unit mesh.
		var combined := root.get_node_or_null("SourceMesh")
		if combined != null:
			root.remove_child(combined)
			combined.free()
		for unit_mesh in kept.find_children("*", "MeshInstance3D", true, false):
			(unit_mesh as MeshInstance3D).visible = true
		root.transform = _mount_transform_for_unit(root, kept, skeleton, hand.bone_name)
		hand.add_child(root)
		if _weapon_scene == null:
			_weapon_scene = root
		_cache_weapon_geometry(root, false)
	_mount_contact_motion(skeleton)

## Solve the weapon root so Grip lands on the hand anchor and OrientationGuide's
## authored axes match WeaponData.character_weapon_transform. This is computed
## once when mounting, not in the frame loop.
static func mount_transform_for_alignment(
		target_hand_transform: Transform3D,
		grip_position_in_root: Vector3,
		guide_basis_in_root: Basis
	) -> Transform3D:
	var root_basis := target_hand_transform.basis * guide_basis_in_root.inverse()
	var root_origin := target_hand_transform.origin - root_basis * grip_position_in_root
	return Transform3D(root_basis, root_origin)

## Align two weapon markers to two distinct rig anchors without scaling the weapon.
## The guide reference supplies roll around the anchor axis.
static func mount_transform_for_two_points(
		target_start: Vector3,
		target_end: Vector3,
		source_start: Vector3,
		source_end: Vector3,
		source_reference_basis: Basis,
		target_reference_basis: Basis,
		anchor_on_end: bool = false
	) -> Transform3D:
	var source_axis := source_end - source_start
	var target_axis := target_end - target_start
	if source_axis.length_squared() < 0.000001 or target_axis.length_squared() < 0.000001:
		return Transform3D.IDENTITY
	var source_frame := frame_from_mount_axis(source_axis, source_reference_basis)
	var target_frame := frame_from_mount_axis(target_axis, target_reference_basis)
	var root_basis := target_frame * source_frame.inverse()
	var anchor_position := target_end if anchor_on_end else target_start
	var source_anchor := source_end if anchor_on_end else source_start
	return Transform3D(root_basis, anchor_position - root_basis * source_anchor)

## Build a stable right-handed frame whose local Y axis follows an anchor pair.
static func frame_from_mount_axis(axis: Vector3, reference_basis: Basis) -> Basis:
	var y_axis := axis.normalized()
	var x_axis := reference_basis.x - y_axis * reference_basis.x.dot(y_axis)
	if x_axis.length_squared() < 0.000001:
		x_axis = reference_basis.z - y_axis * reference_basis.z.dot(y_axis)
	if x_axis.length_squared() < 0.000001:
		var fallback := Vector3.RIGHT if absf(y_axis.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
		x_axis = fallback - y_axis * fallback.dot(y_axis)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	x_axis = y_axis.cross(z_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)

func _mount_transform_for_unit(root: Node3D, unit: WeaponUnit, skeleton: Skeleton3D, hand_bone: StringName) -> Transform3D:
	var hand_mount := _weapon.hand_mount_for(unit.unit_id) if unit != null else _weapon.character_weapon_transform
	return solve_weapon_mount_transform(root, unit, skeleton, hand_bone, hand_mount, _weapon.id)

## Shared by gameplay mounting and the isolated designer preview.
static func solve_weapon_mount_transform(
		root: Node3D,
		unit: WeaponUnit,
		skeleton: Skeleton3D,
		hand_bone: StringName,
		hand_mount: Transform3D,
		weapon_id: StringName = &"preview"
	) -> Transform3D:
	if root == null or unit == null or unit.grip == null or unit.orientation_guide == null:
		return hand_mount
	# Weapon scenes are calibrated before the instance is parented to its hand.
	# global_transform is invalid in that state and Godot returns identity, which
	# silently discards authored Grip/OrientationGuide offsets.
	var grip_in_root := transform_relative_to_root(root, unit.grip).origin
	var guide_in_root := transform_relative_to_root(root, unit.orientation_guide)
	if skeleton == null or skeleton.find_bone(hand_bone) < 0:
		return mount_transform_for_alignment(hand_mount, grip_in_root, guide_in_root.basis)
	var hand_pose := skeleton.get_bone_global_pose(skeleton.find_bone(hand_bone))
	var hand_inverse := hand_pose.affine_inverse()
	if unit.grip_start != null and unit.grip_start_bone != &"":
		var start_anchor := bone_endpoint_position(skeleton, unit.grip_start_bone, false, weapon_id)
		if bool(start_anchor[&"available"]):
			var start_position: Vector3 = start_anchor[&"position"]
			var start_in_hand: Vector3 = hand_mount * (hand_inverse * start_position)
			return mount_transform_for_two_points(
				start_in_hand,
				hand_mount.origin,
				transform_relative_to_root(root, unit.grip_start).origin,
				grip_in_root,
				guide_in_root.basis,
				hand_mount.basis,
				true)
	if unit.grip_end != null and unit.grip_end_thumb_head_bone != &"" and unit.grip_end_index_tail_bone != &"":
		var thumb_head := bone_endpoint_position(skeleton, unit.grip_end_thumb_head_bone, false, weapon_id)
		var index_tail := bone_endpoint_position(skeleton, unit.grip_end_index_tail_bone, true, weapon_id)
		if bool(thumb_head[&"available"]) and bool(index_tail[&"available"]):
			var thumb_position: Vector3 = thumb_head[&"position"]
			var index_position: Vector3 = index_tail[&"position"]
			var midpoint: Vector3 = (thumb_position + index_position) * 0.5
			var end_in_hand: Vector3 = hand_mount * (hand_inverse * midpoint)
			return mount_transform_for_two_points(
				hand_mount.origin,
				end_in_hand,
				grip_in_root,
				transform_relative_to_root(root, unit.grip_end).origin,
				guide_in_root.basis,
				hand_mount.basis)
	return mount_transform_for_alignment(hand_mount, grip_in_root, guide_in_root.basis)

static func bone_endpoint_position(skeleton: Skeleton3D, bone_name: StringName, use_tail: bool, weapon_id: StringName = &"preview") -> Dictionary:
	var bone_index := skeleton.find_bone(bone_name)
	if bone_index < 0:
		push_warning("WeaponRigPresentation [%s]: authored mount reference bone '%s' is missing" % [weapon_id, bone_name])
		return {&"available": false, &"position": Vector3.ZERO}
	var endpoint_index := bone_index
	if use_tail:
		var children := skeleton.get_bone_children(bone_index)
		if children.is_empty():
			push_warning("WeaponRigPresentation [%s]: Grip End index-tail bone '%s' has no child joint to define its tail" % [weapon_id, bone_name])
			return {&"available": false, &"position": Vector3.ZERO}
		endpoint_index = children[0]
	return {&"available": true, &"position": skeleton.get_bone_global_pose(endpoint_index).origin}

## Get a descendant's authored transform relative to an unmounted weapon root.
## This deliberately uses local transforms so it also works before tree entry.
static func transform_relative_to_root(root: Node3D, node: Node3D) -> Transform3D:
	if root == null or node == null:
		return Transform3D.IDENTITY
	var result := Transform3D.IDENTITY
	var cursor: Node3D = node
	while cursor != root:
		if cursor == null:
			push_error("WeaponRigPresentation: %s is not a descendant of %s" % [node, root])
			return Transform3D.IDENTITY
		result = cursor.transform * result
		cursor = cursor.get_parent() as Node3D
	return result

func _find_weapon_unit(root: Node3D, preferred_id: StringName) -> WeaponUnit:
	if root is WeaponUnit and (preferred_id == &"" or root.unit_id == preferred_id):
		return root as WeaponUnit
	for candidate in root.find_children("*", "WeaponUnit", true, false):
		var unit := candidate as WeaponUnit
		if unit != null and (preferred_id == &"" or unit.unit_id == preferred_id):
			return unit
	return null

func _find_skeleton_with_bones(bones: Array) -> Skeleton3D:
	for candidate in visual.find_children("*", "Skeleton3D", true, false):
		var skeleton := candidate as Skeleton3D
		var has_all := true
		for bone in bones:
			if skeleton.find_bone(bone) < 0:
				has_all = false
		if has_all:
			return skeleton
	return null

## Bind-time registry; animation ticks use dictionary lookups and never recurse.
## `reset` false adds to the registry (dual-wield mounts several roots).
func _cache_weapon_geometry(root: Node3D, reset: bool = true) -> void:
	if reset:
		_weapon_units.clear()
		_hitbox_markers.clear()
	for candidate in root.find_children("*", "Node", true, false):
		if candidate is WeaponUnit:
			var unit := candidate as WeaponUnit
			for error in unit.validate():
				push_warning("WeaponRigPresentation [%s]: %s" % [_weapon.id, error])
			if _weapon_units.has(unit.unit_id):
				push_error("WeaponRigPresentation [%s] has duplicate WeaponUnit ID '%s' at %s" % [_weapon.id, unit.unit_id, unit.get_path()])
			else:
				_weapon_units[unit.unit_id] = unit
		elif candidate is WeaponHitboxMarker:
			var marker := candidate as WeaponHitboxMarker
			if marker.marker_id == &"":
				push_error("WeaponRigPresentation [%s] has an empty WeaponHitboxMarker.marker_id at %s" % [_weapon.id, marker.get_path()])
			elif _hitbox_markers.has(marker.marker_id):
				push_error("WeaponRigPresentation [%s] has duplicate hitbox marker ID '%s' at %s" % [_weapon.id, marker.marker_id, marker.get_path()])
			else:
				_hitbox_markers[marker.marker_id] = marker

func get_weapon_unit(unit_id: StringName) -> WeaponUnit:
	return _weapon_units.get(unit_id) as WeaponUnit

## Shared solver used by parry and execution, mounted on the active skeleton.
func get_contact_motion() -> ProceduralContactMotion:
	return _contact_motion if is_instance_valid(_contact_motion) else null

func get_hitbox_marker(marker_id: StringName) -> Node3D:
	return _hitbox_markers.get(marker_id) as Node3D

func _mount_contact_motion(skeleton: Skeleton3D) -> void:
	if not is_instance_valid(_contact_motion):
		return
	if not is_instance_valid(skeleton):
		_contact_motion.abort(&"missing_skeleton")
		return
	if _contact_motion.get_parent() != skeleton:
		_contact_motion.reparent(skeleton, false)
	_contact_motion.transform = Transform3D.IDENTITY

func _physics_process(_delta: float) -> void:
	if _rig_mounted and not (is_instance_valid(visual) and is_instance_valid(animation_player)):
		_unmount_rig() # Rig freed externally.
	if not is_instance_valid(animation_player):
		return
	if _controller.state == CombatController.State.ATTACKING:
		_reaction = false
		_landing = false
		_airborne = _controller.is_airborne
		return # CombatAnimationBridge seeks this player's clip from combat ticks.
	if _controller.state in [CombatController.State.DEAD, CombatController.State.EXECUTING]:
		animation_player.pause() # No supplied death/execution clip; retain the pose.
		return
	if _reaction:
		if animation_player.is_playing():
			return
		_reaction = false
	var airborne := _controller.is_airborne
	if airborne and not _airborne:
		_play_pose(&"jump_start", true)
	elif not airborne and _airborne:
		_landing = true
		_play_pose(&"jump_end", true)
	_airborne = airborne
	if airborne:
		if animation_player.current_animation == _runtime_pose(&"jump_start") and animation_player.is_playing():
			return
		_play_pose(&"jump_idle")
		return
	if _landing:
		if animation_player.is_playing():
			return
		_landing = false
	match _controller.state:
		CombatController.State.BLOCKING: _play_pose(&"block")
		CombatController.State.PARRYING: _play_pose(&"parry")
		CombatController.State.MOVING, CombatController.State.DASHING: _play_pose(&"run")
		_: _play_pose(&"idle")

func on_damage_received() -> void:
	if not is_instance_valid(animation_player):
		return
	_bridge._restore_playback()
	_reaction = _play_pose(&"hit", true)

func _pose(key: StringName) -> StringName:
	return _weapon.poses.clip(key) if _weapon.poses != null else &""

func _runtime_pose(key: StringName) -> StringName:
	var clip := _pose(key)
	return _pose_mixer.runtime_clip_for(clip) if _pose_mixer != null and _pose_mixer.is_bound else clip

func _play_pose(key: StringName, restart: bool = false) -> bool:
	var clip := _pose(key)
	if clip == &"" or (not animation_player.has_animation(clip) and (_pose_mixer == null or not _pose_mixer.has_clip(clip))):
		return false
	if _pose_mixer != null and _pose_mixer.is_bound:
		return _pose_mixer.blend_to_clip(clip, 0.12, restart)
	if restart or animation_player.current_animation != clip or not animation_player.is_playing():
		animation_player.speed_scale = 1.0
		animation_player.play(clip)
		# update_only prevents an authored clip from applying gameplay side effects.
		animation_player.seek(0.0, true, true)
	return true

func _unmount_rig() -> void:
	_rig_mounted = false
	if is_instance_valid(_contact_motion):
		_contact_motion.abort(&"weapon_changed")
		if is_instance_valid(player) and _contact_motion.get_parent() != player:
			_contact_motion.reparent(player, false)
		_contact_motion.transform = Transform3D.IDENTITY
	_weapon_units.clear()
	_hitbox_markers.clear()
	_weapon_scene = null
	if _pose_mixer != null and _pose_mixer.is_bound:
		_pose_mixer.clear()
	if _bridge != null:
		_bridge._restore_playback()
		_bridge.animation_player = null
		_bridge.animation_aliases = {}
		_bridge.air_animation_aliases = {}
		_bridge.fallback_animation = &""
	if is_instance_valid(visual):
		# Detach now so the next rig keeps the "CombatWeaponRig" name.
		if visual.get_parent() != null:
			visual.get_parent().remove_child(visual)
		visual.queue_free()
	visual = null
	animation_player = null

func _exit_tree() -> void:
	# The Player/skeleton hierarchy is already being destroyed. Do not reparent
	# the modifier or detach the runtime rig while SceneTree is freeing children.
	if is_instance_valid(_contact_motion):
		_contact_motion.abort(&"scene_teardown")
	if _pose_mixer != null and _pose_mixer.is_bound:
		_pose_mixer.clear()
