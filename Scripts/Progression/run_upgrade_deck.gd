class_name RunUpgradeDeck
extends RefCounted

var _eligible: Dictionary = {}
var _pending: Dictionary = {}
var _selected: Dictionary = {}
var _weapons: Array[StringName] = []

func add_weapon(weapon_id: StringName, catalog: ProgressionCatalog) -> void:
	if not _weapons.has(weapon_id): _weapons.append(weapon_id)
	for card in catalog.weapon_upgrades:
		if card.level == 1 and card.eligible_weapon_ids.has(weapon_id) and not _selected.has(card.upgrade_id) and not _pending.has(card.upgrade_id):
			_eligible[card.upgrade_id] = card

func draw_offer(count: int, seed: int) -> Array[WeaponUpgradeDefinition]:
	if _pending.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var ids := _eligible.keys()
		for i in range(mini(maxi(count, 0), ids.size())):
			var index := rng.randi_range(0, ids.size() - 1)
			var id = ids.pop_at(index)
			_pending[id] = _eligible[id]
			_eligible.erase(id)
	var result: Array[WeaponUpgradeDefinition] = []
	result.assign(_pending.values())
	return result

func resolve_offer(selected_ids: Array[StringName], catalog: ProgressionCatalog) -> bool:
	var seen := {}
	for id in selected_ids:
		if seen.has(id) or not _pending.has(id): return false
		seen[id] = true
	for id in _pending:
		if seen.has(id): _selected[id] = _pending[id]
		else: _eligible[id] = _pending[id]
	_pending.clear()
	for card in catalog.weapon_upgrades:
		if card.level > 1 and _selected.has(card.prerequisite_upgrade_id) and not _selected.has(card.upgrade_id):
			for weapon in _weapons:
				if card.eligible_weapon_ids.has(weapon): _eligible[card.upgrade_id] = card
	return true

func selected_cards() -> Array:
	return _selected.values().map(func(card): return card.duplicate(true))

## Checkpoint snapshot (ids only; cards are re-read from the catalog on restore).
func to_checkpoint() -> Dictionary:
	return {"weapons": _weapons.duplicate(), "eligible": _eligible.keys(), "pending": _pending.keys(), "selected": _selected.keys()}

static func from_checkpoint(data: Dictionary, catalog: ProgressionCatalog) -> RunUpgradeDeck:
	var deck := RunUpgradeDeck.new()
	var cards := {}
	for card in catalog.weapon_upgrades:
		if card != null: cards[card.upgrade_id] = card
	for weapon in data.get("weapons", []): deck._weapons.append(StringName(weapon))
	for pair in [["eligible", deck._eligible], ["pending", deck._pending], ["selected", deck._selected]]:
		for id in data.get(pair[0], []):
			if not cards.has(StringName(id)): return null
			pair[1][StringName(id)] = cards[StringName(id)]
	return deck
