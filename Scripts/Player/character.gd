extends CharacterBody3D

@export var SPEED = 5.0
@export var JUMP_VELOCITY = 4.5
@export var GRAVITY = 10

@export var camera_rig: CameraRig
@export var dash_manager: DashManager

@onready var model_pivot: Node3D = $ModelPivot

enum State {
	DEFAULT,
	DASHING,
	GUARDING
}

var state := State.DEFAULT
var lock_velocity := false
var speed_multiplier := 1.0


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("dash") and dash_manager.can_dash():
		dash_manager.dash()
		speed_multiplier = dash_manager.get_mult()
	
	if not is_on_floor():
		velocity += Vector3.DOWN * GRAVITY * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backwards")
	var direction
	direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		var forward := -camera_rig.global_basis.z
		var right := camera_rig.global_basis.x

		direction = (
			right * input_dir.x
			+ forward * -input_dir.y
		).normalized()
		
		if not lock_velocity:
			velocity.x = direction.x * SPEED * speed_multiplier
			velocity.z = direction.z * SPEED * speed_multiplier
		
		lock_velocity = dash_manager.is_dashing()
		print(lock_velocity)

		model_pivot.basis = Basis.looking_at(
			-direction,
			Vector3.UP
		)
		
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		
	speed_multiplier = 1.0

	move_and_slide()
