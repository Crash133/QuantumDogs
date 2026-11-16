class_name RunCheckpointStore
extends RefCounted

## Active-run Continue checkpoint. It stores the run immediately before its
## target level and that level's starting Style Points balance.

const SCHEMA_VERSION := 2
var path := "user://run_checkpoint.cfg"
var last_error: Error = OK

func save_next_level(run: RunProgressionState, next: StageContext, profile: PersistentProfile) -> Error:
	if run == null or next == null or profile == null or run.ended:
		return _fail(ERR_INVALID_DATA)
	if run._catalog == null or run._catalog.checkpoint_compatibility_id == &"":
		return _fail(ERR_INVALID_DATA)
	if not is_finite(profile.style_points) or profile.style_points < 0.0:
		return _fail(ERR_INVALID_DATA)
	var expected := run.make_next_stage_context(run._catalog)
	if expected == null or next.run_seed != expected.run_seed or next.mode != expected.mode or next.ascent_depth != expected.ascent_depth or next.band != expected.band or next.encounter == null or next.arena_profile == null:
		return _fail(ERR_INVALID_DATA)
	var cfg := ConfigFile.new()
	cfg.set_value("checkpoint", "schema_version", SCHEMA_VERSION)
	cfg.set_value("checkpoint", "catalog_compatibility_id", run._catalog.checkpoint_compatibility_id)
	cfg.set_value("checkpoint", "run", run.to_checkpoint())
	cfg.set_value("checkpoint", "target_depth", next.ascent_depth)
	cfg.set_value("checkpoint", "profile_style_points", profile.style_points)
	cfg.set_value("checkpoint", "profile_stat_levels", profile.get_stat_levels())
	cfg.set_value("checkpoint", "reward_pending", false)
	cfg.set_value("checkpoint", "invalidated", false)
	return _save_config(cfg)

## Transitional bootstrap seam: the integrated controller currently calls this
## after activation. Snapshot its build as the pre-stage payload for that level.
func save_checkpoint(run: RunProgressionState, profile: PersistentProfile) -> Error:
	if run == null or run._catalog == null or run.ascent_depth < 1:
		return _fail(ERR_INVALID_DATA)
	var data := run.to_checkpoint()
	data.ascent_depth = run.ascent_depth - 1
	var before_stage := RunProgressionState.from_checkpoint(data, run._catalog)
	if before_stage == null:
		return _fail(ERR_INVALID_DATA)
	return save_next_level(before_stage, before_stage.make_next_stage_context(run._catalog), profile)

func has_checkpoint() -> bool:
	return FileAccess.file_exists(path)

func has_valid_checkpoint(catalog: ProgressionCatalog) -> bool:
	return not load_checkpoint(catalog).is_empty()

## Returns {run, target_depth, profile_style_points, reward_pending}, or {}.
## Invalid and older checkpoints are read-only failures.
func load_checkpoint(catalog: ProgressionCatalog) -> Dictionary:
	if catalog == null or catalog.checkpoint_compatibility_id == &"":
		last_error = ERR_INVALID_DATA
		return {}
	var cfg := ConfigFile.new()
	last_error = cfg.load(path)
	if last_error != OK: return {}
	if cfg.get_value("checkpoint", "schema_version", 0) != SCHEMA_VERSION:
		last_error = ERR_INVALID_DATA
		return {}
	if cfg.get_value("checkpoint", "invalidated", false) != false:
		last_error = ERR_INVALID_DATA
		return {}
	if StringName(cfg.get_value("checkpoint", "catalog_compatibility_id", "")) != catalog.checkpoint_compatibility_id:
		last_error = ERR_INVALID_DATA
		return {}
	var points = cfg.get_value("checkpoint", "profile_style_points", null)
	var target_depth = cfg.get_value("checkpoint", "target_depth", null)
	var reward_pending = cfg.get_value("checkpoint", "reward_pending", null)
	var stat_levels = cfg.get_value("checkpoint", "profile_stat_levels", null)
	var data = cfg.get_value("checkpoint", "run", null)
	var run := RunProgressionState.from_checkpoint(data, catalog) if data is Dictionary else null
	if run == null or not (points is float or points is int) or not is_finite(float(points)) or points < 0.0 or not target_depth is int or target_depth != run.ascent_depth + 1 or not reward_pending is bool or not stat_levels is Dictionary:
		last_error = ERR_INVALID_DATA
		return {}
	for id in stat_levels:
		var stat := catalog.get_stat(StringName(id))
		if stat == null or not stat_levels[id] is int or stat_levels[id] < 0 or stat_levels[id] > stat.max_level:
			last_error = ERR_INVALID_DATA
			return {}
	var target := run.make_next_stage_context(catalog)
	if target.ascent_depth != target_depth or target.arena_profile == null or target.encounter == null:
		last_error = ERR_INVALID_DATA
		return {}
	last_error = OK
	return {"run": run, "target_depth": target_depth, "profile_style_points": float(points), "profile_stat_levels": stat_levels.duplicate(true), "reward_pending": reward_pending}

## Atomically mark the old level-start checkpoint before accepting reward purchases.
func mark_reward_pending() -> Error:
	var cfg := ConfigFile.new()
	last_error = cfg.load(path)
	if last_error != OK: return last_error
	if cfg.get_value("checkpoint", "schema_version", 0) != SCHEMA_VERSION:
		return _fail(ERR_INVALID_DATA)
	cfg.set_value("checkpoint", "reward_pending", true)
	return _save_config(cfg)

## Persist invalidation before attempting removal. If removal fails, the file
## remains present but can no longer be accepted as an active checkpoint.
func invalidate_checkpoint() -> Error:
	if not has_checkpoint():
		last_error = OK
		return OK
	var cfg := ConfigFile.new()
	last_error = cfg.load(path)
	if last_error != OK: return last_error
	if cfg.get_value("checkpoint", "schema_version", 0) != SCHEMA_VERSION:
		return clear()
	cfg.set_value("checkpoint", "invalidated", true)
	var mark_error := _save_config(cfg)
	if mark_error != OK: return mark_error
	return clear()

## Restore the active level's currency, and restore stat levels only when an
## unresolved reward purchase would otherwise become permanent.
func reconcile_profile(store: ProfileStore, catalog: ProgressionCatalog) -> Error:
	if store == null or catalog == null:
		return _fail(ERR_INVALID_PARAMETER)
	var checkpoint := load_checkpoint(catalog)
	if checkpoint.is_empty():
		if not has_checkpoint():
			last_error = OK
			return OK
		return last_error
	var profile := store.load_profile(catalog)
	if FileAccess.file_exists(store.path) and store.last_error != OK:
		return _fail(store.last_error)
	profile.style_points = checkpoint.profile_style_points
	if checkpoint.reward_pending:
		profile.stat_levels.clear()
		for id in checkpoint.profile_stat_levels:
			profile.stat_levels[StringName(id)] = int(checkpoint.profile_stat_levels[id])
	last_error = store.save_profile(profile)
	return last_error

## Roll back only the level-start currency; permanent stat levels are current.
func restore_currency(profile: PersistentProfile, checkpoint: Dictionary) -> Error:
	if profile == null or checkpoint.is_empty() or not checkpoint.get("run") is RunProgressionState or not checkpoint.get("target_depth") is int or not checkpoint.get("profile_style_points") is float or not is_finite(checkpoint.profile_style_points) or checkpoint.profile_style_points < 0.0:
		return _fail(ERR_INVALID_DATA)
	profile.style_points = checkpoint.profile_style_points
	last_error = OK
	return OK

func clear() -> Error:
	if not has_checkpoint(): return OK
	last_error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return last_error

func _fail(error: Error) -> Error:
	last_error = error
	return error

func _save_config(cfg: ConfigFile) -> Error:
	last_error = cfg.save(path + ".tmp")
	if last_error != OK: return last_error
	last_error = DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path))
	return last_error
