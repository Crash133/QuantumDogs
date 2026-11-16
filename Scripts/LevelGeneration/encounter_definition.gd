extends Resource
class_name EncounterDefinition

const EncounterEntryType = preload("res://Scripts/LevelGeneration/encounter_entry.gd")

@export var entries: Array[EncounterEntryType] = []

func get_total_count() -> int:
	var total := 0
	for entry in entries:
		if entry != null and entry.count >= 0:
			total += entry.count
	return total

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for index in range(entries.size()):
		var entry: EncounterEntryType = entries[index]
		if entry == null:
			errors.append("Encounter entry %d is null." % index)
		else:
			errors.append_array(entry.validate())
	return errors
