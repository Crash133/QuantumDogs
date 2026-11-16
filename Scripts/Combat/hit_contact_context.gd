class_name HitContactContext
extends RefCounted

## Immutable-at-resolution snapshot of the submitted collision geometry.
var attack_id: StringName = &""
var hitbox_id: int = -1
var attacker_ref: WeakRef
var hitbox_transform: Transform3D = Transform3D.IDENTITY
var has_hitbox_transform: bool = false
var hitbox_previous_transform: Transform3D = Transform3D.IDENTITY
var has_previous_hitbox_transform: bool = false
var swept: bool = false
var trail_age: int = 0
var profile_shape: StringName = &""
var profile_size: Vector3 = Vector3.ZERO
var world_point: Vector3 = Vector3.ZERO
var has_world_point: bool = false
var physics_tick: int = 0
var melee: bool = false

func set_attacker(value: Object) -> void:
	attacker_ref = weakref(value) if is_instance_valid(value) else null

func get_attacker() -> Object:
	if attacker_ref == null:
		return null
	var value: Object = attacker_ref.get_ref()
	return value if is_instance_valid(value) else null

## Closest point on the captured hit volume's surface. The snapshot remains usable
## after its hitbox or attacker has been removed. Returns null for incomplete or
## unsupported geometry rather than inventing an interception point.
func closest_point_to(query_world: Vector3) -> Variant:
	if not has_hitbox_transform or not query_world.is_finite() or not world_transform_is_finite():
		return null
	var rigid := Transform3D(hitbox_transform.basis.orthonormalized(), hitbox_transform.origin)
	var local_query := rigid.affine_inverse() * query_world
	var local_point: Variant = null
	match profile_shape:
		&"sphere":
			var radius := profile_size.x
			if not is_finite(radius) or radius <= 0.0:
				return null
			var direction := local_query.normalized()
			if direction.is_zero_approx():
				direction = Vector3.UP
			local_point = direction * radius
		&"capsule":
			var radius := profile_size.x
			var half_segment := maxf(profile_size.z * 0.5, 0.0)
			if not is_finite(radius) or not is_finite(half_segment) or radius <= 0.0:
				return null
			var axis_point := Vector3(0.0, 0.0, clampf(local_query.z, -half_segment, half_segment))
			var radial := local_query - axis_point
			if radial.is_zero_approx():
				radial = Vector3.RIGHT
			local_point = axis_point + radial.normalized() * radius
		&"box":
			if not profile_size.is_finite() or profile_size.x <= 0.0 or profile_size.y <= 0.0 or profile_size.z <= 0.0:
				return null
			var half := profile_size * 0.5
			var clamped := local_query.clamp(-half, half)
			if clamped == local_query:
				var distances := Vector3(half.x - absf(local_query.x), half.y - absf(local_query.y), half.z - absf(local_query.z))
				if distances.x <= distances.y and distances.x <= distances.z:
					clamped.x = half.x * (1.0 if local_query.x >= 0.0 else -1.0)
				elif distances.y <= distances.z:
					clamped.y = half.y * (1.0 if local_query.y >= 0.0 else -1.0)
				else:
					clamped.z = half.z * (1.0 if local_query.z >= 0.0 else -1.0)
			local_point = clamped
		&"cone":
			var angle := clampf(profile_size.x, 0.0, 89.0)
			var length := profile_size.z
			if not is_finite(angle) or not is_finite(length) or length <= 0.0:
				return null
			local_point = _closest_on_cone(local_query, length, tan(deg_to_rad(angle)))
		&"ring":
			var radius := profile_size.x
			var thickness := profile_size.y
			var half_height := profile_size.z * 0.5
			if not is_finite(radius) or not is_finite(thickness) or not is_finite(half_height) or radius <= 0.0 or thickness <= 0.0 or half_height <= 0.0:
				return null
			var radial := Vector2(local_query.x, local_query.z)
			var radial_length := radial.length()
			var nearest_radius := clampf(radial_length, maxf(0.0, radius - thickness), radius + thickness)
			var nearest_radial := Vector2.RIGHT * nearest_radius if radial_length <= 0.000001 else radial / radial_length * nearest_radius
			local_point = Vector3(nearest_radial.x, clampf(local_query.y, -half_height, half_height), nearest_radial.y)
		_:
			return null
	if not local_point is Vector3 or not local_point.is_finite():
		return null
	return rigid * local_point

func _closest_on_cone(point: Vector3, length: float, tangent: float) -> Vector3:
	var depth := -point.z
	var radial := Vector2(point.x, point.y).length()
	if depth >= 0.0 and depth <= length and radial <= depth * tangent:
		return point
	var section := Vector2(depth, radial)
	var base_radius := length * tangent
	var candidates: Array[Vector2] = [
		_closest_on_segment(section, Vector2.ZERO, Vector2(length, base_radius)),
		_closest_on_segment(section, Vector2.ZERO, Vector2(length, 0.0)),
		_closest_on_segment(section, Vector2(length, 0.0), Vector2(length, base_radius)),
	]
	var closest := candidates[0]
	for candidate in candidates.slice(1):
		if section.distance_squared_to(candidate) < section.distance_squared_to(closest):
			closest = candidate
	var factor := closest.y / radial if radial > 0.000001 else 0.0
	return Vector3(point.x * factor, point.y * factor, -closest.x)

func _closest_on_segment(point: Vector2, start: Vector2, finish: Vector2) -> Vector2:
	var direction := finish - start
	var length_squared := direction.length_squared()
	var progress := clampf((point - start).dot(direction) / length_squared, 0.0, 1.0) if length_squared > 0.000001 else 0.0
	return start + direction * progress

func world_transform_is_finite() -> bool:
	return hitbox_transform.origin.is_finite() and hitbox_transform.basis.x.is_finite() and hitbox_transform.basis.y.is_finite() and hitbox_transform.basis.z.is_finite()
