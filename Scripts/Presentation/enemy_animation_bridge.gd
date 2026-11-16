class_name EnemyAnimationBridge
extends Node

## Visual follower of an enemy's role state. Samples Enemy/EnemyRoleController
## each physics frame and poses the imported rig by seeking with update_only,
## so clips can never call methods, play audio or move the body. It never calls
## request_attack(), step_physics() or hitbox methods.

signal missing_action(role: StringName, state: StringName)

@export var map: EnemyAnimationMap

@export_group("Reaction fallback pose")
## Temporary art: the rigs have no knockdown/get-up clips yet, so those states
## pose the "hit" clip and tilt the authored RoleVisual pivot instead. The pivot
## is restored after recovery, clear() and rebind; collision never moves.
@export_range(0.0, 30.0, 0.5, "suffix:deg") var max_recoil_degrees: float = 12.0
@export_range(0.0, 90.0, 0.5, "suffix:deg") var down_tilt_degrees: float = 65.0
## Flinch time that reaches full recoil (24 authored ticks).
@export_range(0.05, 2.0, 0.01, "suffix:s") var recoil_reference_seconds: float = 0.4
## Reduced motion: no recoil, and the down pose stays static until recovery.
@export var reduced_motion: bool = false
@export_group("Level of detail")
## Re-posing a rig is the dearest per-enemy cost, so far, idle-walking enemies are
## posed less often (time still advances, so loops stay in step). Attacks, reactions
## and anything near Lace are always posed every tick.
## Ticks between poses for an idle or walking enemy near Lace (2 = 30 Hz); 1 = every tick.
@export_range(1, 4, 1) var near_pose_interval: int = 2
@export_range(0.0, 100.0, 0.5, "suffix:m") var half_rate_distance: float = 10.0
@export_range(0.0, 100.0, 0.5, "suffix:m") var quarter_rate_distance: float = 20.0
## Enemies this far from Lace that are also off camera are posed at quarter rate.
@export_range(0.0, 100.0, 0.5, "suffix:m") var offscreen_check_distance: float = 6.0
var enemy: Enemy
var role: EnemyRoleController
var visual: Node3D
var animation_player: AnimationPlayer
var restored_speed_scale: float = 1.0
var unresolved_actions: PackedStringArray = PackedStringArray()
## Warn once per process, not once per spawned enemy (a horde spams the log otherwise).
static var _warned_clips: Dictionary = {}
var _loop_time: float = 0.0
var _loop_clip: StringName
var _rest_basis: Basis
var _tilt: float = 0.0
var _skipped_delta: float = 0.0

func _ready() -> void:
	var parent := get_parent() as Enemy
	if parent != null and map != null and not is_bound():
		bind(parent, parent.get_node_or_null("RoleController") as EnemyRoleController, parent.get_node_or_null("RoleVisual") as Node3D, map)

func bind(new_enemy: Enemy, new_role: EnemyRoleController, new_visual: Node3D, new_map: EnemyAnimationMap) -> void:
	clear()
	if new_enemy == null or new_role == null or new_visual == null or new_map == null:
		return
	var players := new_visual.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		push_warning("Enemy visual has no AnimationPlayer: %s" % new_visual.name)
		return
	enemy = new_enemy
	role = new_role
	visual = new_visual
	map = new_map
	animation_player = players[0] as AnimationPlayer
	restored_speed_scale = animation_player.speed_scale
	_rest_basis = visual.basis
	_tilt = 0.0
	animation_player.speed_scale = 0.0 # Time comes from the role, not the player.

func is_bound() -> bool:
	return is_instance_valid(animation_player) and is_instance_valid(enemy) and role != null

func clear() -> void:
	_set_tilt(0.0)
	if is_instance_valid(animation_player):
		animation_player.speed_scale = restored_speed_scale
	enemy = null
	role = null
	visual = null
	animation_player = null
	_loop_clip = &""

func _physics_process(delta: float) -> void:
	var _probe := ScriptCostProbe.start()
	_physics_process_body(delta)
	ScriptCostProbe.stop(&"enemy.anim_bridge", _probe)

func _physics_process_body(delta: float) -> void:
	if not is_bound():
		return
	if not enemy.is_alive():
		_pose(&"defeated", 1.0)
		clear()
		return
	var reaction := enemy.reactions.presentation_state() if enemy.reactions != null else (&"flinch" if enemy.stun > 0.0 else &"none")
	if reaction == &"none" and role.state == &"pursue" and not _lod_due():
		_skipped_delta += delta
		return
	delta += _skipped_delta
	_skipped_delta = 0.0
	_set_tilt(_tilt_for(reaction))
	if reaction == &"knockdown" or reaction == &"get_up":
		_loop(_reaction_clip_state(reaction), delta)
	elif enemy.is_staggered():
		_loop(&"stagger", delta)
	elif reaction == &"flinch":
		_loop(&"hit", delta)
	elif role.state in [&"windup", &"attack", &"recovery"]:
		_pose(role.state, _attack_progress())
	elif Vector2(enemy.velocity.x, enemy.velocity.z).length() > map.walk_speed_threshold:
		_loop(&"pursue", delta)
	else:
		_loop(&"idle", delta)

## True on the ticks this enemy should be re-posed: every tick near Lace, every 2nd
## or 4th when far or off camera. The phase is spread by instance id so a crowd
## never updates on the same frame.
func _lod_due() -> bool:
	var target := enemy.player
	if not is_instance_valid(target):
		return true
	var offset := enemy.global_position - target.global_position
	var distance_squared := offset.length_squared()
	var interval := near_pose_interval
	if distance_squared > quarter_rate_distance * quarter_rate_distance:
		interval = 4
	elif distance_squared > half_rate_distance * half_rate_distance:
		interval = 2
	elif near_pose_interval == 1 and distance_squared > offscreen_check_distance * offscreen_check_distance:
		var camera := enemy.get_viewport().get_camera_3d()
		if camera != null and not camera.is_position_in_frustum(enemy.global_position + Vector3.UP):
			interval = 4
	return interval == 1 or (Engine.get_physics_frames() + enemy.get_instance_id()) % interval == 0

## knockdown/get_up use their own clip only when the map names a real one;
## otherwise the "hit" clip plus the pivot tilt, logged once per role/state.
func _reaction_clip_state(reaction: StringName) -> StringName:
	if map.clips.has(reaction) and animation_player.has_animation(map.clips[reaction]):
		return reaction
	var key := "%s/%s->hit+pivot" % [map.role, reaction]
	if not unresolved_actions.has(key):
		unresolved_actions.append(key)
		if OS.is_debug_build() and not _warned_clips.has(key):
			_warned_clips[key] = true
			push_warning("Enemy reaction clip missing, using fallback: %s" % key)
		missing_action.emit(map.role, reaction)
	return &"hit"

## Presentation-only pitch of the visual pivot, in radians (backward = positive).
func _tilt_for(reaction: StringName) -> float:
	match reaction:
		&"knockdown":
			return deg_to_rad(down_tilt_degrees)
		&"get_up":
			if reduced_motion:
				return deg_to_rad(down_tilt_degrees)
			return deg_to_rad(down_tilt_degrees) * enemy.reactions.get_up_fraction()
		&"flinch":
			if reduced_motion:
				return 0.0
			return deg_to_rad(max_recoil_degrees) * clampf(enemy.stun / recoil_reference_seconds, 0.0, 1.0)
	return 0.0

func _set_tilt(radians: float) -> void:
	if not is_instance_valid(visual) or is_equal_approx(radians, _tilt):
		return
	_tilt = radians
	visual.basis = _rest_basis * Basis(Vector3.RIGHT, -radians)

## 0..1 across the whole attack clip, with the role's active window mapped
## onto map.strike_window so the strike pose matches the live hitbox.
func _attack_progress() -> float:
	var attack := role.definition.attack
	var span: Vector2
	var total: int
	match role.state:
		&"windup":
			span = Vector2(0.0, map.strike_window.x)
			total = attack.windup_ticks
		&"attack":
			span = map.strike_window
			total = attack.active_ticks
		_:
			span = Vector2(map.strike_window.y, 1.0)
			total = attack.recovery_ticks
	var elapsed := clampf(float(total - role.ticks_left) / float(maxi(1, total)), 0.0, 1.0)
	return lerpf(span.x, span.y, elapsed)

func _resolve(state: StringName) -> StringName:
	var clip := map.clip_for(state)
	if animation_player.has_animation(clip):
		return clip
	var key := "%s/%s" % [map.role, state]
	if not unresolved_actions.has(key):
		unresolved_actions.append(key)
		if OS.is_debug_build():
			push_warning("Enemy action missing, using fallback '%s': %s" % [map.fallback, key])
		missing_action.emit(map.role, state)
	return map.fallback if animation_player.has_animation(map.fallback) else &""

func _pose(state: StringName, progress: float) -> void:
	var clip := _resolve(state)
	if clip == &"":
		return
	if animation_player.current_animation != clip:
		animation_player.play(clip)
		animation_player.speed_scale = 0.0
	_loop_clip = &""
	animation_player.seek(animation_player.current_animation_length * progress, true, true)

func _loop(state: StringName, delta: float) -> void:
	var clip := _resolve(state)
	if clip == &"":
		return
	if clip != _loop_clip:
		_loop_clip = clip
		_loop_time = 0.0
		animation_player.play(clip)
		animation_player.speed_scale = 0.0
	_loop_time += delta
	var length := maxf(0.001, animation_player.current_animation_length)
	animation_player.seek(fmod(_loop_time, length), true, true)
