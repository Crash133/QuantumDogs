class_name Enemy
extends CharacterBody3D

@export var SPEED := 5.0
@export var KNOCKBACK_DECELERATION := 20.0
@export var player: Player

var direction := Vector3.ZERO
var knockback_velocity := Vector3.ZERO
var stun := 0

func _process(delta: float) -> void:
	var pp = player.global_position
	pp.y = global_position.y
	direction = (pp - global_position).normalized()
	
	look_at(
		pp,
		Vector3.UP
	)

func _physics_process(delta: float) -> void:
	# Count down stun.
	if stun > 0.0:
		stun = max(0.0, stun - delta)

	# Normal movement.
	var movement_velocity := direction * SPEED

	# Don't move normally while stunned or being knocked back.
	if stun > 0.0 or knockback_velocity != Vector3.ZERO:
		movement_velocity = Vector3.ZERO

	# Decay knockback.
	knockback_velocity = knockback_velocity.move_toward(
		Vector3.ZERO,
		KNOCKBACK_DECELERATION * delta
	)

	# Final velocity.
	velocity = movement_velocity + knockback_velocity

	if not is_on_floor():
		velocity += Vector3.DOWN * 9 * delta

	move_and_slide()


func _on_hurtbox_took_knockback(new_knockback: Vector3) -> void:
	knockback_velocity += new_knockback.length() * -direction


func _on_hurtbox_took_stun(duration: float) -> void:
	stun = duration


func _on_health_component_died(amount: float) -> void:
	queue_free()
