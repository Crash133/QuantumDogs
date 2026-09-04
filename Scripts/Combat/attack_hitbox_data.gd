class_name AttackHitboxData
extends Resource

enum HitPolicy {
	ONCE_PER_ATTACK,
	REPEAT
}

@export var shape: Shape3D

@export_category("Generation")
@export var active_start: float = 0.0
@export var active_end: float = 0.2

@export_category("Decay")
@export var decay: float = 0.0
@export var decay_curve: Curve

@export_category("Hit Policy")
@export var hit_policy: HitPolicy = HitPolicy.ONCE_PER_ATTACK
@export var repeat_interval: float = 0.0

@export_category("Trajectory")
@export var samples: Array[AttackHitboxSample] = []
