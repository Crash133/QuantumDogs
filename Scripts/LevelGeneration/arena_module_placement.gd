extends Resource
class_name ArenaModulePlacement

const ModuleDefinitionType = preload("res://Scripts/LevelGeneration/arena_module_definition.gd")

@export var definition: ModuleDefinitionType
@export var transform: Transform3D = Transform3D.IDENTITY
var instance: Node3D
