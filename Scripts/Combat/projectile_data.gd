class_name CombatProjectileData
extends Resource

# Deliberately unconfigured: gameplay supplies approved tuning and a HitSpec.
@export var speed: float = 0.0
@export var lifetime_ticks: int = 0
@export_enum("sphere", "capsule", "box", "cone", "ring") var profile_shape: String = "sphere"
@export var profile_size: Vector3 = Vector3.ZERO
@export_flags_3d_physics var collision_mask: int = 1
@export var hit_spec: HitSpec

func is_valid() -> bool:
	if hit_spec == null or not is_finite(speed) or speed < 0.0 or lifetime_ticks <= 0 or not profile_size.is_finite():
		return false
	match profile_shape:
		"sphere": return profile_size.x > 0.0
		"capsule": return profile_size.x > 0.0 and profile_size.z >= 0.0
		"box", "ring": return profile_size.x > 0.0 and profile_size.y > 0.0 and profile_size.z > 0.0
		"cone": return profile_size.x > 0.0 and profile_size.x <= 89.0 and profile_size.z > 0.0
	return false
