extends Resource
class_name ArenaProfile

const ArenaModuleDefinitionType = preload("res://Scripts/LevelGeneration/arena_module_definition.gd")
const SILHOUETTE_PLUS_BALCONY: StringName = &"plus_balcony"
const SILHOUETTE_COLUMN_CORRIDOR: StringName = &"column_corridor"
const SILHOUETTE_SQUARE_FUNNEL: StringName = &"square_funnel"
const SILHOUETTE_BALCONY: StringName = &"balcony"
const SILHOUETTE_COLISEUM: StringName = &"coliseum"
const SILHOUETTE_SQUARE: StringName = &"square"
const SUPPORTED_SILHOUETTES: Array[StringName] = [
	SILHOUETTE_PLUS_BALCONY,
	SILHOUETTE_COLUMN_CORRIDOR,
	SILHOUETTE_SQUARE_FUNNEL,
	SILHOUETTE_BALCONY,
	SILHOUETTE_COLISEUM,
	SILHOUETTE_SQUARE,
]

@export var allowed_silhouettes: Array[StringName] = []
@export_range(0.1, 100.0, 0.1) var module_unit_size: float = 4.0
@export var silhouette_weights: Dictionary = {}
@export var normalized_footprints: Dictionary = {}
@export_multiline var silhouette_source_note: String = ""
@export var core_modules: Dictionary = {}
@export var module_catalogue: Array[ArenaModuleDefinitionType] = []
@export var fallback_scenes: Dictionary = {}
@export_range(1, 256, 1) var max_attempts: int = 16

## One profile that offers every silhouette of `sources` (each source keeps its
## own footprint, core module and fallback). Sources must share module_unit_size.
## Returns null and fills `errors` when they cannot be combined.
static func merge(sources: Array, errors: PackedStringArray = PackedStringArray()) -> ArenaProfile:
	var merged := ArenaProfile.new()
	var seen_modules := {}
	for source_value in sources:
		var source := source_value as ArenaProfile
		if source == null:
			errors.append("Cannot merge a null arena profile.")
			return null
		if merged.allowed_silhouettes.is_empty():
			merged.module_unit_size = source.module_unit_size
			merged.max_attempts = source.max_attempts
			merged.silhouette_source_note = source.silhouette_source_note
		elif not is_equal_approx(merged.module_unit_size, source.module_unit_size):
			errors.append("Cannot merge arena profiles with different module_unit_size.")
			return null
		for silhouette_id in source.allowed_silhouettes:
			if merged.allowed_silhouettes.has(silhouette_id):
				continue
			merged.allowed_silhouettes.append(silhouette_id)
			merged.normalized_footprints[silhouette_id] = source.normalized_footprints.get(silhouette_id)
			merged.core_modules[silhouette_id] = source.core_modules.get(silhouette_id)
			merged.fallback_scenes[silhouette_id] = source.fallback_scenes.get(silhouette_id)
			if source.silhouette_weights.has(silhouette_id):
				merged.silhouette_weights[silhouette_id] = source.silhouette_weights[silhouette_id]
		for module in source.module_catalogue:
			if module != null and not seen_modules.has(module.module_id):
				seen_modules[module.module_id] = true
				merged.module_catalogue.append(module)
	return merged

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if allowed_silhouettes.is_empty():
		errors.append("Arena profile must allow at least one silhouette.")
	var seen := {}
	for silhouette_id in allowed_silhouettes:
		if not SUPPORTED_SILHOUETTES.has(silhouette_id):
			errors.append("Unsupported silhouette ID '%s'." % silhouette_id)
		if seen.has(silhouette_id):
			errors.append("Duplicate silhouette ID '%s'." % silhouette_id)
		seen[silhouette_id] = true
	for silhouette_id in allowed_silhouettes:
		if not normalized_footprints.has(silhouette_id):
			errors.append("Missing normalized footprint for silhouette '%s'." % silhouette_id)
			continue
		var footprint_value: Variant = normalized_footprints[silhouette_id]
		if not footprint_value is PackedVector2Array:
			errors.append("Normalized footprint for silhouette '%s' must be a PackedVector2Array." % silhouette_id)
			continue
		var footprint: PackedVector2Array = footprint_value
		if footprint.size() < 3:
			errors.append("Normalized footprint for silhouette '%s' needs at least three points." % silhouette_id)
			continue
		for point in footprint:
			if point.x < 0.0 or point.x > 1.0 or point.y < 0.0 or point.y > 1.0:
				errors.append("Normalized footprint for silhouette '%s' must stay inside [0, 1]." % silhouette_id)
				break
	for silhouette_id in silhouette_weights:
		if not allowed_silhouettes.has(silhouette_id):
			errors.append("Weight provided for silhouette '%s' outside the allow-list." % silhouette_id)
		var weight := float(silhouette_weights[silhouette_id])
		if not is_finite(weight) or weight < 0.0:
			errors.append("Silhouette weight for '%s' must be finite and nonnegative." % silhouette_id)
	if not silhouette_weights.is_empty():
		var total_weight := 0.0
		for silhouette_id in allowed_silhouettes:
			total_weight += maxf(float(silhouette_weights.get(silhouette_id, 1.0)), 0.0)
		if total_weight <= 0.0:
			errors.append("Allowed silhouette weights must have a positive total.")
	if module_unit_size <= 0.0:
		errors.append("Arena module unit size must be greater than zero.")
	if max_attempts <= 0:
		errors.append("Arena generation max_attempts must be greater than zero.")
	return errors

func choose_silhouette(rng: RandomNumberGenerator) -> StringName:
	if rng == null or allowed_silhouettes.is_empty():
		return &""
	var total_weight := 0.0
	for silhouette_id in allowed_silhouettes:
		total_weight += maxf(float(silhouette_weights.get(silhouette_id, 1.0)), 0.0)
	if total_weight <= 0.0:
		total_weight = float(allowed_silhouettes.size())
		var equal_choice := rng.randf() * total_weight
		return allowed_silhouettes[mini(int(equal_choice), allowed_silhouettes.size() - 1)]
	var choice := rng.randf() * total_weight
	for silhouette_id in allowed_silhouettes:
		choice -= maxf(float(silhouette_weights.get(silhouette_id, 1.0)), 0.0)
		if choice < 0.0:
			return silhouette_id
	return allowed_silhouettes.back()
