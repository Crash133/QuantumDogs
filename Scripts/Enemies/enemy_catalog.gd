class_name EnemyCatalog
extends Resource

@export var definitions: Array[EnemyDefinition] = []

func _init() -> void:
	if definitions.is_empty():
		for role in [&"common", &"drone", &"elite"]:
			var definition := EnemyDefinition.new()
			definition.enemy_id = role
			definition.role = role
			definition.scene = load("res://Scenes/Enemies/%sEnemy.tscn" % ("Flying" if role == &"drone" else "Elite" if role == &"elite" else "Common"))
			definition.max_health = 56.0 if role == &"drone" else 288.0 if role == &"elite" else 80.0
			definition.move_speed = 4.0 if role == &"drone" else 2.5
			var attack := EnemyAttackDefinition.new()
			attack.attack_id = &"phase_cannon" if role == &"drone" else &"melee"
			attack.telegraph_cue = &"camera_glow" if role == &"drone" else &"head_light" if role == &"common" else &"elite_warning"
			# Long windups so every strike can be read and dodged (60 ticks = 1 s).
			attack.windup_ticks = 54 if role == &"drone" else 48 if role == &"elite" else 40
			attack.hit_spec = HitSpec.new()
			attack.hit_spec.damage = 10.0
			if role == &"drone":
				attack.range_meters = 8.0
				attack.shape = &"capsule"
				attack.shape_size = Vector3(0.35, 0.0, attack.range_meters)
			definition.attack = attack
			definitions.append(definition)

func get_definition(enemy_id: StringName) -> EnemyDefinition:
	for definition in definitions:
		if definition != null and definition.enemy_id == enemy_id: return definition
	return null

func validate() -> Array[String]:
	var errors: Array[String] = []
	var seen: Dictionary = {}
	for definition in definitions:
		if definition == null:
			errors.append("null definition")
			continue
		if seen.has(definition.enemy_id): errors.append("duplicate enemy_id: %s" % definition.enemy_id)
		seen[definition.enemy_id] = true
		errors.append_array(definition.validate())
	return errors
