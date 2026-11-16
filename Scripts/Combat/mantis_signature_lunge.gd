@tool
class_name MantisSignatureLunge
extends WeaponAbility

## Mantis Blades opening Lunge: homes to close targets or the exact enemy hit by
## this combatant's successful Revolver shot.
@export_group("Mantis Signature Lunge")
## Nearby fallback is measured from the target's body radius in horizontal meters.
@export_range(1.0, 6.0, 0.25, "suffix:x target body radius") var nearby_radius_multiplier: float = 2.0
## Horizontal travel speed while following a target. Units: meters per second.
@export_range(1.0, 60.0, 0.5, "suffix:m/s") var travel_speed: float = 20.0
## Stop this lunge at this horizontal distance from the target root. Units: meters.
@export_range(0.1, 2.0, 0.05, "suffix:m") var arrival_distance: float = 0.7
## Stop applying lunge movement after this long without actual progress. Units: local seconds.
@export_range(0.1, 3.0, 0.05, "suffix:s") var blocked_progress_timeout: float = 0.5
## Minimum target-distance reduction that resets the blocked-route timer. Units: meters.
@export_range(0.005, 0.25, 0.005, "suffix:m") var progress_epsilon: float = 0.03

func validate(_weapon: WeaponData) -> Array[String]:
	var errors: Array[String] = []
	if nearby_radius_multiplier < 1.0 or nearby_radius_multiplier > 6.0:
		errors.append("Mantis signature nearby radius multiplier must be between 1 and 6")
	if travel_speed <= 0.0 or travel_speed > 60.0:
		errors.append("Mantis signature travel speed must be between 0 and 60 m/s")
	if arrival_distance <= 0.0 or arrival_distance > 2.0:
		errors.append("Mantis signature arrival distance must be between 0 and 2 m")
	if blocked_progress_timeout <= 0.0 or blocked_progress_timeout > 3.0:
		errors.append("Mantis signature blocked progress timeout must be between 0 and 3 seconds")
	if progress_epsilon <= 0.0 or progress_epsilon > 0.25:
		errors.append("Mantis signature progress epsilon must be between 0 and 0.25 m")
	return errors

func create_runtime(context: WeaponAbilityContext) -> WeaponAbilityRuntime:
	var runtime := MantisSignatureLungeRuntime.new()
	runtime.configure(self, context)
	return runtime
