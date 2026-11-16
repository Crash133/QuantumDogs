class_name DefenseResolver
extends RefCounted

enum Result { IGNORED, PARRIED, BLOCKED, DAMAGED }

func resolve(_damage: float, iframe_active: bool, parry_active: bool, block_held: bool, _tuning: CombatTuning) -> Result:
	if iframe_active:
		return Result.IGNORED
	if parry_active:
		return Result.PARRIED
	if block_held:
		return Result.BLOCKED
	return Result.DAMAGED

## adds_heat is false for hits that must not raise Lace's heat (drone shots).
func apply_to_meters(result: Result, damage: float, heat: HeatMeter, battery: BatteryMeter, tuning: CombatTuning, adds_heat: bool = true) -> void:
	match result:
		Result.PARRIED:
			if heat != null:
				heat.reduce_heat(tuning.heat_parry_reduce)
			if battery != null:
				battery.pause_drain(tuning.battery_parry_pause_ticks)
		Result.BLOCKED:
			if heat != null and adds_heat:
				heat.add_heat(tuning.heat_per_block)
		Result.DAMAGED:
			if battery != null:
				battery.take_damage(damage)
			if heat != null and adds_heat:
				heat.add_heat(tuning.heat_per_damage_taken)

