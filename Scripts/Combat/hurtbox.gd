class_name Hurtbox
extends Area3D

@export var owner_entity: Node

signal took_damage(amount: float)
signal took_knockback(velocity: Vector3)
signal took_stun(duration: float)

func _ready() -> void:
	monitoring = false

func apply_hit(hit: HitData) -> void:
	took_damage.emit(hit.damage)
	took_knockback.emit(hit.knockback)
	took_stun.emit(hit.hitstun)
	
	print("Hurtbox took %s damage!" % hit.damage)
