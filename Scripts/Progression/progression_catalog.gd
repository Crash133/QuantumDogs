class_name ProgressionCatalog
extends Resource

const MODES = [&"Normal", &"Challenger", &"Chaos"]
const BANDS = [&"Easy", &"Medium", &"Hard"]
const STATS = [&"damage", &"heat_damage_multiplier", &"battery_drain_reduction", &"dash_cooldown_reduction", &"heat_gauge_increase"]
@export var tuning_note: String
## Explicit compatibility ID for checkpointed stage generation/catalog data.
@export var checkpoint_compatibility_id: StringName = &""
@export var melee_weapon_ids: Array[StringName] = []
@export var revolver_id: StringName = &"revolver"
@export var stage_counts: Dictionary = {}
@export var stat_definitions: Array[StatUpgradeDefinition] = []
@export var difficulty_profiles: Array[DifficultyProfile] = []
## Keys are Mode/Band, values are arrays of owner-authored encounter Resources.
@export var encounters: Dictionary = {}
@export var arena_profiles: Dictionary = {}
@export var weapon_upgrades: Array[WeaponUpgradeDefinition] = []
## PROPOSED, not approved balance/design: offer fewer cards and skip empty deck.
@export var allow_exhausted_deck_fallback: bool = true

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var weapons := {}
	for id in melee_weapon_ids:
		if id == &"" or id == revolver_id or weapons.has(id): errors.append("Invalid/duplicate melee ID")
		weapons[id] = true
	if weapons.size() != 4 or melee_weapon_ids.size() != 4 or revolver_id == &"": errors.append("Require four melee weapons and separate Revolver")
	weapons[revolver_id] = true
	for band in BANDS:
		if not stage_counts.get(band) is int or stage_counts.get(band, 0) <= 0: errors.append("Invalid stage count")
	var stats := {}
	for stat in stat_definitions:
		if stat == null or not stat.is_valid():
			errors.append("Invalid stat cost/cap")
			continue
		if stats.has(stat.stat_id) or not STATS.has(stat.stat_id): errors.append("Duplicate/unknown stat")
		stats[stat.stat_id] = true
	if stats.size() != 5: errors.append("Require all five paid stats")
	var profiles := {}
	for profile in difficulty_profiles:
		if profile == null: 
			errors.append("Missing difficulty")
			continue
		var key := String(profile.mode) + "/" + String(profile.band)
		if profiles.has(key) or not MODES.has(profile.mode) or not BANDS.has(profile.band) or not profile.is_valid(): errors.append("Invalid difficulty")
		profiles[key] = true
	for mode in MODES:
		for band in BANDS:
			var key := String(mode) + "/" + String(band)
			if not profiles.has(key): errors.append("Missing difficulty " + key)
			var pool = encounters.get(key, [])
			if not pool is Array or pool.is_empty(): errors.append("Missing encounter " + key)
			else:
				for encounter in pool:
					if not encounter is Resource: errors.append("Invalid encounter")
			if not arena_profiles.get(key) is Resource: errors.append("Missing arena profile")
	var ids := {}
	var levels := {}
	for upgrade in weapon_upgrades:
		if upgrade == null:
			errors.append("Missing upgrade")
			continue
		var key := String(upgrade.family_id) + "/" + str(upgrade.level)
		if upgrade.upgrade_id == &"" or upgrade.family_id == &"" or upgrade.level < 1 or ids.has(upgrade.upgrade_id) or levels.has(key): errors.append("Invalid duplicate upgrade/family level")
		ids[upgrade.upgrade_id] = upgrade
		levels[key] = true
		if upgrade.eligible_weapon_ids.is_empty(): errors.append("Upgrade needs eligible weapons")
		for weapon in upgrade.eligible_weapon_ids:
			if not weapons.has(weapon): errors.append("Unknown upgrade weapon")
	for upgrade in weapon_upgrades:
		if upgrade == null: continue
		var prior = ids.get(upgrade.prerequisite_upgrade_id)
		if upgrade.level == 1:
			if upgrade.prerequisite_upgrade_id != &"": errors.append("Level one has prerequisite")
		elif prior == null or prior.family_id != upgrade.family_id or prior.level != upgrade.level - 1:
			errors.append("Gapped/cross-family prerequisite")
	return errors

func get_stat(id: StringName) -> StatUpgradeDefinition:
	for stat in stat_definitions:
		if stat != null and stat.stat_id == id: return stat
	return null

func get_stage_count(band: StringName) -> int:
	return stage_counts.get(band, 0)

func get_difficulty(mode: StringName, band: StringName, depth: int) -> Dictionary:
	for profile in difficulty_profiles:
		if profile.mode == mode and profile.band == band: return profile.get_parameters_at(depth)
	return {}

func get_encounter(mode: StringName, band: StringName, depth: int, run_seed: int) -> Resource:
	var pool: Array = encounters.get(String(mode) + "/" + String(band), [])
	if pool.is_empty(): return null
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed + depth
	return pool[rng.randi_range(0, pool.size() - 1)].duplicate(true)
