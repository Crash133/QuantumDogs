class_name WeaponAbilityContext
extends RefCounted

## What ability runtimes may touch. They never reach into adapter internals.

var controller: CombatController
var combatant: Node
var tuning: CombatTuning
var weapon: WeaponData
## Stable Node for leases that outlive one runtime (gather provider identity).
var host: WeaponAbilityHost
var manager: HitManagerNode
## Created on the first spawn; shared by every weapon so flights outlive a switch.
var projectile_pool: CombatProjectilePool

func spawn_projectile(data: CombatProjectileData, transform: Transform3D) -> CombatProjectile:
	if projectile_pool == null:
		projectile_pool = CombatProjectilePool.new()
		projectile_pool.name = "AbilityProjectilePool"
		projectile_pool.manager = manager
		var pool_parent: Node = host if host.is_inside_tree() else combatant
		pool_parent.add_child(projectile_pool)
	return projectile_pool.spawn(data, transform, combatant, weapon.id)
