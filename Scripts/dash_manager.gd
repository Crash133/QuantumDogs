class_name DashManager extends Node

@onready var cooldown: Timer = $Cooldown
@onready var duration: Timer = $Duration

@export var dash_multiplier = 10.0
@export var dash_time_buffering := 0.1
@export var dash_speed_curve: Curve

signal dash_end()

var dashing = false
var in_cooldown = false

func get_mult() -> float:
	return _get_speed_mult()

func can_dash() -> bool:
	return not in_cooldown or cooldown.time_left < dash_time_buffering
	
func dash() -> void:
	cooldown.start()
	duration.start()

	dashing = true
	in_cooldown = true
	
func _get_speed_mult() -> float:
	if not is_dashing():
		return 1.0
		
	var elapsed_time = duration.wait_time - duration.time_left
	var t = elapsed_time / duration.wait_time
	return dash_speed_curve.sample(t) * dash_multiplier
	
func is_dashing() -> bool:
	return dashing

func _on_duration_timeout() -> void:
	dashing = false
	dash_end.emit()

func _on_cooldown_timeout() -> void:
	in_cooldown = false
