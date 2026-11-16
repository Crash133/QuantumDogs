class_name MantisSignatureLungeRuntime
extends WeaponAbilityRuntime

const LUNGE_NODE_ID: StringName = &"Lunge"

var _config: MantisSignatureLunge
var _primed_target: WeakRef
var _lunge_target: WeakRef
var _signature_attack_active: bool = false
var _motion_stopped: bool = false
var _has_previous_distance: bool = false
var _previous_distance: float = 0.0
var _blocked_seconds: float = 0.0

func configure(config: MantisSignatureLunge, runtime_context: WeaponAbilityContext) -> void:
	_config = config
	context = runtime_context

func revolver_hit(target: Object) -> void:
	if target is Node3D and _target_is_live(target as Node3D):
		_primed_target = weakref(target)

func attack_started(node: ComboNode) -> void:
	if node == null or node.id != LUNGE_NODE_ID:
		return
	_clear_lunge()
	var target := _resolve_target(_primed_target)
	_primed_target = null
	if target == null and context != null and context.controller != null and context.controller.targeting_service != null:
		target = context.controller.targeting_service.find_nearby_lunge_target(_actor_position(), _config.nearby_radius_multiplier)
	if target == null:
		return
	_signature_attack_active = true
	_lunge_target = weakref(target)

func tick(node: ComboNode, _node_tick: int, _hitboxes: Array[HitboxProxy]) -> void:
	if not _target_is_live(_resolve_target(_primed_target)):
		_primed_target = null
	if not _target_is_live(_resolve_target(_lunge_target)):
		_lunge_target = null
		_motion_stopped = true

## Returns {active, target, velocity}; active with zero velocity means arrival or a blocked route.
func movement_intent(actor_position: Vector3, delta: float) -> Dictionary:
	if not _signature_attack_active:
		return {}
	var target := _resolve_target(_lunge_target)
	if target == null:
		_lunge_target = null
		_motion_stopped = true
		return {"active": true, "target": null, "velocity": Vector3.ZERO}
	if _motion_stopped:
		_motion_stopped = true
		return {"active": true, "target": target, "velocity": Vector3.ZERO}
	var offset := target.global_position - actor_position
	offset.y = 0.0
	var distance := offset.length()
	if distance <= _config.arrival_distance:
		_motion_stopped = true
		return {"active": true, "target": target, "velocity": Vector3.ZERO}
	if _has_previous_distance:
		if _previous_distance - distance >= _config.progress_epsilon:
			_blocked_seconds = 0.0
		else:
			_blocked_seconds += maxf(0.0, delta)
		if _blocked_seconds >= _config.blocked_progress_timeout:
			_motion_stopped = true
			return {"active": true, "target": target, "velocity": Vector3.ZERO}
	else:
		_has_previous_distance = true
	_previous_distance = distance
	return {"active": true, "target": target, "velocity": offset / distance * _config.travel_speed}

func _actor_position() -> Vector3:
	var actor := context.combatant as Node3D if context != null else null
	return actor.global_position if actor != null else Vector3.ZERO

func _resolve_target(reference: WeakRef) -> Node3D:
	if reference == null:
		return null
	var target := reference.get_ref() as Node3D
	return target if _target_is_live(target) else null

func _target_is_live(target: Node3D) -> bool:
	return target != null and is_instance_valid(target) and target.is_inside_tree() and not target.is_queued_for_deletion() and (not target.has_method("is_alive") or bool(target.call("is_alive")))

func _clear_lunge() -> void:
	_lunge_target = null
	_signature_attack_active = false
	_motion_stopped = false
	_has_previous_distance = false
	_previous_distance = 0.0
	_blocked_seconds = 0.0

func unequipped() -> void:
	_primed_target = null
	_clear_lunge()

func cancel_movement() -> void:
	_clear_lunge()

func released() -> void:
	unequipped()
