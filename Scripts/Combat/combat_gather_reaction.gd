class_name CombatGatherReaction
extends RefCounted

# Movement-only lease. Damage/Heat/events still belong to HitResolver.
var provider: Node
var speed: float = 0.0

func begin(owner_node: Node, units_per_second: float) -> void:
	provider = owner_node
	speed = maxf(0.0, units_per_second)

func active() -> bool:
	return is_instance_valid(provider) and provider.is_gathering()

func velocity_at(position: Vector3, delta: float) -> Vector3:
	if not active() or delta <= 0.0:
		return Vector3.ZERO
	var offset: Vector3 = provider.gather_position() - position
	offset.y = 0.0
	return offset.limit_length(speed * delta) / delta

func release(owner_node: Node) -> bool:
	if provider != owner_node:
		return false
	provider = null
	return true
