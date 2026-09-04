class_name AttackRuntime
extends RefCounted

var definition: AttackDefinition
var elapsed := 0.0

func start(attack: AttackDefinition) -> void:
	definition = attack
	elapsed = 0.0

func update(delta: float) -> void:
	elapsed += delta

	# evaluate attack
