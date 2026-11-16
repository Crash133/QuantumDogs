class_name DifficultyAdapter
extends RefCounted

## The legacy difficulty_scale curve has no approved conversion. Keep the run
## playable at the neutral multiplier and surface a diagnostic until D3 values
## are authored. Explicit supported values pass through unchanged.
func normalize(raw: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var diagnostics := PackedStringArray()
	var health_multiplier := 1.0
	for key in raw:
		match StringName(key):
			&"health_multiplier":
				var value: Variant = raw[key]
				if not (value is int or value is float) or not is_finite(float(value)) or float(value) <= 0.0:
					errors.append("health_multiplier must be a finite positive number")
				else:
					health_multiplier = float(value)
			&"difficulty_scale":
				var legacy_value: Variant = raw[key]
				if not (legacy_value is int or legacy_value is float) or not is_finite(float(legacy_value)):
					errors.append("difficulty_scale must be finite while awaiting an approved mapping")
				else:
					diagnostics.append("difficulty_scale is not mapped; D3 health/damage/parry/Heat curves need approved numeric values")
			_:
				errors.append("Unsupported difficulty parameter: %s" % String(key))
	return {
		"ok": errors.is_empty(),
		"parameters": {"health_multiplier": health_multiplier},
		"errors": errors,
		"diagnostics": diagnostics,
	}
