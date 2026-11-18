class_name DifficultyAdapter
extends RefCounted

## The legacy difficulty_scale curve has no approved conversion. Keep the run
## playable at the neutral multiplier and surface a diagnostic until D3 values
## are authored. Explicit supported values pass through unchanged.
## Enemy damage is the exception: it grows exponentially with level depth.

## Enemy damage is multiplied by this per level above 1 (level 1 = x1). Tuned for a
## 10-damage hit against the 100-point Battery: level 10 takes 4 hits (31 each),
## level 11 is the first where 3 hits kill (36 each), and it keeps growing after.
const DAMAGE_GROWTH_PER_LEVEL := 1.135

func normalize(raw: Dictionary, depth: int = 0) -> Dictionary:
	var errors := PackedStringArray()
	var diagnostics := PackedStringArray()
	var health_multiplier := 1.0
	var damage_multiplier := pow(DAMAGE_GROWTH_PER_LEVEL, maxi(depth - 1, 0))
	for key in raw:
		match StringName(key):
			&"health_multiplier":
				var value: Variant = raw[key]
				if not (value is int or value is float) or not is_finite(float(value)) or float(value) <= 0.0:
					errors.append("health_multiplier must be a finite positive number")
				else:
					health_multiplier = float(value)
			&"damage_multiplier":
				var damage_value: Variant = raw[key]
				if not (damage_value is int or damage_value is float) or not is_finite(float(damage_value)) or float(damage_value) <= 0.0:
					errors.append("damage_multiplier must be a finite positive number")
				else:
					damage_multiplier = float(damage_value)
			&"difficulty_scale":
				var legacy_value: Variant = raw[key]
				if not (legacy_value is int or legacy_value is float) or not is_finite(float(legacy_value)):
					errors.append("difficulty_scale must be finite while awaiting an approved mapping")
				else:
					diagnostics.append("difficulty_scale is not mapped; D3 health/parry/Heat curves need approved numeric values (damage scales with depth)")
			_:
				errors.append("Unsupported difficulty parameter: %s" % String(key))
	return {
		"ok": errors.is_empty(),
		"parameters": {"health_multiplier": health_multiplier, "damage_multiplier": damage_multiplier},
		"errors": errors,
		"diagnostics": diagnostics,
	}
