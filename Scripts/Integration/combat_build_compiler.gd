class_name CombatBuildCompiler
extends RefCounted

const STAT_IDS: Array[StringName] = [
	&"damage",
	&"heat_damage_multiplier",
	&"battery_drain_reduction",
	&"dash_cooldown_reduction",
	&"heat_gauge_increase",
]
const STAT_IDENTITIES: Dictionary = {
	&"damage": 1.0,
	&"heat_damage_multiplier": 1.0,
	&"battery_drain_reduction": 1.0,
	&"dash_cooldown_reduction": 1.0,
	&"heat_gauge_increase": 0.0,
}
const UPGRADE_FIELDS: Array[StringName] = [&"damage_multiplier", &"heat_multiplier"]

func compile(
	profile: PersistentProfile,
	run: RunProgressionState,
	catalog: ProgressionCatalog,
	base_tuning: CombatTuning,
	base_weapons: Array[WeaponData],
	policy: CombatBuildPolicy
) -> Dictionary:
	var errors := PackedStringArray()
	if profile == null or run == null or catalog == null or base_tuning == null or policy == null:
		return _failure(["Compiler input is null"])
	if base_weapons.is_empty(): return _failure(["Base weapon catalog is empty"])

	var stat_levels := _validated_stat_levels(profile, catalog, errors)
	_validate_policy(policy, catalog, errors)
	var base_by_id: Dictionary = {}
	for weapon in base_weapons:
		if weapon == null or weapon.id == &"" or base_by_id.has(weapon.id):
			errors.append("Base weapons contain a null, empty-ID, or duplicate resource")
			continue
		if not catalog.melee_weapon_ids.has(weapon.id):
			errors.append("Base weapon is not in the Progression catalog: %s" % weapon.id)
		if not weapon.validate().is_empty():
			errors.append("Invalid base weapon resource: %s" % weapon.id)
		base_by_id[weapon.id] = weapon

	var ordered_weapons: Array[WeaponData] = []
	var seen_acquired: Dictionary = {}
	for weapon_id in run.acquired_melee_weapon_ids:
		if seen_acquired.has(weapon_id):
			errors.append("Duplicate acquired weapon ID: %s" % weapon_id)
			continue
		seen_acquired[weapon_id] = true
		if not catalog.melee_weapon_ids.has(weapon_id):
			errors.append("Unknown acquired weapon ID: %s" % weapon_id)
			continue
		if not base_by_id.has(weapon_id):
			errors.append("Acquired weapon has no base WeaponData: %s" % weapon_id)
			continue
		ordered_weapons.append(base_by_id[weapon_id])
	if ordered_weapons.is_empty(): errors.append("Run build has no acquired melee weapons")

	var catalog_cards: Dictionary = {}
	for card in catalog.weapon_upgrades:
		if card == null: continue
		if catalog_cards.has(card.upgrade_id):
			errors.append("Duplicate catalog upgrade ID: %s" % card.upgrade_id)
		else:
			catalog_cards[card.upgrade_id] = card
	var selected_cards: Array = run.deck.selected_cards() if run.deck != null else []
	var selected_ids: Dictionary = {}
	var selected_family_levels: Dictionary = {}
	var best_by_family_and_weapon: Dictionary = {}
	for selected in selected_cards:
		if not selected is WeaponUpgradeDefinition:
			errors.append("Selected upgrade is not a WeaponUpgradeDefinition")
			continue
		var card: WeaponUpgradeDefinition = selected
		if card.upgrade_id == &"" or not catalog_cards.has(card.upgrade_id):
			errors.append("Selected upgrade is absent from catalog: %s" % card.upgrade_id)
			continue
		if selected_ids.has(card.upgrade_id):
			errors.append("Duplicate selected upgrade: %s" % card.upgrade_id)
			continue
		selected_ids[card.upgrade_id] = true
		var catalog_card: WeaponUpgradeDefinition = catalog_cards[card.upgrade_id]
		if card.family_id != catalog_card.family_id or card.level != catalog_card.level or card.eligible_weapon_ids != catalog_card.eligible_weapon_ids:
			errors.append("Selected upgrade differs from catalog: %s" % card.upgrade_id)
		if card.family_id == &"" or card.level < 1 or card.eligible_weapon_ids.is_empty():
			errors.append("Selected upgrade has invalid definition: %s" % card.upgrade_id)
		var family_key := String(card.family_id)
		var level_key := family_key + "/" + str(card.level)
		if selected_family_levels.has(level_key): errors.append("Multiple selected upgrades share family level: %s" % level_key)
		selected_family_levels[level_key] = true
		for eligible_id in card.eligible_weapon_ids:
			if not catalog.melee_weapon_ids.has(eligible_id) and eligible_id != catalog.revolver_id:
				errors.append("Upgrade has unknown eligible weapon: %s" % eligible_id)
		if not policy.upgrade_values.has(card.upgrade_id):
			errors.append("Selected upgrade has no approved scalar policy: %s" % card.upgrade_id)
		if not best_by_family_and_weapon.has(family_key): best_by_family_and_weapon[family_key] = {}
		var best_for_weapon: Dictionary = best_by_family_and_weapon[family_key]
		for eligible_id in card.eligible_weapon_ids:
			if not best_for_weapon.has(eligible_id) or card.level > best_for_weapon[eligible_id].level:
				best_for_weapon[eligible_id] = card
	for selected_id in selected_ids:
		var selected_card: WeaponUpgradeDefinition = catalog_cards[selected_id]
		if selected_card.level > 1 and not selected_ids.has(selected_card.prerequisite_upgrade_id):
			errors.append("Selected upgrade prerequisite is missing: %s" % selected_card.upgrade_id)

	if not errors.is_empty(): return _failure(errors)

	var tuning := base_tuning.duplicate(true) as CombatTuning
	var damage_factor: float = _stat_value(policy, &"damage", stat_levels[&"damage"], errors)
	var heat_factor: float = _stat_value(policy, &"heat_damage_multiplier", stat_levels[&"heat_damage_multiplier"], errors)
	var drain_factor: float = _stat_value(policy, &"battery_drain_reduction", stat_levels[&"battery_drain_reduction"], errors)
	var dash_factor: float = _stat_value(policy, &"dash_cooldown_reduction", stat_levels[&"dash_cooldown_reduction"], errors)
	var heat_addition: float = _stat_value(policy, &"heat_gauge_increase", stat_levels[&"heat_gauge_increase"], errors)
	tuning.battery_baseline_drain_per_second = base_tuning.battery_baseline_drain_per_second * drain_factor
	tuning.dash_regen_ticks = maxi(1, roundi(float(base_tuning.dash_regen_ticks) * dash_factor))
	tuning.heat_max = base_tuning.heat_max + heat_addition
	var multipliers: Dictionary[StringName, Vector2] = {}
	for weapon in ordered_weapons:
		multipliers[weapon.id] = Vector2(damage_factor, heat_factor)
	multipliers[catalog.revolver_id] = Vector2(damage_factor, heat_factor)
	for family_key in best_by_family_and_weapon:
		var best_for_weapon: Dictionary = best_by_family_and_weapon[family_key]
		for target_id in best_for_weapon:
			if not multipliers.has(target_id): continue
			var card: WeaponUpgradeDefinition = best_for_weapon[target_id]
			var values: Dictionary = policy.upgrade_values.get(card.upgrade_id, {})
			var card_damage := float(values.get(&"damage_multiplier", 1.0))
			var card_heat := float(values.get(&"heat_multiplier", 1.0))
			var old: Vector2 = multipliers[target_id]
			multipliers[target_id] = Vector2(old.x * card_damage, old.y * card_heat)
	if not errors.is_empty(): return _failure(errors)

	var build := CombatRunBuild.new()
	build.weapons = ordered_weapons
	build.revolver_available = run.revolver_available
	build.tuning = tuning
	build.hit_multipliers = multipliers
	var build_errors := build.validate()
	if not build_errors.is_empty(): return _failure(build_errors)
	return {"ok": true, "build": build, "errors": PackedStringArray()}

func _validated_stat_levels(profile: PersistentProfile, catalog: ProgressionCatalog, errors: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for stat_id in STAT_IDS: result[stat_id] = 0
	for raw_id in profile.stat_levels:
		var stat_id := StringName(raw_id)
		var definition := catalog.get_stat(stat_id)
		var level = profile.stat_levels[raw_id]
		if not STAT_IDS.has(stat_id) or definition == null:
			errors.append("Unknown purchased stat ID: %s" % stat_id)
			continue
		if not definition.is_valid() or not level is int or level < 0 or level > definition.max_level:
			errors.append("Invalid purchased level for stat: %s" % stat_id)
			continue
		result[stat_id] = level
	return result

func _validate_policy(policy: CombatBuildPolicy, catalog: ProgressionCatalog, errors: PackedStringArray) -> void:
	for raw_id in policy.stat_values:
		var stat_id := StringName(raw_id)
		if not STAT_IDS.has(stat_id):
			errors.append("Unsupported policy stat: %s" % stat_id)
			continue
		var values = policy.stat_values[raw_id]
		if not values is Array or values.is_empty():
			errors.append("Stat policy must be a nonempty Array: %s" % stat_id)
			continue
		for value in values:
			if not _valid_nonnegative_number(value): errors.append("Invalid stat policy value: %s" % stat_id)
		if _valid_nonnegative_number(values[0]) and not is_equal_approx(float(values[0]), float(STAT_IDENTITIES[stat_id])):
			errors.append("Stat policy level 0 must be identity: %s" % stat_id)
	for raw_id in policy.upgrade_values:
		var upgrade_id := StringName(raw_id)
		var found := false
		for card in catalog.weapon_upgrades:
			if card != null and card.upgrade_id == upgrade_id:
				found = true
				break
		if not found:
			errors.append("Upgrade policy references unknown card: %s" % upgrade_id)
		var values = policy.upgrade_values[raw_id]
		if not values is Dictionary:
			errors.append("Upgrade policy must be a Dictionary: %s" % upgrade_id)
			continue
		for field in values:
			if not UPGRADE_FIELDS.has(StringName(field)):
				errors.append("Unsupported weapon upgrade modifier: %s" % field)
			elif not _valid_nonnegative_number(values[field]):
				errors.append("Invalid weapon upgrade modifier: %s" % field)

func _stat_value(policy: CombatBuildPolicy, stat_id: StringName, level: int, errors: PackedStringArray) -> float:
	if not policy.stat_values.has(stat_id):
		if level == 0: return float(STAT_IDENTITIES[stat_id])
		errors.append("Missing production stat policy for nonzero level: %s" % stat_id)
		return float(STAT_IDENTITIES[stat_id])
	var values = policy.stat_values[stat_id]
	if not values is Array or level >= values.size():
		errors.append("Stat policy does not define purchased level: %s/%d" % [stat_id, level])
		return float(STAT_IDENTITIES[stat_id])
	var value = values[level]
	if not _valid_nonnegative_number(value):
		errors.append("Invalid stat policy value: %s/%d" % [stat_id, level])
		return float(STAT_IDENTITIES[stat_id])
	return float(value)

func _valid_nonnegative_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0

func _failure(errors: Array) -> Dictionary:
	var packed := PackedStringArray()
	for error in errors: packed.append(str(error))
	return {"ok": false, "build": null, "errors": packed}
