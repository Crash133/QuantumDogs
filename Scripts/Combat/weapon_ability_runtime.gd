class_name WeaponAbilityRuntime
extends RefCounted

## Per-equip state for one WeaponAbility. Every hook is optional. Created on
## equip and dropped on unequip, so state here resets when switching away.

var ability: WeaponAbility
var context: WeaponAbilityContext

func equipped() -> void:
	pass

func unequipped() -> void:
	pass

## A combo node successfully started (rejected presses never reach this).
func attack_started(_node: ComboNode) -> void:
	pass

## Once per adapter physics tick, after the node's hitboxes are posed. node is
## null at Rest; hitboxes are the current node's live proxies.
func tick(_node: ComboNode, _node_tick: int, _hitboxes: Array[HitboxProxy]) -> void:
	pass

## A landed hit from this combatant with the equipped weapon.
func hit_landed(_hit: HitData, _target: Object) -> void:
	pass

## Successful Revolver hit by this combatant, independent of equipped melee ID.
func revolver_hit(_target: Object) -> void:
	pass

## The owning actor is leaving the tree; drop leases without side effects.
func released() -> void:
	pass

## Optional gather-provider contract, answered through WeaponAbilityHost.
func is_gathering() -> bool:
	return false

func gather_position() -> Vector3:
	return Vector3.ZERO

## Optional collision-resolved actor movement while a weapon signature is active.
func movement_intent(_actor_position: Vector3, _delta: float) -> Dictionary:
	return {}

## Explicit combo cancellation (dash, jump, block, execution) stops optional movement ownership.
func cancel_movement() -> void:
	pass
