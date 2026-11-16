class_name ProfileStore
extends RefCounted

const SCHEMA_VERSION := 1
var path := "user://progression_profile.cfg"
var last_error: Error = OK

func save_profile(profile: PersistentProfile) -> Error:
	if not is_finite(profile.style_points) or profile.style_points < 0: return ERR_INVALID_DATA
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "schema_version", SCHEMA_VERSION)
	cfg.set_value("profile", "style_points", profile.style_points)
	cfg.set_value("profile", "stat_levels", profile.get_stat_levels())
	last_error = cfg.save(path + ".tmp")
	if last_error != OK: return last_error
	last_error = DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path))
	return last_error

func load_profile(catalog: ProgressionCatalog) -> PersistentProfile:
	var profile := PersistentProfile.new()
	var cfg := ConfigFile.new()
	last_error = cfg.load(path)
	if last_error != OK: return profile
	# Only schema 1 exists; unknown/older versions are read-only defaults.
	if cfg.get_value("profile", "schema_version", 0) != SCHEMA_VERSION:
		last_error = ERR_INVALID_DATA
		return profile
	var points = cfg.get_value("profile", "style_points", null)
	var levels = cfg.get_value("profile", "stat_levels", null)
	if not (points is float or points is int) or not is_finite(float(points)) or points < 0 or not levels is Dictionary:
		last_error = ERR_INVALID_DATA
		return profile
	for id in levels:
		if not (id is String or id is StringName):
			last_error = ERR_INVALID_DATA
			return profile
		var stat := catalog.get_stat(StringName(id))
		if stat == null or not levels[id] is int or levels[id] < 0 or levels[id] > stat.max_level:
			last_error = ERR_INVALID_DATA
			return profile
	profile.style_points = points
	for id in levels: profile.stat_levels[StringName(id)] = levels[id]
	return profile
