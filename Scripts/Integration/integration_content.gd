class_name IntegrationContent
extends RefCounted

## Fills Progression's temporary catalog with concrete Level Generation profiles
## and EncounterDefinitions that use the real EnemyCatalog IDs.
## shortcut: integrator placeholder content (band -> silhouette, small rosters);
## replace with owner-authored stage data once Progression/LevelGen/Enemies agree it.

const BASE_CATALOG := "res://Resources/Progression/temporary_catalog.tres"
## Each band mixes silhouettes (all share a 4 m module unit) so runs vary.
const PROFILES_BY_BAND := {
	&"Easy": ["plus_balcony", "balcony", "square"],
	&"Medium": ["column_corridor", "coliseum", "balcony"],
	&"Hard": ["square_funnel", "coliseum", "column_corridor"],
}
## Horde sizes per band. Levels 1-2 (Easy) are 50-80, then Normal 300-400 with
## 5% elites and Hard 500 with 15% elites; a band never grows with depth.
## RunController.active_enemy_cap keeps ~20 alive at once.
const TOTALS_BY_BAND := {
	&"Easy": [50, 65, 80],
	&"Medium": [300, 350, 400],
	&"Hard": [500],
}
const ELITE_SHARE_BY_BAND := {&"Easy": 0.0, &"Medium": 0.05, &"Hard": 0.15}
const DRONE_SHARE := 0.2

static func make_profile(band: StringName) -> ArenaProfile:
	var sources: Array = []
	for id in PROFILES_BY_BAND[band]:
		sources.append(load("res://Scenes/LevelGeneration/Profiles/%s.tres" % id))
	return ArenaProfile.merge(sources)

static func make_catalog() -> ProgressionCatalog:
	var catalog := (load(BASE_CATALOG) as ProgressionCatalog).duplicate(true) as ProgressionCatalog
	var profiles := {}
	var encounters := {}
	for mode in ProgressionCatalog.MODES:
		for band in ProgressionCatalog.BANDS:
			var key := String(mode) + "/" + String(band)
			profiles[key] = make_profile(band)
			encounters[key] = TOTALS_BY_BAND[band].map(func(total: int) -> EncounterDefinition: return make_encounter(band, total))
	catalog.arena_profiles = profiles
	catalog.encounters = encounters
	catalog.checkpoint_compatibility_id = &"integration-content-v1"
	return catalog

static func make_encounter(band: StringName, total: int = 0) -> EncounterDefinition:
	if total <= 0:
		total = TOTALS_BY_BAND[band][0]
	var elites := roundi(total * ELITE_SHARE_BY_BAND[band])
	var drones := roundi(total * DRONE_SHARE)
	var encounter := EncounterDefinition.new()
	for pair in [[&"common", total - elites - drones], [&"drone", drones], [&"elite", elites]]:
		if pair[1] <= 0:
			continue
		var entry := EncounterEntry.new()
		entry.enemy_id = pair[0]
		entry.count = pair[1]
		# Generated tiles only publish `ground` anchors; drones hover above them.
		entry.spawn_tags = [&"ground"]
		encounter.entries.append(entry)
	return encounter
