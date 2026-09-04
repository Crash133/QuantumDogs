class_name ComboManager
extends Node

var current_attack: AttackDefinition
var buffered_input: StringName

func receive_light() -> void:
	buffered_input = &"light"

func receive_heavy() -> void:
	buffered_input = &"heavy"


func get_next_attack() -> AttackDefinition:
	match buffered_input:
		&"light":
			return current_attack.next_light

		&"heavy":
			return current_attack.next_heavy

	return null
