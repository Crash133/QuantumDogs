extends Node

signal hit_landed(hit_data: HitData, target: Object)
signal enemy_killed(target: Object, hit_data: HitData)
signal parried(parrier: Object, attacker: Object)
## Emitted when the confirmed, presentation-only weapon Tip reaches the captured
## melee contact point. Does not re-run defense or apply damage.
signal parry_contact_presented(action_id: int, world_point: Vector3)
signal executed(target: Object)
signal blocked(attacker: Object)
signal damage_taken(amount: float, source: Object)
signal dash_used(charges_left: int)
signal revolver_fired(target: Object, hit_data: HitData)
signal weapon_switched(previous: StringName, current: StringName)
signal combo_advanced(weapon_id: StringName, node_id: StringName, depth: int)
signal heat_changed(owner: Object, value: float, maximum: float)
signal battery_changed(value: float, maximum: float)
signal staggered(owner: Object, duration_ticks: int)
signal player_died
