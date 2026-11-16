extends Node


## The single time-scale owner (set by the FeedbackDirector). hit_stop forwards to it.
var time_handler: FeedbackTimeHandler
var _warned_unbound := false


@export var default_hit_particle: PackedScene


func hit_stop(duration: float) -> void:
	# Legacy entry point. Time scale has one owner: FeedbackTimeHandler.
	if is_instance_valid(time_handler):
		time_handler.request_stop(duration, 0.05, &"")
	elif not _warned_unbound:
		_warned_unbound = true
		push_warning("JuiceManager.hit_stop ignored: no FeedbackDirector time handler is bound")


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
