class_name ParryPresentationController
extends Node

## Presents an already-confirmed melee parry. Defense, meter changes and enemy
## parry callbacks remain owned by CombatController/HitResolver.

@export var player: Player
@export var motion: ProceduralContactMotion
@export var rig_presentation: WeaponRigPresentation

var _time_domains: Node
var _time_token: int = -1
var _active_context: HitContactContext
var _active_unit: WeaponUnit
var _fallback_point: Vector3 = Vector3.ZERO
var _has_fallback_point: bool = false
var _fallback_action_id: int = 1
var _last_physics_frame: int = -1
var _presented_action_ids: Dictionary = {}
var _pending_context: HitContactContext
var _selection_scheduled: bool = false

func _ready() -> void:
	_time_domains = get_tree().get_first_node_in_group("combat_time_domains") as Node
	if motion != null:
		if not motion.contact_reached.is_connected(_on_contact_reached):
			motion.contact_reached.connect(_on_contact_reached)
		if not motion.ended.is_connected(_on_motion_ended):
			motion.ended.connect(_on_motion_ended)

## Queue the presentation for a successful melee defense. Projectiles and
## missing contexts intentionally retain their immediate authoritative result.
func on_confirmed_parry(context: HitContactContext) -> void:
	if context == null or not context.melee or player == null or not is_instance_valid(player):
		return
	if motion != null and motion.is_moving:
		return
	var tick := _contact_tick(context)
	if tick <= _last_physics_frame:
		return
	if _pending_context == null or _contact_precedes(context, _pending_context):
		_pending_context = context
	if _selection_scheduled:
		return
	_selection_scheduled = true
	call_deferred("_flush_pending_contact")

func _flush_pending_contact() -> void:
	_selection_scheduled = false
	var context := _pending_context
	_pending_context = null
	if context == null or player == null or not is_instance_valid(player) or (motion != null and motion.is_moving):
		return
	var tick := _contact_tick(context)
	if tick <= _last_physics_frame:
		return
	_last_physics_frame = tick
	_active_context = context
	_active_unit = null
	_fallback_point = context.world_point if context.has_world_point else Vector3.ZERO
	_has_fallback_point = context.has_world_point
	var weapon := player.combat_controller.combo.weapon if player.combat_controller != null else null
	var profile: WeaponContactProfile = weapon.contact_profile if weapon != null else null
	if profile == null or rig_presentation == null or motion == null:
		_present_fallback(_fallback_point)
		return
	for unit_id in profile.permitted_parry_tip_ids:
		var candidate := rig_presentation.get_weapon_unit(unit_id)
		if candidate != null and is_instance_valid(candidate) and is_instance_valid(candidate.tip):
			_active_unit = candidate
			break
	if _active_unit == null:
		_present_fallback(_fallback_point)
		return
	var intercept: Variant = context.closest_point_to(_active_unit.tip.global_position)
	if not intercept is Vector3:
		_present_fallback(_fallback_point)
		return
	var intercept_point: Vector3 = intercept
	_fallback_point = intercept_point
	_has_fallback_point = true
	var attacker := context.get_attacker()
	var error: Error = motion.begin(_active_unit, intercept_point, profile, attacker)
	if error != OK:
		_present_fallback(intercept_point)
		_active_context = null
		_active_unit = null
		return
	if is_instance_valid(_time_domains) and _time_domains.has_method("acquire"):
		var participants: Array[Node] = [player]
		_time_token = int(_time_domains.call("acquire", self, participants, profile.parry_slow_scale, 0.04, 0.12))

func cancel(reason: StringName) -> void:
	_pending_context = null
	_selection_scheduled = false
	if _active_context != null and motion != null and motion.is_moving:
		motion.abort(reason)
	_release_time()
	_active_context = null
	_active_unit = null

func _physics_process(delta: float) -> void:
	if _active_context == null or motion == null or not motion.is_moving:
		return
	if player == null or not is_instance_valid(player) or player.combat_controller == null:
		cancel(&"owner_lost")
		return
	if player.combat_controller.state in [CombatController.State.DEAD, CombatController.State.STAGGERED, CombatController.State.EXECUTING]:
		cancel(&"interrupted")
		return
	if not is_instance_valid(_active_unit) or _active_unit.is_queued_for_deletion():
		cancel(&"weapon_lost")
		return
	var local_delta := delta
	if is_instance_valid(_time_domains) and _time_domains.has_method("factor_for"):
		local_delta *= clampf(float(_time_domains.call("factor_for", player)), 0.01, 1.0)
	motion.evaluate(local_delta)

func _on_contact_reached(action_id: int, point: Vector3) -> void:
	if _active_context == null or _presented_action_ids.has(action_id):
		return
	_presented_action_ids[action_id] = true
	if _presented_action_ids.size() > 64:
		_presented_action_ids.clear()
		_presented_action_ids[action_id] = true
	_emit_contact_event(action_id, point)

func _on_motion_ended(action_id: int, reason: StringName) -> void:
	if _active_context == null:
		return
	if reason in [&"blocked", &"unreachable"] and not _presented_action_ids.has(action_id):
		var fallback_id := -absi(action_id)
		_presented_action_ids[fallback_id] = true
		_emit_contact_event(fallback_id, _fallback_point)
	_release_time()
	_active_context = null
	_active_unit = null

func _present_fallback(point: Vector3) -> void:
	if not _has_fallback_point or not point.is_finite():
		return
	var action_id := -_fallback_action_id
	_fallback_action_id += 1
	_emit_contact_event(action_id, point)

func _emit_contact_event(action_id: int, point: Vector3) -> void:
	if not point.is_finite():
		return
	var events := get_tree().root.get_node_or_null("CombatEvents") if is_inside_tree() else null
	if events != null and events.has_signal(&"parry_contact_presented"):
		events.emit_signal(&"parry_contact_presented", action_id, point)

func _contact_tick(context: HitContactContext) -> int:
	return context.physics_tick if context.physics_tick > 0 else Engine.get_physics_frames()

func _contact_precedes(candidate: HitContactContext, current: HitContactContext) -> bool:
	var candidate_tick := _contact_tick(candidate)
	var current_tick := _contact_tick(current)
	if candidate_tick != current_tick:
		return candidate_tick < current_tick
	var candidate_id := String(candidate.attack_id) if candidate.attack_id != &"" else "hitbox:%010d" % candidate.hitbox_id
	var current_id := String(current.attack_id) if current.attack_id != &"" else "hitbox:%010d" % current.hitbox_id
	return candidate_id < current_id

func _release_time() -> void:
	if _time_token > 0 and is_instance_valid(_time_domains):
		_time_domains.call("release", _time_token)
	_time_token = -1

func _exit_tree() -> void:
	cancel(&"scene_teardown")
