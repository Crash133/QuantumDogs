extends CharacterBody3D


@export var SPEED = 5.0
@export var JUMP_VELOCITY = 4.5
@export var GRAVITY = 10

@export var camera_rig: CameraRig

@onready var model_pivot: Node3D = $ModelPivot

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += Vector3.DOWN * GRAVITY * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backwards")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		var forward := -camera_rig.global_basis.z
		var right := camera_rig.global_basis.x

		direction = (
			right * input_dir.x
			+ forward * -input_dir.y
		).normalized()

		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED

		model_pivot.basis = Basis.looking_at(
			-direction,
			Vector3.UP
		)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
