@tool
class_name ChargedProjectileAbility
extends WeaponAbility

## Started attacks fill an invisible gauge (separate from Player Heat). Once
## full, the weapon stays charged until unequipped and every attack emits one
## piercing flight on its earliest active HitSpec, copying that HitSpec, with a
## hit set independent of the blade.

@export_range(1, 100) var attacks_to_charge: int = 5
@export var projectile_speed: float = 20.0
@export_range(1, 600, 1, "suffix:ticks @60Hz") var projectile_lifetime_ticks: int = 24
@export var projectile_radius: float = 0.6

func validate(_weapon: WeaponData) -> Array[String]:
	var errors: Array[String] = []
	if attacks_to_charge < 1 or projectile_speed <= 0.0 or projectile_lifetime_ticks < 1 or projectile_radius <= 0.0:
		errors.append("ChargedProjectileAbility needs positive charge, speed, lifetime and radius")
	return errors

func create_runtime(_context: WeaponAbilityContext) -> WeaponAbilityRuntime:
	return Runtime.new()

class Runtime extends WeaponAbilityRuntime:
	var _count: int = 0
	var _charged: bool = false
	var _armed: bool = false

	func charge_count() -> int:
		return _count

	func is_charged() -> bool:
		return _charged

	func attack_started(_node: ComboNode) -> void:
		if not _charged:
			_count += 1
			_charged = _count >= maxi(1, (ability as ChargedProjectileAbility).attacks_to_charge)
		_armed = _charged

	func tick(node: ComboNode, node_tick: int, hitboxes: Array[HitboxProxy]) -> void:
		if not _armed or node == null:
			return
		var first: HitboxProxy
		for proxy in hitboxes:
			if first == null or proxy.hit_spec.active_ticks.x < first.hit_spec.active_ticks.x:
				first = proxy
		if first == null or node_tick != first.hit_spec.active_ticks.x:
			return
		# One flight per attack, even for multi-HitSpec nodes or a full pool.
		_armed = false
		var config := ability as ChargedProjectileAbility
		var data := CombatProjectileData.new()
		data.speed = config.projectile_speed
		data.lifetime_ticks = config.projectile_lifetime_ticks
		data.profile_size = Vector3.ONE * config.projectile_radius
		data.collision_mask = first.collision_mask
		data.hit_spec = first.hit_spec
		var flight := context.spawn_projectile(data, first.global_transform)
		if flight != null:
			SaberPlasmaVisual.attach(flight, data.profile_size.x)
