extends Resource
class_name ArenaModuleDefinition

const ArenaSocketDefinitionType = preload("res://Scripts/LevelGeneration/arena_socket_definition.gd")

@export var module_id: StringName = &""
@export var scene: PackedScene
@export var supported_silhouettes: Array[StringName] = []
@export var local_bounds: Rect2 = Rect2()
@export var sockets: Array[ArenaSocketDefinitionType] = []

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if module_id.is_empty():
		errors.append("Module ID cannot be empty.")
	if scene == null:
		errors.append("Module '%s' has no scene." % module_id)
	if supported_silhouettes.is_empty():
		errors.append("Module '%s' supports no silhouettes." % module_id)
	if local_bounds.size.x <= 0.0 or local_bounds.size.y <= 0.0:
		errors.append("Module '%s' local XZ bounds must have positive size." % module_id)
	for socket in sockets:
		if socket == null:
			errors.append("Module '%s' contains a null socket." % module_id)
		else:
			errors.append_array(socket.validate())
	return errors
