class_name CombatAnimationBridge
extends Node

signal missing_clip(weapon_id: StringName, animation: StringName)

## WeaponRigPresentation sets these from the equipped WeaponData when it mounts a rig.
@export var fallback_animation: StringName
@export var animation_aliases: Dictionary = {}
## Checked before animation_aliases when an attack starts airborne (see WeaponData).
@export var air_animation_aliases: Dictionary = {}
@export var controller: CombatController
## The mounted weapon rig's player; WeaponRigPresentation assigns it at runtime.
@export var animation_player: AnimationPlayer
@export var pose_mixer: CombatPoseMixer
var requested_animation: StringName
var using_fallback: bool = false
## The current attack resolved through air_animation_aliases.
var using_air_clip: bool = false
var unresolved_animations: PackedStringArray = PackedStringArray()
var _active: bool = false
var _serial: int = -1
var _last_transition: ComboTransition

func _ready() -> void:
	if controller != null and not controller.combo.transition_started.is_connected(_on_transition_started):
		controller.combo.transition_started.connect(_on_transition_started)

func _on_transition_started(transition: ComboTransition) -> void:
	_last_transition = transition

func _physics_process(delta: float) -> void:
	var _probe := ScriptCostProbe.start()
	_physics_process_body(delta)
	ScriptCostProbe.stop(&"player.anim_bridge", _probe)

func _physics_process_body(delta: float) -> void:
	if controller == null or not is_instance_valid(animation_player) or pose_mixer == null or not pose_mixer.is_bound:
		return
	var node := controller.combo.current_node
	if node == null or controller.state != CombatController.State.ATTACKING:
		_restore_playback()
		pose_mixer.advance_presentation(delta)
		return
	if not _active:
		_active = true
		_serial = -1
	if controller.combo.attack_serial != _serial:
		_serial = controller.combo.attack_serial
		requested_animation = node.animation
		var clip := _resolve_clip(node.animation)
		if using_fallback:
			_report_missing_clip(node.animation)
		if not pose_mixer.has_clip(clip):
			_restore_playback()
			return
		var transition := _last_transition
		if transition == null or transition.serial != _serial:
			transition = ComboTransition.new(&"", node.id, -1, _serial, 0)
		# The node's clip span is authored for its ground clip; jump clips play whole.
		var span := Vector2(0.0, -1.0) if using_air_clip else Vector2(node.clip_start_seconds, node.clip_end_seconds)
		pose_mixer.begin_transition(transition, clip, span, node.duration_ticks)
	pose_mixer.evaluate_tick(controller.combo.node_tick, node.duration_ticks, delta)

func _resolve_clip(animation: StringName) -> StringName:
	using_air_clip = controller.is_airborne and air_animation_aliases.has(animation)
	var aliases := air_animation_aliases if using_air_clip else animation_aliases
	var clip := StringName(aliases.get(animation, animation))
	using_fallback = not animation_player.has_animation(clip)
	if using_fallback:
		clip = fallback_animation
	return clip

func _report_missing_clip(animation: StringName) -> void:
	var key := "%s/%s" % [controller.combo.weapon.id, animation]
	if unresolved_animations.has(key):
		return
	unresolved_animations.append(key)
	if OS.is_debug_build():
		push_warning("Combat clip missing, using fallback '%s': %s" % [fallback_animation, key])
	missing_clip.emit(controller.combo.weapon.id, animation)

func _restore_playback() -> void:
	if not _active:
		return
	_active = false
	_serial = -1

func _exit_tree() -> void:
	_restore_playback()
