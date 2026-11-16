@tool
class_name GatherThrowAbility
extends WeaponAbility

## While a node tagged node_tag runs, landed hits with effect hit_effect pull
## targets toward a point in front of the attacker. Leaving the tagged nodes
## (or unequipping) throws them along the last facing. Death/deletion only
## releases. Movement only: no extra hit, damage or healing.

@export var node_tag: StringName = &"ghost_drill"
@export var hit_effect: StringName = &"ghost_drill"
@export var gather_distance: float = 2.0
@export var gather_speed: float = 8.0
@export var throw_speed: float = 8.0

func validate(weapon: WeaponData) -> Array[String]:
	var errors: Array[String] = []
	var tagged := false
	if weapon.graph != null:
		for combo_node in weapon.graph.nodes:
			if combo_node != null and combo_node.tags.has(node_tag):
				tagged = true
	if not tagged:
		errors.append("GatherThrowAbility tag '%s' is on no combo node" % node_tag)
	if gather_distance < 0.0 or gather_speed < 0.0 or throw_speed < 0.0:
		errors.append("GatherThrowAbility distances and speeds cannot be negative")
	return errors

func create_runtime(_context: WeaponAbilityContext) -> WeaponAbilityRuntime:
	return Runtime.new()

class Runtime extends WeaponAbilityRuntime:
	var targets: Array[Node3D] = []
	var _last_direction := Vector3.FORWARD
	var _enabled := false

	func equipped() -> void:
		_enabled = true

	func unequipped() -> void:
		_release_all(_throw_velocity())
		_enabled = false

	func released() -> void:
		_release_all(Vector3.ZERO)
		_enabled = false

	func is_gathering() -> bool:
		var node: ComboNode = context.controller.combo.current_node if is_instance_valid(context.controller) else null
		return _enabled and _alive() and node != null and node.tags.has((ability as GatherThrowAbility).node_tag)

	func gather_position() -> Vector3:
		return (context.combatant as Node3D).global_position + _direction() * (ability as GatherThrowAbility).gather_distance

	func tick(_node: ComboNode, _node_tick: int, _hitboxes: Array[HitboxProxy]) -> void:
		if is_gathering():
			_last_direction = _direction()
			return
		_release_all(_throw_velocity())

	func hit_landed(hit: HitData, target: Object) -> void:
		if hit.effect != (ability as GatherThrowAbility).hit_effect or not is_gathering():
			return
		if not is_instance_valid(target) or not target is Node3D or not target.has_method("begin_combat_gather") or not target.has_method("end_combat_gather") or not target.is_alive():
			return
		# Track only accepted leases; closed elite armor refuses one.
		if target.begin_combat_gather(context.host, (ability as GatherThrowAbility).gather_speed) and not targets.has(target):
			targets.append(target)

	func _alive() -> bool:
		var combatant := context.combatant
		return is_instance_valid(combatant) and not combatant.is_queued_for_deletion() and is_instance_valid(context.controller) and context.controller.state != CombatController.State.DEAD

	func _throw_velocity() -> Vector3:
		return _last_direction * (ability as GatherThrowAbility).throw_speed if _alive() else Vector3.ZERO

	func _direction() -> Vector3:
		var facing := context.controller.attack_direction
		facing.y = 0.0
		return facing.normalized() if not facing.is_zero_approx() else _last_direction

	func _release_all(velocity: Vector3) -> void:
		for target in targets:
			if is_instance_valid(target):
				target.end_combat_gather(context.host, velocity)
		targets.clear()
