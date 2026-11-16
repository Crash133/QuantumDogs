class_name PersistentProfile
extends Resource

var style_points: float = 0.0
var stat_levels: Dictionary = {}

func credit_style_points(amount: float) -> bool:
	if not is_finite(amount) or amount < 0 or not is_finite(style_points + amount): return false
	style_points += amount
	return true

func get_stat_levels() -> Dictionary:
	return stat_levels.duplicate(true)

func try_purchase(stat_id: StringName, catalog: ProgressionCatalog) -> Dictionary:
	var level = stat_levels.get(stat_id, 0)
	var reply := {"success": false, "cost": 0.0, "level": level, "balance": style_points, "error": "Invalid stat/profile"}
	var stat := catalog.get_stat(stat_id)
	if stat == null or not stat.is_valid() or not level is int or level < 0 or level >= stat.max_level or not is_finite(style_points) or style_points < 0: return reply
	var cost := stat.cost_by_level[level]
	reply.cost = cost
	if style_points < cost:
		reply.error = "Insufficient Style Points"
		return reply
	style_points -= cost
	stat_levels[stat_id] = level + 1
	return {"success": true, "cost": cost, "level": level + 1, "balance": style_points, "error": ""}
