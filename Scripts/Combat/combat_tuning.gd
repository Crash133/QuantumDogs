class_name CombatTuning
extends Resource

@export var tick_rate: int = 60
@export var input_buffer_ticks: int = 6
@export_group("Combo Action Arbitration")
## Complete tie-break order for simultaneous cancels and combo links.
## Each of block_parry, dodge, execute, jump, switch, light and heavy must occur once.
@export var cancel_action_priority: Array[StringName] = [&"block_parry", &"dodge", &"execute", &"jump", &"switch", &"light", &"heavy"]
@export_group("")
@export var parry_window_ticks: int = 8
@export var heat_max: float = 100.0
@export var heat_per_block: float = 25.0
@export var heat_parry_reduce: float = 10.0
@export var heat_when_parried: float = 5.0
@export var heat_per_damage_taken: float = 35.0
@export var heat_idle_delay_ticks: int = 60
@export var heat_decay_per_second: float = 15.0
@export var stagger_ticks: int = 150
@export var elite_stagger_ticks: int = 180
@export var battery_max: float = 100.0
@export var battery_baseline_drain_per_second: float = 1.5
@export var battery_ramp_delay_ticks: int = 120
@export var battery_ramp_per_second: float = 0.5
@export var battery_ramp_max_multiplier: float = 4.0
@export var battery_hit_heal: float = 4.0
## The attacker's own Heat drops by this much per landed hit (scaled by potency).
@export var heat_hit_reduce: float = 2.0
@export var battery_parry_pause_ticks: int = 90
@export var dash_charges_base: int = 1
@export var dash_regen_ticks: int = 90
@export var dash_iframe_ticks: int = 12
@export var dash_distance: float = 5.0
@export var air_hover_ticks: int = 21
@export var revolver_capacity: int = 6
@export var revolver_shot_interval_ticks: int = 7
@export var revolver_regen_ticks_per_shot: int = 48
@export var magnetism_range: float = 6.0
@export var magnetism_cone_degrees: float = 45.0
@export var lock_range: float = 20.0
# Approach presentation values are playtest placeholders, not authored GDD timings.
@export var execution_close_speed: float = 20.0
@export var execution_strike_distance: float = 1.2
## Off: an execution kills the target at once and fires the shockwave, with no approach
## or finisher animation. On: Lace closes in and plays the procedural finisher first.
@export var execution_animation_enabled: bool = true
@export_group("Execution Shockwave")
## Maximum spherical range affected by a confirmed execution finisher. Units: metres.
@export_range(0.0, 15.0, 0.1, "suffix:m") var execution_shockwave_radius: float = 4.0
## Minimum ground flinch duration applied without damage or heat. Units: seconds on each enemy's local clock.
@export_range(0.0, 5.0, 0.05, "suffix:s") var execution_shockwave_stun_seconds: float = 1.1
## Downward speed applied to airborne/flying enemies. Units: metres per second.
@export_range(0.0, 30.0, 0.5, "suffix:m/s") var execution_shockwave_slam_speed: float = 8.0
## Prevents a shocked enemy from being executed again, including through its knockdown recovery. Units: seconds on its local clock.
@export_range(0.0, 8.0, 0.05, "suffix:s") var execution_shockwave_execution_lock_seconds: float = 2.0
## Optional authored expanding ring effect shown at the committed execution center.
@export var execution_shockwave_vfx: PackedScene
# Aerial combat feel controls. Tick values use the combat's authored 60 Hz clock.
@export_group("Aerial Combat")
## Duration of gravity suspension after a launcher or ordinary air hit. Units: 60 Hz ticks.
@export_range(0, 120, 1, "suffix:ticks @60Hz") var enemy_air_hit_hold_ticks: int = 21
## Additional gravity suspension captured once when a launched enemy reaches its apex. Zero disables it.
@export_range(0, 180, 1, "suffix:ticks @60Hz") var enemy_apex_hold_ticks: int = 30
## Initial upward launch velocity. Units: metres per second.
@export_range(0.0, 20.0, 0.1, "or_greater", "suffix:m/s") var launcher_upward_speed: float = 6.0
## Downward acceleration applied to airborne enemies. Units: metres per second squared.
@export_range(0.1, 30.0, 0.1, "or_greater", "suffix:m/s²") var enemy_gravity: float = 9.0
## Grunts and drones that may be in a windup or strike at once; the rest hold a ring
## around Lace and step in as slots free up. Elites are exempt. 0 = no limit.
@export_range(0, 20, 1) var enemy_max_attackers: int = 4
## A hit drone drops at enemy_gravity times this, with no air-hit hold.
@export_range(1.0, 30.0, 0.5, "or_greater") var drone_drop_gravity_scale: float = 10.0
## After landing a hit drone stays down and immobile this long, then flies back up.
@export_range(0.0, 10.0, 0.1, "suffix:s") var drone_downed_seconds: float = 3.0
@export_range(0.5, 20.0, 0.5, "suffix:m/s") var drone_rise_speed: float = 4.0
## Time available to press an aerial follow-up after a launch. Zero expires immediately.
@export_range(1, 180, 1, "suffix:ticks @60Hz") var aerial_follow_window_ticks: int = 90
## Maximum player travel speed while following a launched target. Units: metres per second.
@export_range(0.1, 40.0, 0.1, "or_greater", "suffix:m/s") var aerial_follow_speed: float = 20.0
## Side offset maintained from the target during the follow. Units: metres.
@export_range(0.0, 5.0, 0.05, "suffix:m") var aerial_follow_distance: float = 1.0
## Maximum duration of follow movement after it starts. Units: 60 Hz ticks.
@export_range(1, 180, 1, "suffix:ticks @60Hz") var aerial_follow_timeout_ticks: int = 36
@export_group("")
@export var trail_linger_ticks: int = 8
@export var battery_drain_enabled: bool = true

func validate() -> Array[String]:
	var errors: Array[String] = []
	var required: Array[StringName] = [&"block_parry", &"dodge", &"execute", &"jump", &"switch", &"light", &"heavy"]
	var seen: Dictionary = {}
	for action in cancel_action_priority:
		if action not in required:
			errors.append("Cancel priority contains unsupported action '%s'" % action)
		elif seen.has(action):
			errors.append("Cancel priority repeats action '%s'" % action)
		seen[action] = true
	for action in required:
		if not seen.has(action):
			errors.append("Cancel priority is missing action '%s'" % action)
	return errors

