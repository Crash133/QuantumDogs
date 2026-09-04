class_name HitData
extends Resource

enum HitPolicy {
	ONCE,
	MULTI_HIT,
	COOLDOWN
}

@export var attack: AttackDefinition

@export var damage: float = 0.0
@export var hitstun: float = 0.0
@export var knockback: Vector3

@export var potency: float = 1.0

@export var hit_policy: HitPolicy = HitPolicy.ONCE
@export var hit_cooldown: float = 0.1
