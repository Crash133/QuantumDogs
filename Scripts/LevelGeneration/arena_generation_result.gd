extends Resource
class_name ArenaGenerationResult

const PlacementType = preload("res://Scripts/LevelGeneration/arena_module_placement.gd")
const SpawnAnchorType = preload("res://Scripts/LevelGeneration/arena_spawn_anchor.gd")

@export var success: bool = false
@export var seed: int = 0
@export var silhouette_id: StringName = &""
var root: Node3D
@export var placements: Array[PlacementType] = []
var spawn_anchors: Array[SpawnAnchorType] = []
@export var diagnostics: Dictionary = {}
@export var error: String = ""
