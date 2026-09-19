class_name CameraShake
extends Node3D


@export var trauma_decay: float = 4.0

@export var max_offset: Vector3 = Vector3(
	0.15,
	0.15,
	0.05
)


var trauma: float = 0.0

var _original_position: Vector3


func _ready() -> void:
	_original_position = position


func add_shake(amount: float) -> void:

	trauma = clamp(
		trauma + amount,
		0.0,
		1.0
	)


func _process(delta: float) -> void:

	if trauma <= 0.0:

		position = _original_position
		return

	trauma = max(
		trauma - trauma_decay * delta,
		0.0
	)

	var intensity := trauma * trauma

	var random_offset := Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)
	)

	position = _original_position + (
		random_offset
		* intensity
		* max_offset
	)
