class_name RunProgressionState
extends RefCounted

var run_difficulty: StringName
var run_seed: int
var ascent_depth: int = 0
var band: StringName = &"Easy"
var acquired_melee_weapon_ids: Array[StringName] = []
var revolver_available := true
var deck := RunUpgradeDeck.new()
var encounter: Resource
var reward_resolved := false
var ended := false
var profile_stat_levels: Dictionary = {}
var _catalog: ProgressionCatalog
var _drafted_bands: Array[StringName] = []

static func begin_run(mode: StringName, seed: int, catalog: ProgressionCatalog) -> RunProgressionState:
	if not ProgressionCatalog.MODES.has(mode) or not catalog.validate().is_empty(): return null
	var run := RunProgressionState.new()
	run._catalog = catalog
	run.run_difficulty = mode
	run.run_seed = seed
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var weapon := catalog.melee_weapon_ids[rng.randi_range(0, 3)]
	run.acquired_melee_weapon_ids.append(weapon)
	run.deck.add_weapon(weapon, catalog)
	run.deck.add_weapon(catalog.revolver_id, catalog)
	return run

func get_weapon_draft_band(catalog: ProgressionCatalog) -> StringName:
	var boundary := 0
	for candidate in ProgressionCatalog.BANDS:
		boundary += catalog.get_stage_count(candidate)
		if ascent_depth == boundary and not _drafted_bands.has(candidate): return candidate
	return &""

func get_weapon_draft_candidates() -> Array[StringName]:
	var result: Array[StringName] = []
	if ended or get_weapon_draft_band(_catalog) == &"": return result
	for weapon in _catalog.melee_weapon_ids:
		if not acquired_melee_weapon_ids.has(weapon): result.append(weapon)
	return result

func apply_weapon_draft(weapon_id: StringName, catalog: ProgressionCatalog) -> bool:
	if not get_weapon_draft_candidates().has(weapon_id): return false
	_drafted_bands.append(get_weapon_draft_band(catalog))
	acquired_melee_weapon_ids.append(weapon_id)
	deck.add_weapon(weapon_id, catalog)
	return true

func make_next_stage_context(catalog: ProgressionCatalog) -> StageContext:
	var context := StageContext.new()
	context.run_seed = run_seed
	context.ascent_depth = ascent_depth + 1
	context.mode = run_difficulty
	var easy := catalog.get_stage_count(&"Easy")
	var medium := easy + catalog.get_stage_count(&"Medium")
	context.band = &"Easy" if context.ascent_depth <= easy else (&"Medium" if context.ascent_depth <= medium else &"Hard")
	context.difficulty_parameters = catalog.get_difficulty(run_difficulty, context.band, context.ascent_depth)
	context.arena_profile = catalog.arena_profiles[String(run_difficulty) + "/" + String(context.band)].duplicate(true)
	context.encounter = catalog.get_encounter(run_difficulty, context.band, context.ascent_depth, run_seed)
	return context

func advance_stage(context: StageContext) -> bool:
	if ended or context == null or context.run_seed != run_seed or context.mode != run_difficulty or context.ascent_depth != ascent_depth + 1 or context.encounter == null or context.arena_profile == null: return false
	ascent_depth = context.ascent_depth
	band = context.band
	encounter = context.encounter.duplicate(true)
	reward_resolved = false
	return true

func end_run_if_dead(revives: int) -> bool:
	if revives > 0 or ended: return false
	ended = true
	return true

## Level-start checkpoint (see RunCheckpointStore). Only valid between levels.
func to_checkpoint() -> Dictionary:
	return {"mode": run_difficulty, "seed": run_seed, "ascent_depth": ascent_depth, "band": band, "weapons": acquired_melee_weapon_ids.duplicate(), "revolver": revolver_available, "drafted_bands": _drafted_bands.duplicate(), "deck": deck.to_checkpoint(), "catalog_id": _catalog.checkpoint_compatibility_id if _catalog != null else &""}

## Rebuilds the run positioned before its saved level (ascent_depth - 1) so
## make_next_stage_context() reproduces that level's context deterministically.
static func from_checkpoint(data: Dictionary, catalog: ProgressionCatalog) -> RunProgressionState:
	var depth = data.get("ascent_depth")
	var seed = data.get("seed")
	if not depth is int or depth < 0 or not seed is int: return null
	if StringName(data.get("catalog_id", "")) != catalog.checkpoint_compatibility_id or catalog.checkpoint_compatibility_id == &"": return null
	var run := begin_run(StringName(data.get("mode", "")), seed, catalog)
	var restored_deck := RunUpgradeDeck.from_checkpoint(data.get("deck", {}), catalog) if data.get("deck") is Dictionary else null
	if run == null or restored_deck == null: return null
	run.ascent_depth = depth
	run.band = StringName(data.get("band", "Easy"))
	run.revolver_available = bool(data.get("revolver", true))
	run.acquired_melee_weapon_ids.clear()
	for weapon in data.get("weapons", []):
		if not catalog.melee_weapon_ids.has(StringName(weapon)): return null
		run.acquired_melee_weapon_ids.append(StringName(weapon))
	run._drafted_bands.clear()
	for drafted in data.get("drafted_bands", []): run._drafted_bands.append(StringName(drafted))
	run.deck = restored_deck
	run.reward_resolved = true
	return run
