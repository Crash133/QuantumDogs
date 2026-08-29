class_name Hurtbox extends Area3D

signal took_damage(amount: int)

func apply_hit(damage: int) -> void:
	took_damage.emit(damage)
	print("Hurtbox took %s damage!" % damage)
