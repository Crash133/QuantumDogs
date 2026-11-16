@tool
class_name ComboPreview
extends Control

@onready var viewport: SubViewport = %PreviewViewport
@onready var world_root: Node3D = %PreviewWorld
@onready var overlay_root: Node3D = $PreviewLayout/PreviewViewportContainer/PreviewViewport/PreviewWorld/PreviewOverlays
@onready var target_center: Node3D = $PreviewLayout/PreviewViewportContainer/PreviewViewport/PreviewWorld/PreviewTargetDummy/ExecutionCenter
@onready var tick_control: SpinBox = %PreviewTick
@onready var status: Label = %PreviewStatus
@onready var play_button: Button = %PreviewPlayPause
@onready var cancel_action: OptionButton = %PreviewCancelAction

var _weapon_copy: WeaponData
var _runner := ComboRunner.new()
var _rig: Node3D
var _animation_player: AnimationPlayer
var _last_node: ComboNode
var _playing := false
var _play_accumulator := 0.0

func _ready() -> void:
	if not _runner.transition_started.is_connected(_on_transition_started):
		_runner.transition_started.connect(_on_transition_started)
	%PressLight.pressed.connect(press.bind(&"light"))
	%PressHeavy.pressed.connect(press.bind(&"heavy"))
	%PreviewStep.pressed.connect(step_preview)
	%PreviewStop.pressed.connect(stop)
	play_button.pressed.connect(_toggle_play)
	%PreviewCancel.pressed.connect(_try_cancel)
	tick_control.value_changed.connect(seek_tick)
	for action in [&"dodge", &"block_parry", &"switch", &"jump", &"execute"]:
		cancel_action.add_item(String(action).capitalize().replace("_", "/"))
		cancel_action.set_item_metadata(cancel_action.item_count - 1, action)
	set_process(false)

func _process(delta: float) -> void:
	if not _playing:
		return
	_play_accumulator += delta
	var stepped := 0
	while _play_accumulator >= 1.0 / 60.0 and stepped < 8:
		_play_accumulator -= 1.0 / 60.0
		_runner.step()
		_show_current_pose()
		stepped += 1
		if _runner.current_node == null:
			_playing = false
			play_button.text = "Play"
			set_process(false)
			break

## Load a deep-copied weapon graph and visual-only rig. No CombatController,
## HitManager, collision areas, timers or autoload references are instantiated.
func load_copy(weapon: WeaponData) -> Error:
	stop()
	if weapon == null or weapon.character_scene == null or weapon.graph == null:
		return ERR_INVALID_PARAMETER
	_weapon_copy = weapon.duplicate(true) as WeaponData
	if _weapon_copy == null or _weapon_copy.graph == null:
		return ERR_INVALID_DATA
	_rig = _weapon_copy.character_scene.instantiate() as Node3D
	if _rig == null:
		return ERR_CANT_CREATE
	_rig.name = "IsolatedComboPreviewRig"
	world_root.add_child(_rig)
	_mount_weapon_preview()
	var players := _rig.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		stop()
		return ERR_DOES_NOT_EXIST
	_animation_player = players[0] as AnimationPlayer
	_isolate_animation_libraries()
	_animation_player.set_process_callback(AnimationPlayer.ANIMATION_PROCESS_MANUAL)
	_runner.set_weapon(_weapon_copy)
	visible = true
	target_center.visible = true
	status.text = "Visual-only preview; copied graph; no damage, audio or global time"
	status.text = "Visual-only preview · copied graph · no damage or global time"
	return OK

func seek_tick(tick: int) -> void:
	if _animation_player == null or _runner.current_node == null:
		return
	_runner.node_tick = clampi(tick, 0, _runner.current_node.duration_ticks - 1)
	if tick_control.value != _runner.node_tick:
		tick_control.set_value_no_signal(_runner.node_tick)
	_show_current_pose()

func press(action: StringName) -> void:
	if _runner.press(action):
		_show_current_pose()

func step_preview(ticks: int = 1) -> void:
	for _index in maxi(0, ticks):
		_runner.step()
		if _runner.current_node != null:
			tick_control.set_value_no_signal(_runner.node_tick)
		_show_current_pose()

func stop() -> void:
	_playing = false
	_play_accumulator = 0.0
	set_process(false)
	if is_instance_valid(play_button):
		play_button.text = "Play"
	_runner.cancel()
	_last_node = null
	if is_instance_valid(_rig):
		_rig.queue_free()
	_rig = null
	_animation_player = null
	_weapon_copy = null
	_clear_overlay_nodes()
	visible = false
	if is_inside_tree():
		status.text = "Preview stopped"

func _show_current_pose() -> void:
	if _animation_player == null or _runner.current_node == null:
		_clear_overlay_nodes()
		return
	var combo_node := _runner.current_node
	var clip := _weapon_copy.animation_aliases.get(combo_node.animation, combo_node.animation)
	if not _animation_player.has_animation(clip):
		return
	if _last_node != combo_node:
		_animation_player.play(clip)
		_last_node = combo_node
	var animation := _animation_player.get_animation(clip)
	var clip_end := animation.length if combo_node.clip_end_seconds < 0.0 else minf(combo_node.clip_end_seconds, animation.length)
	var clip_span := maxf(0.0, clip_end - combo_node.clip_start_seconds)
	var fraction := float(_runner.node_tick) / float(maxi(1, combo_node.duration_ticks))
	_animation_player.seek(combo_node.clip_start_seconds + clip_span * fraction, true, true)
	_animation_player.advance(0.0)
	_update_hitbox_overlays(combo_node)
	if tick_control.value != combo_node.duration_ticks:
		tick_control.max_value = maxi(0, combo_node.duration_ticks - 1)
		tick_control.set_value_no_signal(_runner.node_tick)

func _on_transition_started(_transition: ComboTransition) -> void:
	_show_current_pose()

func _toggle_play() -> void:
	_playing = not _playing and _runner.current_node != null
	_play_accumulator = 0.0
	play_button.text = "Pause" if _playing else "Play"
	set_process(_playing)
	status.text = "Preview running at 60 Hz" if _playing else "Preview paused"

func _try_cancel() -> void:
	if cancel_action.selected < 0:
		return
	var action := StringName(cancel_action.get_item_metadata(cancel_action.selected))
	if _runner.can_cancel(action):
		_runner.cancel()
		_playing = false
		set_process(false)
		play_button.text = "Play"
		_clear_overlay_nodes()
		status.text = "Cancelled with %s; attack is back at Rest" % action
	else:
		status.text = "%s is outside its authored cancel window" % action

func _update_hitbox_overlays(combo_node: ComboNode) -> void:
	_clear_overlay_nodes()
	var tick := _runner.node_tick
	for spec in combo_node.hit_specs:
		if spec == null:
			continue
		var profile: HitboxProfile = _weapon_copy.hitbox_profiles.get(spec.profile)
		if profile == null:
			continue
		var sample_from := maxi(0, tick - mini(spec.linger_ticks, 18))
		var sampled_poses: Array[Transform3D] = []
		for sample_tick in range(sample_from, tick + 1):
			if not spec.is_active_at_tick(sample_tick):
				continue
			_evaluate_clip_tick(combo_node, sample_tick)
			var marker: Node3D = _find_marker(spec.marker_id) if spec.placement == HitSpec.Placement.WEAPON_MARKER else null
			var resolved := CombatHitAdapter.resolve_placement_pose(spec, _preview_actor_pose(), marker)
			if not bool(resolved[&"available"]):
				continue
			var pose: Transform3D = resolved[&"transform"]
			sampled_poses.append(pose)
			var age := tick - sample_tick
			var alpha := 0.58 if age == 0 else 0.18 * (1.0 - float(age) / float(maxi(1, spec.linger_ticks + 1)))
			_add_hit_volume(profile, pose, clampf(alpha, 0.04, 0.58), spec.marker_id)
		for pose_index in range(1, sampled_poses.size()):
			_add_travel_segment(sampled_poses[pose_index - 1].origin, sampled_poses[pose_index].origin, spec.marker_id, 0.25)
		_evaluate_clip_tick(combo_node, tick)
	_draw_contact_markers()

func _evaluate_clip_tick(combo_node: ComboNode, tick: int) -> void:
	var clip: StringName = _weapon_copy.animation_aliases.get(combo_node.animation, combo_node.animation)
	var animation := _animation_player.get_animation(clip)
	var clip_end := animation.length if combo_node.clip_end_seconds < 0.0 else minf(combo_node.clip_end_seconds, animation.length)
	var span := maxf(0.0, clip_end - combo_node.clip_start_seconds)
	var fraction := float(tick) / float(maxi(1, combo_node.duration_ticks))
	_animation_player.seek(combo_node.clip_start_seconds + span * fraction, true, true)
	_animation_player.advance(0.0)

func _preview_actor_pose() -> Transform3D:
	var direction := Vector3.FORWARD
	return Transform3D(Basis.looking_at(direction, Vector3.UP), _rig.global_position + Vector3.UP * 0.9 + direction * 0.9)

func _find_marker(marker_id: StringName) -> Node3D:
	if marker_id == &"" or _rig == null:
		return null
	for candidate in _rig.find_children("*", "WeaponHitboxMarker", true, false):
		var marker := candidate as WeaponHitboxMarker
		if marker.marker_id == marker_id:
			return marker
	return null

func _add_hit_volume(profile: HitboxProfile, pose: Transform3D, alpha: float, marker_id: StringName) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "PreviewHitVolume_%s" % marker_id
	var native := profile.to_native()
	var dimensions: Vector3 = native[&"size"]
	var pose_offset := Transform3D.IDENTITY
	match profile.shape:
		HitboxProfile.Shape.SPHERE:
			var mesh := SphereMesh.new()
			mesh.radius = dimensions.x
			mesh.height = dimensions.x * 2.0
			mesh_instance.mesh = mesh
		HitboxProfile.Shape.CAPSULE:
			var mesh := CapsuleMesh.new()
			mesh.radius = dimensions.x
			mesh.height = maxf(dimensions.z, dimensions.x * 2.0)
			mesh_instance.mesh = mesh
			pose_offset = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
		HitboxProfile.Shape.BOX:
			var mesh := BoxMesh.new()
			mesh.size = dimensions
			mesh_instance.mesh = mesh
		HitboxProfile.Shape.CONE:
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.0
			mesh.bottom_radius = dimensions.y
			mesh.height = dimensions.z
			mesh_instance.mesh = mesh
			pose_offset = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO)
		HitboxProfile.Shape.RING:
			var mesh := TorusMesh.new()
			mesh.inner_radius = maxf(0.01, dimensions.x - dimensions.y * 0.5)
			mesh.outer_radius = dimensions.x + dimensions.y * 0.5
			mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.22, 0.13, alpha)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	mesh_instance.material_override = material
	overlay_root.add_child(mesh_instance)
	mesh_instance.global_transform = Transform3D(pose.basis.orthonormalized(), pose.origin) * pose_offset

func _draw_contact_markers() -> void:
	if _weapon_copy == null or _rig == null:
		return
	for candidate in _rig.find_children("*", "WeaponUnit", true, false):
		var unit := candidate as WeaponUnit
		if unit.tip == null:
			continue
		var marker := _make_marker_mesh("PreviewActualTip_%s" % unit.unit_id, Color(1.0, 0.35, 0.1), 0.025)
		overlay_root.add_child(marker)
		marker.global_position = unit.tip.global_position
		if unit.grip != null:
			var grip_marker := _make_marker_mesh("PreviewGrip_%s" % unit.unit_id, Color(0.25, 0.75, 1.0), 0.018)
			overlay_root.add_child(grip_marker)
			grip_marker.global_position = unit.grip.global_position
		if unit.grip_start != null:
			var start_marker := _make_marker_mesh("PreviewGripStart_%s" % unit.unit_id, Color(0.35, 0.45, 1.0), 0.018)
			overlay_root.add_child(start_marker)
			start_marker.global_position = unit.grip_start.global_position
		if unit.grip_end != null:
			var end_marker := _make_marker_mesh("PreviewGripEnd_%s" % unit.unit_id, Color(0.2, 1.0, 0.9), 0.018)
			overlay_root.add_child(end_marker)
			end_marker.global_position = unit.grip_end.global_position
		if unit.orientation_guide != null:
			var origin := unit.orientation_guide.global_position
			_add_travel_segment(origin, origin + unit.orientation_guide.global_basis.x * 0.16, unit.unit_id, 1.0, Color(1.0, 0.25, 0.25))
			_add_travel_segment(origin, origin + unit.orientation_guide.global_basis.y * 0.16, unit.unit_id, 1.0, Color(0.25, 1.0, 0.35))
			_add_travel_segment(origin, origin + unit.orientation_guide.global_basis.z * 0.16, unit.unit_id, 1.0, Color(0.25, 0.55, 1.0))
	var center_marker := _make_marker_mesh("PreviewExecutionCenter", Color(0.2, 1.0, 0.48), 0.035)
	overlay_root.add_child(center_marker)
	center_marker.global_position = target_center.global_position

func _make_marker_mesh(marker_name: String, color: Color, radius: float) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	marker.name = marker_name
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	marker.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	marker.material_override = material
	return marker

func _add_travel_segment(from: Vector3, to: Vector3, marker_id: StringName, alpha: float, color: Color = Color(1.0, 0.62, 0.2)) -> void:
	var direction := to - from
	var distance := direction.length()
	if distance <= 0.001:
		return
	var segment := MeshInstance3D.new()
	segment.name = "PreviewTravel_%s" % marker_id
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.018, 0.018, distance)
	segment.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	segment.material_override = material
	overlay_root.add_child(segment)
	segment.global_transform = Transform3D(Basis.looking_at(direction.normalized(), Vector3.UP), (from + to) * 0.5)

func _clear_overlay_nodes() -> void:
	if not is_instance_valid(overlay_root):
		return
	for child in overlay_root.get_children():
		child.free()

func _isolate_animation_libraries() -> void:
	for library_name in _animation_player.get_animation_library_list():
		var source := _animation_player.get_animation_library(library_name)
		if source == null:
			continue
		var isolated := AnimationLibrary.new()
		for animation_name in source.get_animation_list():
			var animation := source.get_animation(animation_name).duplicate(true) as Animation
			for track_index in animation.get_track_count():
				if animation.track_get_type(track_index) in [Animation.TYPE_METHOD, Animation.TYPE_AUDIO]:
					animation.track_set_enabled(track_index, false)
			isolated.add_animation(animation_name, animation)
		_animation_player.remove_animation_library(library_name)
		_animation_player.add_animation_library(library_name, isolated)

func _mount_weapon_preview() -> void:
	if _weapon_copy.scene == null:
		return
	var unit_bones := _weapon_copy.character_unit_bones
	var required_bones: Array[StringName] = []
	if unit_bones.is_empty():
		if _weapon_copy.character_weapon_bone != &"":
			required_bones.append(_weapon_copy.character_weapon_bone)
	else:
		required_bones.assign(unit_bones.values())
	for candidate in _rig.find_children("*", "Skeleton3D", true, false):
		var skeleton := candidate as Skeleton3D
		var valid := true
		for bone in required_bones:
			if skeleton.find_bone(bone) < 0:
				valid = false
		if not valid:
			continue
		if unit_bones.is_empty():
			_attach_preview_weapon(skeleton, _weapon_copy.character_weapon_bone, &"", false)
		else:
			for unit_id: StringName in unit_bones:
				_attach_preview_weapon(skeleton, unit_bones[unit_id], unit_id, true)
		return
	if not required_bones.is_empty():
		status.text = "Preview rig is missing a configured weapon bone"

func _attach_preview_weapon(skeleton: Skeleton3D, bone: StringName, unit_id: StringName, paired: bool) -> void:
	var attachment := BoneAttachment3D.new()
	attachment.name = "PreviewHand_%s" % (unit_id if paired else &"primary")
	attachment.bone_name = bone
	skeleton.add_child(attachment)
	var root := _weapon_copy.scene.instantiate() as Node3D
	if root == null:
		attachment.queue_free()
		return
	root.name = "PreviewWeapon_%s" % (unit_id if paired else &"primary")
	var mount_unit: WeaponUnit
	if paired:
		var kept: WeaponUnit
		for candidate in root.find_children("*", "WeaponUnit", true, false):
			var unit := candidate as WeaponUnit
			if unit.unit_id == unit_id:
				kept = unit
			else:
				unit.get_parent().remove_child(unit)
				unit.free()
		if kept == null:
			root.free()
			attachment.free()
			return
		var combined_mesh := root.get_node_or_null("SourceMesh")
		if combined_mesh != null:
			root.remove_child(combined_mesh)
			combined_mesh.free()
		for mesh in kept.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).visible = true
		mount_unit = kept
	else:
		if _weapon_copy.contact_profile != null:
			for candidate in root.find_children("*", "WeaponUnit", true, false):
				var unit := candidate as WeaponUnit
				if unit.unit_id == _weapon_copy.contact_profile.execution_tip_id:
					mount_unit = unit
					break
		if mount_unit == null:
			var units := root.find_children("*", "WeaponUnit", true, false)
			if not units.is_empty():
				mount_unit = units[0] as WeaponUnit
	var hand_mount := _weapon_copy.hand_mount_for(mount_unit.unit_id) if mount_unit != null else _weapon_copy.character_weapon_transform
	root.transform = WeaponRigPresentation.solve_weapon_mount_transform(
		root, mount_unit, skeleton, bone, hand_mount, _weapon_copy.id)
	attachment.add_child(root)
	for collision in root.find_children("*", "CollisionObject3D", true, false):
		var object := collision as CollisionObject3D
		object.collision_layer = 0
		object.collision_mask = 0
	if not paired and _weapon_copy.contact_profile != null:
		for unit in root.find_children("*", "WeaponUnit", true, false):
			if unit.unit_id == _weapon_copy.contact_profile.execution_tip_id and unit.tip != null:
				_add_tip_marker(unit.tip)
	else:
		for unit in root.find_children("*", "WeaponUnit", true, false):
			if unit.unit_id == unit_id and unit.tip != null:
				_add_tip_marker(unit.tip)

func _add_tip_marker(tip: Node3D) -> void:
	var marker := MeshInstance3D.new()
	marker.name = "PreviewTipMarker"
	var mesh := SphereMesh.new()
	mesh.radius = 0.025
	mesh.height = 0.05
	marker.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.35, 0.1)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	marker.material_override = material
	tip.add_child(marker)
