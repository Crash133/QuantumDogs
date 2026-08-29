class_name Attack extends Node3D

@onready var anim_player: AnimationPlayer = $AnimationPlayer

func play_attack() -> void:
	anim_player.play("test_1")
