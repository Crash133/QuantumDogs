extends Node3D
class_name CameraRig

@export var follow_speed := 10.0

@export var min_pitch := -35.0
@export var max_pitch := 45.0
@export var mouse_sensitivity := 0.003

@export var orbit_point: Node3D

@onready var pitch_pivot = $PitchPivot

var pitch := -15.0
var yaw := 0.0
var follow_speed_mult := 1.0

func _process(delta: float) -> void:
	var target_position := orbit_point.global_position

	global_position = global_position.lerp(
		target_position,
		follow_speed * follow_speed_mult * delta
	)
	
	rotation.y = yaw
	pitch_pivot.rotation.x = deg_to_rad(pitch)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		yaw -= event.relative.x * mouse_sensitivity
		pitch -= event.relative.y * mouse_sensitivity

		pitch = clamp(
			pitch,
			deg_to_rad(min_pitch),
			deg_to_rad(max_pitch)
		)
