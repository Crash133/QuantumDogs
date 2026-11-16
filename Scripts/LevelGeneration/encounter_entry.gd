extends Resource
class_name EncounterEntry

@export var enemy_id: StringName = &""
@export_range(-100000, 100000, 1) var count: int = 0
@export var spawn_tags: Array[StringName] = []

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if enemy_id.is_empty():
		errors.append("Encounter enemy ID cannot be empty.")
	if count < 0:
		errors.append("Encounter count cannot be negative.")
	for tag in spawn_tags:
		if tag.is_empty():
			errors.append("Encounter spawn tags cannot contain an empty tag.")
	return errors
