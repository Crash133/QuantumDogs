class_name CombatController
extends Node

var current_attack: AttackRuntime

func start_attack(
	attack: AttackDefinition
) -> void:

	current_attack = AttackRuntime.new()
	current_attack.start(attack)

func _physics_process(delta: float) -> void:
	if current_attack:
		current_attack.update(delta)
