extends Control

@onready var press_any_button: Control = $PressAnyButton
@onready var menu: Control = $Menu
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var menu_open := false

func _ready() -> void:
	menu.hide()
	$Menu/PanelContainer/MarginContainer/VBoxContainer/Button4.pressed.connect(_start_game)
	$Menu/PanelContainer/MarginContainer/VBoxContainer/Button3.pressed.connect(get_tree().quit)

func _unhandled_input(event: InputEvent) -> void:
	if menu_open or not event.is_pressed():
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		menu_open = true
		_open_menu()

func _open_menu() -> void:
	animation_player.play("PressOut")
	await animation_player.animation_finished
	press_any_button.hide()
	menu.show()
	animation_player.play("MenuIntro")

func _start_game() -> void:
	get_tree().change_scene_to_file("res://Scenes/test.tscn")
