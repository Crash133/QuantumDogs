class_name ProgressionService
extends RefCounted

signal profile_changed(snapshot: Dictionary)
signal reward_selected
signal run_ended
var profile: PersistentProfile
var run: RunProgressionState
var catalog: ProgressionCatalog
var profile_store: ProfileStore
var last_save_error: Error = OK
var _offer: Dictionary = {}
var _serial := 0

func configure(p: PersistentProfile, r: RunProgressionState, c: ProgressionCatalog, store: ProfileStore) -> void:
	profile = p
	run = r
	catalog = c
	profile_store = store
	run.profile_stat_levels = profile.get_stat_levels()
	_offer.clear()

func _persist() -> void:
	last_save_error = profile_store.save_profile(profile)
	profile_changed.emit(profile_snapshot())

func credit_style_points(amount: float) -> bool:
	if not profile.credit_style_points(amount): return false
	_persist()
	return true

func purchase_stat(stat_id: StringName) -> Dictionary:
	if run.ended: return {"success": false, "error": "Run ended"}
	var result := profile.try_purchase(stat_id, catalog)
	if result.success:
		run.profile_stat_levels = profile.get_stat_levels()
		_persist()
	result["save_error"] = last_save_error
	return result

func profile_snapshot() -> Dictionary:
	var stats: Array = []
	for definition in catalog.stat_definitions:
		var level: int = profile.stat_levels.get(definition.stat_id, 0)
		var capped := level >= definition.max_level
		var cost := 0.0 if capped else definition.cost_by_level[level]
		stats.append({"id": definition.stat_id, "level": level, "cap": definition.max_level, "cost": cost, "capped": capped, "can_purchase": not run.ended and not capped and profile.style_points >= cost})
	return {"style_points": profile.style_points, "stat_levels": profile.get_stat_levels(), "stats": stats, "save_error": last_save_error}

func build_reward_offer(is_weapon_milestone: bool) -> Dictionary:
	if not _offer.is_empty() and not run.reward_resolved: return _offer.duplicate(true)
	_serial += 1
	var milestone := run.get_weapon_draft_band(catalog) != &""
	# Caller hint cannot create or suppress an actual milestone.
	if is_weapon_milestone != milestone: pass
	var weapons: Array = run.get_weapon_draft_candidates() if milestone else []
	var upgrades: Array = [] if milestone else run.deck.draw_offer(3, run.run_seed + run.ascent_depth)
	var required := 1 if milestone else mini(2 if run.run_difficulty == &"Chaos" else 1, upgrades.size())
	var blocked := run.ended or (not milestone and upgrades.size() < 3 and not catalog.allow_exhausted_deck_fallback)
	_offer = {"offer_id": _serial, "depth": run.ascent_depth, "milestone": milestone, "weapons": weapons, "upgrades": upgrades, "required_count": required, "blocked": blocked, "stats": profile_snapshot().stats}
	run.reward_resolved = false
	return _offer.duplicate(true)

func select_reward_ids(ids: Array[StringName], offer: Dictionary) -> bool:
	if run.ended or run.reward_resolved or _offer.is_empty() or offer.get("offer_id") != _offer.offer_id or run.ascent_depth != _offer.depth or _offer.blocked or ids.size() != _offer.required_count: return false
	var unique := {}
	for id in ids:
		if unique.has(id): return false
		unique[id] = true
	if _offer.milestone:
		if not _offer.weapons.has(ids[0]) or not run.apply_weapon_draft(ids[0], catalog): return false
	elif not run.deck.resolve_offer(ids, catalog): return false
	run.reward_resolved = true
	_offer.clear()
	reward_selected.emit()
	return true

func on_player_dead(revives: int) -> void:
	if run.end_run_if_dead(revives):
		_offer.clear()
		run_ended.emit()

