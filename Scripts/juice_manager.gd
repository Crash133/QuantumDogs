extends Node


var _is_hit_stopping := false


@export var default_hit_particle: PackedScene


func hit_stop(duration: float) -> void:

	if duration <= 0.0:
		return

	if _is_hit_stopping:
		return

	_is_hit_stopping = true

	Engine.time_scale = 0.05

	await get_tree().create_timer(
		duration,
		true,
		false,
		true
	).timeout

	Engine.time_scale = 1.0

	_is_hit_stopping = false


func spawn_hit_particle(
	particle_scene: PackedScene,
	hit_position: Vector3
) -> void:

	if particle_scene == null:
		return

	var particle := particle_scene.instantiate()

	get_tree().current_scene.add_child(
		particle
	)

	particle.global_position = hit_position
