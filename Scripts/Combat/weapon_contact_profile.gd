@tool
class_name WeaponContactProfile
extends Resource

## Stable WeaponUnit ID whose authored Tip is used for execution contact.
@export var execution_tip_id: StringName
## Ordered stable WeaponUnit IDs allowed to present confirmed melee parries.
@export var permitted_parry_tip_ids: Array[StringName] = []
## Rig-specific arm chain, pole, reach and correction limits used by the contact solver.
@export var rig_calibration: WeaponRigCalibration

@export_group("Procedural Motion")
@export var contact_curve: Curve
@export_range(0.03, 0.25, 0.005, "suffix:s") var parry_duration: float = 0.09
## Preferred wall-clock approach duration; longer routes obey the travel-speed cap.
@export_range(0.05, 0.6, 0.01, "suffix:s") var execution_duration: float = 0.22
## Maximum root travel speed during the collision-resolved execution approach.
@export_range(1.0, 40.0, 0.5, "suffix:m/s") var execution_max_speed: float = 20.0
## Hard action timeout; routes that require longer are rejected before activation.
@export_range(0.1, 3.0, 0.05, "suffix:s") var execution_timeout: float = 1.25
## Maximum collision-resolved body-root movement used to settle the actual Tip at ExecutionCenter.
@export_range(0.0, 0.5, 0.01, "suffix:m") var execution_contact_root_adjustment_limit: float = 0.18
## Minimum horizontal root spacing from the captured ExecutionCenter.
@export_range(0.1, 1.0, 0.01, "suffix:m") var execution_standoff_distance: float = 0.3
## Airborne executions may use a different spacing; zero uses execution_standoff_distance.
@export_range(0.0, 1.0, 0.01, "suffix:m") var airborne_execution_standoff_distance: float = 0.0
## Minimum cosine alignment between the execution approach facing and the target direction; 1 faces directly toward it.
@export_range(-1.0, 1.0, 0.01, "suffix:dot") var execution_min_target_facing_dot: float = 0.5
## Final arm/Tip alignment time after the body reaches its approach point.
@export_range(0.03, 0.3, 0.005, "suffix:s") var execution_contact_duration: float = 0.3
## Additional bounded CCD time to settle on ExecutionCenter after the curved route arrives.
@export_range(0.0, 0.3, 0.005, "suffix:s") var execution_contact_settle_seconds: float = 0.12
## Hold and return the Tip after a committed execution contact.
@export_range(0.0, 0.3, 0.005, "suffix:s") var execution_contact_hold_seconds: float = 0.04
@export_range(0.0, 0.5, 0.005, "suffix:s") var execution_recovery_seconds: float = 0.12
@export_range(0.05, 2.0, 0.01, "suffix:m") var maximum_contact_reach: float = 0.9
@export_range(0.0, 1.0, 0.01) var curve_lift_fraction: float = 0.18
## Signed sideways bow of the Tip path in world metres.
@export_range(-0.75, 0.75, 0.01, "suffix:m") var curve_sideways_offset: float = 0.25
## Added vertical bow of the Tip path in world metres.
@export_range(-0.75, 0.75, 0.01, "suffix:m") var curve_height_offset: float = 0.2
## Radius of the bounded weapon-envelope collision sample in metres.
@export_range(0.005, 0.15, 0.005, "suffix:m") var parry_envelope_radius: float = 0.025
## World collision layers checked along the parry Tip path.
@export_flags_3d_physics var parry_collision_mask: int = 1
## Maximum endpoint error before the confirmed defense falls back to an accent.
@export_range(0.005, 0.1, 0.005, "suffix:m") var contact_tolerance: float = 0.04
## Participant-local hold after reaching contact before the Tip begins to recover.
@export_range(0.0, 0.3, 0.005, "suffix:s") var parry_contact_hold_seconds: float = 0.06
## Participant-local CCD return to the currently animated held-weapon pose.
@export_range(0.0, 0.5, 0.005, "suffix:s") var parry_recovery_seconds: float = 0.12

@export_group("Selective Slowdown")
@export_range(0.01, 1.0, 0.01, "suffix:scale") var parry_slow_scale: float = 0.35
@export_range(0.01, 1.0, 0.01, "suffix:scale") var execution_slow_scale: float = 0.2

func validate(weapon_units: Array[WeaponUnit] = []) -> Array[String]:
	var errors: Array[String] = []
	var ids: Dictionary = {}
	for unit in weapon_units:
		if unit == null:
			continue
		if unit.unit_id == &"" or ids.has(unit.unit_id):
			errors.append("WeaponContactProfile requires unique nonempty WeaponUnit IDs")
		else:
			ids[unit.unit_id] = true
	if ids.is_empty():
		errors.append("WeaponContactProfile requires at least one WeaponUnit with a unique nonempty unit_id")
	if execution_tip_id != &"" and not ids.is_empty() and not ids.has(execution_tip_id):
		errors.append("execution_tip_id '%s' does not match a WeaponUnit.unit_id" % execution_tip_id)
	for unit_id in permitted_parry_tip_ids:
		if not ids.is_empty() and not ids.has(unit_id):
			errors.append("permitted parry tip '%s' does not match a WeaponUnit.unit_id" % unit_id)
	if rig_calibration != null:
		errors.append_array(rig_calibration.validate())
	if maximum_contact_reach <= 0.0:
		errors.append("maximum_contact_reach must be positive")
	if parry_duration <= 0.0 or parry_envelope_radius <= 0.0 or contact_tolerance <= 0.0:
		errors.append("WeaponContactProfile parry duration, envelope radius and tolerance must be positive")
	if not is_finite(execution_duration) or execution_duration < 0.05 or execution_duration > 0.6:
		errors.append("WeaponContactProfile execution_duration must be finite and in [0.05, 0.6] seconds")
	if not is_finite(execution_max_speed) or execution_max_speed < 1.0 or execution_max_speed > 40.0:
		errors.append("WeaponContactProfile execution_max_speed must be finite and in [1, 40] m/s")
	if not is_finite(execution_timeout) or execution_timeout < 0.1 or execution_timeout > 3.0:
		errors.append("WeaponContactProfile execution_timeout must be finite and in [0.1, 3] seconds")
	if not is_finite(execution_contact_root_adjustment_limit) or execution_contact_root_adjustment_limit < 0.0 or execution_contact_root_adjustment_limit > 0.5:
		errors.append("WeaponContactProfile execution_contact_root_adjustment_limit must be finite and in [0, 0.5] metres")
	if not is_finite(execution_standoff_distance) or execution_standoff_distance < 0.1 or execution_standoff_distance > 1.0:
		errors.append("WeaponContactProfile execution_standoff_distance must be finite and in [0.1, 1] metres")
	if not is_finite(airborne_execution_standoff_distance) or airborne_execution_standoff_distance < 0.0 or airborne_execution_standoff_distance > 1.0:
		errors.append("WeaponContactProfile airborne_execution_standoff_distance must be finite and in [0, 1] metres")
	if not is_finite(execution_min_target_facing_dot) or execution_min_target_facing_dot < -1.0 or execution_min_target_facing_dot > 1.0:
		errors.append("WeaponContactProfile execution_min_target_facing_dot must be finite and in [-1, 1]")
	if not is_finite(execution_contact_duration) or execution_contact_duration < 0.03 or execution_contact_duration > 0.3:
		errors.append("WeaponContactProfile execution_contact_duration must be finite and in [0.03, 0.3] seconds")
	if not is_finite(execution_contact_settle_seconds) or execution_contact_settle_seconds < 0.0 or execution_contact_settle_seconds > 0.3:
		errors.append("WeaponContactProfile execution_contact_settle_seconds must be finite and in [0, 0.3] seconds")
	if not is_finite(parry_contact_hold_seconds) or not is_finite(parry_recovery_seconds) or not is_finite(execution_contact_hold_seconds) or not is_finite(execution_recovery_seconds):
		errors.append("WeaponContactProfile action hold and recovery durations must be finite and nonnegative")
	if not is_finite(curve_sideways_offset) or not is_finite(curve_height_offset):
		errors.append("WeaponContactProfile contact curve offsets must be finite")
	if contact_curve != null:
		var previous := -INF
		for sample_index in range(17):
			var sample := contact_curve.sample_baked(float(sample_index) / 16.0)
			if not is_finite(sample) or sample < previous:
				errors.append("WeaponContactProfile contact_curve must be finite and monotonically nondecreasing")
				break
			previous = sample
		if absf(contact_curve.sample_baked(0.0)) > 0.001 or absf(contact_curve.sample_baked(1.0) - 1.0) > 0.001:
			errors.append("WeaponContactProfile contact_curve must start at 0 and end at 1")
	return errors
