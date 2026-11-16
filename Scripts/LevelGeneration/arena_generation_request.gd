extends Resource
class_name ArenaGenerationRequest

const ArenaProfileType = preload("res://Scripts/LevelGeneration/arena_profile.gd")
const EncounterDefinitionType = preload("res://Scripts/LevelGeneration/encounter_definition.gd")

@export var run_seed: int = 0
@export var ascent_depth: int = 0
@export var profile: ArenaProfileType
@export var encounter: EncounterDefinitionType
## Enemies alive at once. Spawn anchors only need room for this many, because
## the rest of the manifest respawns as they die. 0 = the whole manifest at once.
@export var max_concurrent: int = 0

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if ascent_depth < 0:
		errors.append("Ascent depth cannot be negative.")
	if profile == null:
		errors.append("Arena generation request is missing a profile.")
	else:
		errors.append_array(profile.validate())
	if encounter == null:
		errors.append("Arena generation request is missing an encounter definition.")
	else:
		errors.append_array(encounter.validate())
	return errors
