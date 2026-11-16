@tool
class_name HitboxProfile
extends Resource

## Native hit shape for HitSpecs that name this profile. Sizes are world units,
## independent of model scale. Only the fields the selected shape uses are shown.

enum Shape { SPHERE, CAPSULE, BOX, CONE, RING }

const NATIVE_SHAPES: Array[StringName] = [&"sphere", &"capsule", &"box", &"cone", &"ring"]
const SHAPE_FIELDS: Dictionary = {
	Shape.SPHERE: [&"radius"],
	Shape.CAPSULE: [&"radius", &"length"],
	Shape.BOX: [&"size"],
	Shape.CONE: [&"angle_degrees", &"radius", &"length"],
	Shape.RING: [&"radius", &"thickness", &"height"],
}
const ALL_FIELDS: Array[StringName] = [&"radius", &"length", &"size", &"angle_degrees", &"thickness", &"height"]

@export var shape: Shape = Shape.SPHERE:
	set(value):
		shape = value
		notify_property_list_changed()
# Defaults match the legacy dictionary parser's fallbacks.
@export var radius: float = 1.0
## Capsule: along local Z. Cone: finite along local -Z.
@export var length: float = 2.0
@export var size: Vector3 = Vector3.ONE
@export_range(0.0, 180.0, 0.1, "suffix:°") var angle_degrees: float = 30.0
@export var thickness: float = 0.2
@export var height: float = 0.2

func _validate_property(property: Dictionary) -> void:
	if StringName(property.name) in ALL_FIELDS and not StringName(property.name) in SHAPE_FIELDS[shape]:
		property.usage = PROPERTY_USAGE_NO_EDITOR

## Shape name and size vector expected by HitManager.configure_hitbox.
func to_native() -> Dictionary:
	var native_size: Vector3
	match shape:
		Shape.SPHERE: native_size = Vector3(radius, radius, radius)
		Shape.CAPSULE: native_size = Vector3(radius, radius, length)
		Shape.BOX: native_size = size
		Shape.CONE: native_size = Vector3(angle_degrees, radius, length)
		Shape.RING: native_size = Vector3(radius, thickness, height)
	return {&"shape": NATIVE_SHAPES[shape], &"size": native_size}

func validate() -> Array[String]:
	var errors: Array[String] = []
	for field: StringName in SHAPE_FIELDS[shape]:
		var value: Variant = get(field)
		var positive: bool = value.x > 0.0 and value.y > 0.0 and value.z > 0.0 if value is Vector3 else float(value) > 0.0
		if not positive:
			errors.append("%s profile needs a positive %s" % [NATIVE_SHAPES[shape], field])
	return errors
