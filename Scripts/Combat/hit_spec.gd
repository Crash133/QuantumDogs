class_name HitSpec
extends Resource

@export var profile: StringName
enum Placement { ACTOR, WEAPON_MARKER }
## ACTOR preserves legacy chest/forward placement. WEAPON_MARKER follows the
## evaluated authored weapon marker after animation and procedural pose updates.
@export var placement: Placement = Placement.ACTOR
@export var marker_id: StringName
## Offset in the selected placement frame; profile dimensions remain world units.
@export var local_pose: Transform3D = Transform3D.IDENTITY
## Multiple inclusive active intervals; empty preserves legacy active_ticks.
@export var active_windows: Array[Vector2i] = []
## Deprecated single interval, retained until content migration is verified.
@export_custom(PROPERTY_HINT_RANGE, "0,3600,1,suffix:ticks @60Hz") var active_ticks: Vector2i = Vector2i.ZERO
@export var survive_transition: bool = false
## Node ticks (60 Hz) that clear this hitbox's hit-once set.
@export var refresh_ticks: PackedInt32Array = PackedInt32Array()
@export var damage: float = 0.0
## Ordinary flinch on a clean hit, in authored 60 Hz ticks (0 = no flinch).
## HitResolver converts it once into HitData.hitstun seconds, scaled by potency.
@export_range(0, 120, 1, "suffix:ticks @60Hz") var stun_ticks: int = 0
@export var heat: float = 0.0
# Attacker-local reaction velocity in m/s (+Y up, -Z forward); HitResolver
# rotates it once into world-space HitData. Independent of model scale.
@export var knockback: Vector3 = Vector3.ZERO
@export var effect: StringName
## Reaction requested on a clean hit: flinch, pushback, launch, knockdown or slam.
## A target decides the outcome (armor may resist). effect = launch is a legacy
## alias for launch while this stays the default flinch.
@export_custom(PROPERTY_HINT_ENUM_SUGGESTION, "flinch,pushback,launch,knockdown,slam") var reaction_kind: StringName = &"flinch"
## Opens a closed elite's armor (heavy and finisher moves).
@export var interrupts_armor: bool = false
## Semantic Game Feel cue for this move's resolved contacts (routine_hit, heavy_hit,
## finisher, or a custom cue). Authored per move; never inferred. Presentation only.
@export var feedback_cue_id: StringName = &"routine_hit"
@export var decay: Curve
@export_range(0, 256, 1, "suffix:ticks @60Hz") var linger_ticks: int = 8

func potency_at_age(age: int) -> float:
	if age < 0 or age > linger_ticks:
		return 0.0
	if decay == null:
		return 1.0 - 0.7 * float(age) / maxf(1.0, float(linger_ticks))
	return decay.sample(clampf(float(age) / maxf(1.0, float(linger_ticks)), 0.0, 1.0))

func resolved_active_windows() -> Array[Vector2i]:
	if not active_windows.is_empty():
		return active_windows.duplicate()
	return [active_ticks]

func is_active_at_tick(tick: int) -> bool:
	for window in resolved_active_windows():
		if tick >= window.x and tick <= window.y:
			return true
	return false
