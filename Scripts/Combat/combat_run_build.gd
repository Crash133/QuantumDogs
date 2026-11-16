class_name CombatRunBuild
extends RefCounted

var weapons: Array[WeaponData] = []
var revolver_available: bool = false
var tuning: CombatTuning
var hit_multipliers: Dictionary[StringName, Vector2] = {}

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if weapons.is_empty(): errors.append("Combat build requires at least one melee weapon")
	var seen: Dictionary = {}
	for weapon in weapons:
		if weapon == null or weapon.id == &"" or seen.has(weapon.id):
			errors.append("Combat build has a null, empty-ID, or duplicate weapon")
			continue
		seen[weapon.id] = true
		if not weapon.validate().is_empty(): errors.append("Combat build contains an invalid weapon: %s" % weapon.id)
	if tuning == null:
		errors.append("Combat build requires tuning")
	else:
		errors.append_array(tuning.validate())
		if not is_finite(tuning.heat_max) or tuning.heat_max < 0.0:
			errors.append("Combat build Heat maximum must be finite and nonnegative")
		if not is_finite(tuning.battery_baseline_drain_per_second) or tuning.battery_baseline_drain_per_second < 0.0:
			errors.append("Combat build Battery drain must be finite and nonnegative")
		if tuning.dash_regen_ticks < 1:
			errors.append("Combat build dash regeneration must be at least one tick")
	for id in hit_multipliers:
		var multiplier: Vector2 = hit_multipliers[id]
		if id == &"" or not is_finite(multiplier.x) or not is_finite(multiplier.y) or multiplier.x < 0.0 or multiplier.y < 0.0:
			errors.append("Combat build has invalid hit multiplier")
	return errors
