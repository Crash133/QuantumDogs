extends Resource
class_name ArenaSocketDefinition

@export var socket_id: StringName = &""
@export var local_transform: Transform3D = Transform3D.IDENTITY
@export var compatibility_tag: StringName = &""
@export var is_walkable: bool = true

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if socket_id.is_empty():
		errors.append("Socket ID cannot be empty.")
	if compatibility_tag.is_empty():
		errors.append("Socket compatibility tag cannot be empty.")
	return errors
