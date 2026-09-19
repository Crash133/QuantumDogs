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

@export_category("Juice")

@export_range(0.0, 0.2, 0.005)
var hitstop: float = 0.04

@export_range(0.0, 1.0, 0.01)
var camera_shake: float = 0.1

@export var hit_sound: AudioStream

@export var hit_particle_scene: PackedScene
