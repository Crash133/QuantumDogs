extends RefCounted
class_name StyleState

var rating: float = 0.0
var action_counts: Array[Dictionary] = []
var idle_ticks: int = 0
var _last_nonzero_rank_index: int = -1

func add_action(action: StyleActionDefinition, tuning: StyleTuning) -> void:
	if action == null or tuning == null:
		return
	rating = clampf(rating + action.rating_gain, 0.0, tuning.max_rating)
	idle_ticks = 0
	_update_last_nonzero_rank(tuning)
	for index in range(action_counts.size()):
		if action_counts[index].id == action.id:
			var entry: Dictionary = action_counts[index]
			entry.count = int(entry.count) + 1
			entry.base_points = float(entry.base_points) + action.style_points
			action_counts[index] = entry
			return
	action_counts.append({
		"id": action.id,
		"display_label": action.display_label,
		"count": 1,
		"base_points": action.style_points
	})

func advance_tick(tuning: StyleTuning) -> StyleAward:
	if tuning == null:
		return null
	idle_ticks += 1
	if rating > 0.0:
		rating = maxf(0.0, rating - maxf(0.0, tuning.rating_decay_per_tick))
		_update_last_nonzero_rank(tuning)
	if rating <= 0.0 and not action_counts.is_empty():
		return _pay_out(_last_nonzero_rank_index, tuning)
	if idle_ticks >= maxi(1, tuning.idle_payout_ticks):
		var rank_index := get_rank_index(tuning)
		if rank_index < 0:
			rank_index = _last_nonzero_rank_index
		return _pay_out(rank_index, tuning)
	return null

func apply_damage(tuning: StyleTuning) -> StyleAward:
	if tuning == null:
		return null
	if rating > 0.0:
		var retention := clampf(tuning.damage_retention_ratio, 0.01, 0.99)
		rating = maxf(minf(rating, 1e-300), rating * retention)
		_update_last_nonzero_rank(tuning)
	var rank_index := get_rank_index(tuning)
	if rank_index < 0:
		rank_index = _last_nonzero_rank_index
	return _pay_out(rank_index, tuning)

func get_rank_index(tuning: StyleTuning) -> int:
	if tuning == null or rating <= 0.0:
		return -1
	var rank_index := 0
	for threshold in tuning.rank_thresholds:
		if rating >= threshold:
			rank_index += 1
	return rank_index

func get_normalized_rating(tuning: StyleTuning) -> float:
	if tuning == null or tuning.max_rating <= 0.0:
		return 0.0
	return clampf(rating / tuning.max_rating, 0.0, 1.0)

func _update_last_nonzero_rank(tuning: StyleTuning) -> void:
	var rank_index := get_rank_index(tuning)
	if rank_index >= 0:
		_last_nonzero_rank_index = rank_index

func _pay_out(rank_index: int, tuning: StyleTuning) -> StyleAward:
	if action_counts.is_empty():
		idle_ticks = 0
		return null
	var safe_rank := clampi(rank_index, 0, maxi(0, tuning.rank_multipliers.size() - 1))
	var multiplier := 1.0
	if not tuning.rank_multipliers.is_empty():
		multiplier = tuning.rank_multipliers[safe_rank]
	var base_points := 0.0
	for entry in action_counts:
		base_points += float(entry.base_points)
	var award := StyleAward.new()
	award.amount = base_points * multiplier
	award.rank_index = safe_rank
	award.action_counts = action_counts
	action_counts.clear()
	idle_ticks = 0
	return award
