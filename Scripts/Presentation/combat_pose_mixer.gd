class_name CombatPoseMixer
extends Node

## One AnimationPlayer is driven manually at the gameplay physics boundary.
## Runtime libraries are private copies; imported/shared animation resources remain untouched.
const SAFE_LIBRARY_PREFIX: StringName = &"__combat_pose_"
const MAX_TRACKS_PER_CLIP: int = 2048
const MAX_CACHED_CLIPS_PER_RIG: int = 128
const MAX_CACHED_TRACKS_PER_RIG: int = 65536 # each clip is padded with every bone; LaceGame (65 bones) needs ~195 tracks per clip
const TICK_RATE: float = 60.0
## Sanitized copies keyed by source clip + skeleton, shared across rig re-binds:
## imported clips are shared between rig instances and never mutated, so a weapon
## switch reuses them instead of re-sanitizing every clip (that took over a second).
static var _sanitized_cache: Dictionary = {}

var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var is_bound: bool = false
var _safe_library_names: Array[StringName] = []
var _safe_clips: Dictionary[StringName, StringName] = {}
var _previous_process_mode: int = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
var _previous_method_mode: int = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_DEFERRED
var _previous_root_motion_track: NodePath = NodePath()
var _previous_speed_scale: float = 1.0
var _active_clip: StringName = &""
var _active_span: Vector2 = Vector2.ZERO
var _active_duration_ticks: int = 1
var _last_evaluated_tick: int = 0

## Bind to the current weapon rig and cache sanitized runtime-only clip copies.
## A non-empty only_clips caches just those clip names (a shared rig carries every
## weapon's clips; caching all of them would exceed the track budget).
func bind_rig(player: AnimationPlayer, bound_skeleton: Skeleton3D, only_clips: PackedStringArray = PackedStringArray()) -> void:
	clear()
	if not is_instance_valid(player):
		push_error("CombatPoseMixer.bind_rig requires a live AnimationPlayer")
		return
	animation_player = player
	skeleton = bound_skeleton if is_instance_valid(bound_skeleton) else null
	_previous_process_mode = player.callback_mode_process
	_previous_method_mode = player.callback_mode_method
	_previous_root_motion_track = player.root_motion_track
	_previous_speed_scale = player.speed_scale
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_DEFERRED
	player.root_motion_track = NodePath()
	var root := player.get_node_or_null(player.root_node)
	if root == null:
		root = player.get_parent()
	var skeleton_path := root.get_path_to(skeleton) if skeleton != null and root != null else NodePath()
	var cached_clips := 0
	var cached_tracks := 0
	for source_library_name in player.get_animation_library_list():
		var source_library := player.get_animation_library(source_library_name)
		if source_library == null:
			continue
		var library_suffix := "unnamed" if source_library_name == &"" else "named_%s" % source_library_name
		var safe_library_name := StringName("%s%s" % [SAFE_LIBRARY_PREFIX, library_suffix])
		if player.has_animation_library(safe_library_name):
			player.remove_animation_library(safe_library_name)
		var safe_library := AnimationLibrary.new()
		for animation_name in source_library.get_animation_list():
			if not only_clips.is_empty() and not only_clips.has(String(animation_name)):
				continue
			if cached_clips >= MAX_CACHED_CLIPS_PER_RIG:
				push_warning("CombatPoseMixer stopped caching after its bounded %d-clip rig limit" % MAX_CACHED_CLIPS_PER_RIG)
				break
			var source_animation := source_library.get_animation(animation_name)
			var safe_animation := _sanitize_animation(source_animation, skeleton_path)
			if safe_animation == null:
				continue
			if cached_tracks + safe_animation.get_track_count() > MAX_CACHED_TRACKS_PER_RIG:
				push_warning("CombatPoseMixer rejected clip '%s': cached rig would exceed its bounded %d-track limit" % [source_animation.resource_name, MAX_CACHED_TRACKS_PER_RIG])
				continue
			var error := safe_library.add_animation(animation_name, safe_animation)
			if error != OK:
				push_error("CombatPoseMixer could not cache clip %s: error %d" % [animation_name, error])
				continue
			var original_path := String(animation_name) if source_library_name == &"" else "%s/%s" % [source_library_name, animation_name]
			_safe_clips[StringName(original_path)] = StringName("%s/%s" % [safe_library_name, animation_name])
			if source_library_name == &"":
				_safe_clips[animation_name] = StringName("%s/%s" % [safe_library_name, animation_name])
			cached_clips += 1
			cached_tracks += safe_animation.get_track_count()
		var error := player.add_animation_library(safe_library_name, safe_library)
		if error != OK:
			push_error("CombatPoseMixer could not install runtime library %s: error %d" % [safe_library_name, error])
			continue
		_safe_library_names.append(safe_library_name)
	is_bound = not _safe_library_names.is_empty()
	if not is_bound:
		push_error("CombatPoseMixer found no usable animation libraries on the supplied rig")

## Start a fixed-tick attack clip. Standard custom blending starts from the currently
## evaluated pose, so an interrupted blend composes from its live pose.
func begin_transition(transition: ComboTransition, clip: StringName, span: Vector2, duration_ticks: int = 60) -> void:
	if not is_bound or transition == null:
		return
	var safe_clip := _safe_clip(clip)
	if safe_clip == &"":
		push_error("CombatPoseMixer cannot resolve clip '%s' on the bound rig" % clip)
		return
	_active_clip = safe_clip
	_active_span = span
	_active_duration_ticks = maxi(1, duration_ticks)
	var playback_rate := _playback_rate(safe_clip, span, _active_duration_ticks)
	# AnimationPlayer's normal custom blend preserves the old clip pose while the
	# incoming clip advances at the authored rate. Convert the window to clip time.
	var blend_seconds := float(maxi(0, transition.blend_ticks)) / TICK_RATE * playback_rate
	var clip_length := _clip_length(safe_clip)
	var start_time := clampf(span.x, 0.0, clip_length)
	var end_time := clip_length if span.y < 0.0 else clampf(span.y, start_time, clip_length)
	animation_player.play_section(safe_clip, start_time, end_time, blend_seconds, playback_rate, false)
	animation_player.speed_scale = 1.0
	_last_evaluated_tick = 0

## Advance the selected clip span by the authored node-tick delta. Damage windows
## remain owned by ComboRunner and are never lengthened by presentation blending.
func evaluate_tick(node_tick: int, duration_ticks: int, delta_seconds: float) -> void:
	if not is_bound or _active_clip == &"":
		return
	_active_duration_ticks = maxi(1, duration_ticks)
	var length := _clip_length(_active_clip)
	var start_time := clampf(_active_span.x, 0.0, length)
	var end_time := length if _active_span.y < 0.0 else clampf(_active_span.y, start_time, length)
	animation_player.speed_scale = 1.0
	# Seeking forces a track evaluation and cancels AnimationPlayer's capture blend.
	# Physics advances the clip once per authored combo tick, preserving both the
	# blend and the 60 Hz attack timeline. Hit stop leaves node_tick unchanged.
	var elapsed_ticks := maxi(0, node_tick - _last_evaluated_tick)
	if elapsed_ticks > 0 and delta_seconds > 0.0:
		animation_player.advance(delta_seconds * float(elapsed_ticks))
	_last_evaluated_tick = maxi(_last_evaluated_tick, node_tick)

## Blend back to a locomotion/reaction pose after attack cancellation or completion.
func blend_to_clip(clip: StringName, blend_seconds: float = 0.1, restart: bool = false) -> bool:
	if not is_bound:
		return false
	var safe_clip := _safe_clip(clip)
	if safe_clip == &"":
		return false
	if not restart and animation_player.current_animation == safe_clip and animation_player.is_playing():
		return true
	_active_clip = safe_clip
	_active_span = Vector2(0.0, _clip_length(safe_clip))
	animation_player.play(safe_clip, blend_seconds, 1.0)
	animation_player.speed_scale = 1.0
	return true

## Whether an authored source clip was copied into this rig's safe runtime library.
func has_clip(clip: StringName) -> bool:
	return _safe_clip(clip) != &""

## Return the private library name used for a source clip, or an empty name.
func runtime_clip_for(clip: StringName) -> StringName:
	return _safe_clip(clip)

## Advance non-combat poses while the caller owns the presentation physics step.
func advance_presentation(delta_seconds: float) -> void:
	if is_bound and delta_seconds > 0.0:
		animation_player.speed_scale = 1.0
		animation_player.advance(delta_seconds)

func clear() -> void:
	var player := animation_player
	if is_instance_valid(player):
		player.stop(true)
		for library_name in _safe_library_names:
			if player.has_animation_library(library_name):
				player.remove_animation_library(library_name)
		player.speed_scale = _previous_speed_scale
		player.callback_mode_process = _previous_process_mode
		player.callback_mode_method = _previous_method_mode
		player.root_motion_track = _previous_root_motion_track
		player.clear_caches()
	animation_player = null
	skeleton = null
	is_bound = false
	_safe_library_names.clear()
	_safe_clips.clear()
	_active_clip = &""
	_active_span = Vector2.ZERO
	_active_duration_ticks = 1
	_last_evaluated_tick = 0

func _sanitize_animation(source: Animation, skeleton_path: NodePath) -> Animation:
	if source == null:
		return null
	var cache_key := "%d|%s|%d" % [source.get_instance_id(), skeleton_path, skeleton.get_bone_count() if skeleton != null else 0]
	if _sanitized_cache.has(cache_key):
		return _sanitized_cache[cache_key]
	var animation := source.duplicate(true) as Animation
	if animation == null:
		return null
	for track in range(animation.get_track_count() - 1, -1, -1):
		if _must_remove_track(animation, track, skeleton_path):
			animation.remove_track(track)
	if skeleton != null and not skeleton_path.is_empty():
		_fill_unkeyed_bones(animation, skeleton_path)
	if animation.get_track_count() > MAX_TRACKS_PER_CLIP:
		push_error("CombatPoseMixer rejected clip '%s': %d tracks exceeds the bounded %d-track limit" % [source.resource_name, animation.get_track_count(), MAX_TRACKS_PER_CLIP])
		return null
	_sanitized_cache[cache_key] = animation
	return animation

func _must_remove_track(animation: Animation, track: int, skeleton_path: NodePath) -> bool:
	var kind := animation.track_get_type(track)
	if kind in [Animation.TYPE_METHOD, Animation.TYPE_AUDIO, Animation.TYPE_ANIMATION]:
		return true
	var path := animation.track_get_path(track)
	if not _is_transform_track(kind):
		return false
	if path == _previous_root_motion_track or _targets_animation_root(path):
		return true
	if skeleton != null and _targets_root_bone(path, skeleton_path):
		return true
	return false

func _is_transform_track(kind: int) -> bool:
	return kind in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D, Animation.TYPE_VALUE]

func _targets_animation_root(path: NodePath) -> bool:
	var text := String(path)
	var node_path := text.get_slice(":", 0)
	# Animation paths are relative to AnimationPlayer.root_node. A single-segment
	# child path (for example Pose:position) is still a child, not body root motion.
	return node_path in ["", "."] or node_path.begins_with("..")

func _targets_root_bone(path: NodePath, skeleton_path: NodePath) -> bool:
	var text := String(path)
	var node_path := text.get_slice(":", 0)
	if node_path != String(skeleton_path):
		return false
	var bone_name := text.get_slice(":", 1) if text.contains(":") else ""
	var bone_index := skeleton.find_bone(bone_name)
	# A hierarchy root carries root motion. In a flattened rig (LaceGame.glb) every bone
	# is parentless but childless, and stripping them would freeze the whole clip.
	return bone_index >= 0 and skeleton.get_bone_parent(bone_index) < 0 and not skeleton.get_bone_children(bone_index).is_empty()

func _fill_unkeyed_bones(animation: Animation, skeleton_path: NodePath) -> void:
	# One pass over the existing tracks instead of a track scan per bone and channel.
	var keyed: Dictionary = {}
	for track in animation.get_track_count():
		keyed["%d|%s" % [animation.track_get_type(track), animation.track_get_path(track)]] = true
	for bone_index in skeleton.get_bone_count():
		var bone_name := String(skeleton.get_bone_name(bone_index))
		var path := NodePath("%s:%s" % [skeleton_path, bone_name])
		var rest := skeleton.get_bone_rest(bone_index)
		for channel in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			if keyed.has("%d|%s" % [channel, path]):
				continue
			var track := animation.add_track(channel)
			animation.track_set_path(track, path)
			var value: Variant = rest.origin
			if channel == Animation.TYPE_ROTATION_3D:
				value = rest.basis.get_rotation_quaternion()
			elif channel == Animation.TYPE_SCALE_3D:
				value = rest.basis.get_scale()
			animation.track_insert_key(track, 0.0, value)

func _has_track(animation: Animation, path: NodePath, kind: int) -> bool:
	for track in animation.get_track_count():
		if animation.track_get_type(track) == kind and animation.track_get_path(track) == path:
			return true
	return false

func _safe_clip(clip: StringName) -> StringName:
	if _safe_clips.has(clip):
		return _safe_clips[clip]
	return &""

func _clip_length(clip: StringName) -> float:
	var animation := animation_player.get_animation(clip) if is_instance_valid(animation_player) else null
	return animation.length if animation != null else 0.0

func _playback_rate(clip: StringName, span: Vector2, duration_ticks: int) -> float:
	var length := _clip_length(clip)
	var start_time := clampf(span.x, 0.0, length)
	var end_time := length if span.y < 0.0 else clampf(span.y, start_time, length)
	return maxf(0.0, (end_time - start_time) * TICK_RATE / float(maxi(1, duration_ticks)))

func _exit_tree() -> void:
	clear()
