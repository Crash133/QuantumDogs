extends Node3D

var paused := false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	$UI/PauseMenu/PanelContainer/MarginContainer/VBoxContainer/Button.pressed.connect(_resume)
	$UI/PauseMenu/PanelContainer/MarginContainer/VBoxContainer/Button3.pressed.connect(_main_menu)
	$UI/PauseMenu/PanelContainer/MarginContainer/VBoxContainer/Button4.pressed.connect(get_tree().quit)

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("pause"):
		paused = !paused
		get_tree().paused = paused
		$UI/PauseMenu.visible = paused
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED

func _resume() -> void:
	paused = false
	get_tree().paused = false
	$UI/PauseMenu.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")


func _on_hurtbox_took_knockback(velocity: Vector3) -> void:
	pass # Replace with function body.
