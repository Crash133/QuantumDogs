@tool
extends MeshInstance3D

@export var collider: CollisionShape3D

# Called when the node enters the scene tree for the first time.
func _process(delta: float) -> void:
	mesh.size = collider.shape.size
