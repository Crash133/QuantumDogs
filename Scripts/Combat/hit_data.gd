class_name HitData
extends Resource

enum HitPolicy {
	ONCE,
	MULTI_HIT,
	COOLDOWN
}

@export var damage: float = 0.0
## Ordinary flinch in seconds (HitResolver converts HitSpec.stun_ticks once).
@export var hitstun: float = 0.0
## Resolved world-space reaction velocity in m/s; HitSpec authoring is attacker-local.
@export var knockback: Vector3
@export var heat: float = 0.0
@export var effect: StringName
## Requested reaction (see HitSpec.reaction_kind); empty = no reaction.
@export var reaction_kind: StringName = &"flinch"
@export var interrupts_armor: bool = false
## Runtime result the target fills before hit_landed: none, resisted, flinch,
## pushback, launch, air_hold, knockdown, slam or defeated. Presentation reads it.
var reaction_outcome: StringName = &"none"
var reaction_direction: Vector3 = Vector3.ZERO
var source: Object
var weapon_id: StringName
# Presentation-only: copied from HitSpec / the attacking hitbox by HitResolver.
var feedback_cue_id: StringName = &"routine_hit"
var feedback_burst_id: StringName
## Geometry captured before defense callbacks can retire the attacking hitbox.
var contact_context: HitContactContext

@export var potency: float = 1.0

@export var hit_policy: HitPolicy = HitPolicy.ONCE
@export var hit_cooldown: float = 0.1

@export_category("Juice")

@export_range(0.0, 0.2, 0.005)
var hitstop: float = 0.04

@export_range(0.0, 1.0, 0.01)
var camera_shake: float = 0.1

@export var hit_sound: AudioStream

@export var hit_particle_scene: PackedScene
