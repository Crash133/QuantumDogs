class_name Player
extends CharacterBody3D

@export var SPEED = 5.0
@export var JUMP_VELOCITY = 4.5
@export var GRAVITY = 10

@export var camera_rig: CameraRig
@export var dash_manager: DashManager
@export var health: HealthComponent

@onready var anim_tree := $AnimationTree
@onready var model_pivot: Node3D = $ModelPivot
@onready var anim_play:= $AnimationPlayer

signal dealt_damage(hit: HitData)

enum State {
	IDLE,
	DASHING,
	RUNNING,
	ATTACKING,
	GUARDING
}

var state := State.IDLE
var stand_still := false
var can_combo := false
var dash_direction := Vector3.ZERO

func end_attack():
	state = State.IDLE
	anim_play.speed_scale = 1

func lock_movement():
	stand_still = true
	
func unlock_movement():
	stand_still = false

func start_combo_window():
	can_combo = true
	
func end_combo_window():
	can_combo = false

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("attack"):
		state = State.ATTACKING
	
	_update_tree()

func _ready():
	print(SPEED)

func _physics_process(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backwards")
	var direction := Vector3.ZERO
	if input_dir != Vector2.ZERO:
		var forward := -camera_rig.global_basis.z
		var right := camera_rig.global_basis.x
		direction = (right * input_dir.x + forward * -input_dir.y).normalized()

	if Input.is_action_just_pressed("dash") and dash_manager.can_dash():
		dash_manager.dash()
		dash_direction = direction if direction != Vector3.ZERO else -camera_rig.global_basis.z
	
	if not is_on_floor():
		velocity += Vector3.DOWN * GRAVITY * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	if dash_manager.is_dashing():
		var dash_speed: float = SPEED * dash_manager.get_mult()
		velocity.x = dash_direction.x * dash_speed
		velocity.z = dash_direction.z * dash_speed
		model_pivot.basis = Basis.looking_at(-dash_direction, Vector3.UP)
	elif direction != Vector3.ZERO:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
		model_pivot.basis = Basis.looking_at(-direction, Vector3.UP)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
	
	if stand_still:
		velocity = Vector3.ZERO

	move_and_slide()
	
func _update_tree():
	anim_tree.set(
		'parameters/conditions/dash',
		dash_manager.is_dashing()
	)
	anim_tree.set(
		'parameters/conditions/is_dashing',
		dash_manager.is_dashing()
	)
	
	var vel = velocity.length()
	anim_tree.set(
		'parameters/conditions/is_running',
		vel and not dash_manager.is_dashing()
	)
	
	anim_tree.set(
		'parameters/conditions/attack',
		state == State.ATTACKING
	)
	
	anim_tree.set(
		'parameters/conditions/idle',
		not (dash_manager.is_dashing() or velocity.length())
	)
	
	anim_tree.set(
		'parameters/Attack Machine/conditions/light',
		can_combo and Input.is_action_just_pressed("attack")
	)

func _on_attack_hitbox_attacked(hit: HitData, target: Hurtbox, hit_position: Vector3) -> void:
	health.heal_health(hit.damage * 0.8)
	dealt_damage.emit(hit)
	JuiceManager.hit_stop(hit.hitstop)
	camera_rig.get_shaker().add_shake(
		hit.camera_shake
	)
