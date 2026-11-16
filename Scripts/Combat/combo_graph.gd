@tool
class_name ComboGraph
extends Resource

const CURRENT_SCHEMA_VERSION: int = 1

## Zero identifies legacy resources awaiting reviewed copy migration.
@export_storage var schema_version: int = 0

@export var rest_edges: Array[ComboEdge] = []:
	set(value):
		rest_edges = value
		refresh_edge_suggestions()
@export var nodes: Array[ComboNode] = []:
	set(value):
		nodes = value
		refresh_edge_suggestions()

## Best effort: gives every edge this graph's node ids as target suggestions.
func refresh_edge_suggestions() -> void:
	var ids := PackedStringArray()
	for combo_node in nodes:
		if combo_node != null and combo_node.id != &"":
			ids.append(String(combo_node.id))
	var all_edges: Array[ComboEdge] = rest_edges.duplicate()
	for combo_node in nodes:
		if combo_node != null:
			all_edges.append_array(combo_node.edges)
	for edge in all_edges:
		if edge != null:
			edge.target_suggestions = ids

func get_node(node_id: StringName) -> ComboNode:
	for combo_node in nodes:
		if combo_node != null and combo_node.id == node_id:
			return combo_node
	return null

func first_attack() -> StringName:
	return rest_edges[0].target if not rest_edges.is_empty() and rest_edges[0] != null else &""

func validate() -> Array[String]:
	var errors: Array[String] = []
	if schema_version < 0 or schema_version > CURRENT_SCHEMA_VERSION:
		errors.append("Combo graph schema version %d is not supported" % schema_version)
	var ids: Dictionary = {}
	var edge_ids: Dictionary = {}
	for combo_node in nodes:
		if combo_node == null:
			errors.append("Graph contains a null node")
			continue
		if combo_node.id == &"" or ids.has(combo_node.id):
			errors.append("Node ids must be non-empty and unique: %s" % combo_node.id)
		ids[combo_node.id] = true
		if combo_node.duration_ticks <= 0:
			errors.append("Node %s must have a positive duration" % combo_node.id)
		if combo_node.input_window.x < 0 or combo_node.input_window.y < combo_node.input_window.x or combo_node.input_window.y > combo_node.duration_ticks:
			errors.append("Node %s has an invalid input window" % combo_node.id)
		if combo_node.switch_window.x < 0 or combo_node.switch_window.y < combo_node.switch_window.x or combo_node.switch_window.y > combo_node.duration_ticks:
			errors.append("Node %s has an invalid switch window" % combo_node.id)
		if not is_finite(combo_node.clip_start_seconds) or combo_node.clip_start_seconds < 0.0 or not is_finite(combo_node.clip_end_seconds) or combo_node.clip_end_seconds < -1.0 or (combo_node.clip_end_seconds >= 0.0 and combo_node.clip_end_seconds <= combo_node.clip_start_seconds):
			errors.append("Node %s has an invalid animation clip span" % combo_node.id)
		for spec in combo_node.hit_specs:
			if spec == null:
				continue
			for window in spec.resolved_active_windows():
				if window.x < 0 or window.y < window.x or window.y >= combo_node.duration_ticks:
					errors.append("Node %s has an invalid hit active window" % combo_node.id)
		for window in combo_node.cancel_windows:
			if window == null or window.start_tick < 0 or window.end_tick < window.start_tick or window.end_tick >= combo_node.duration_ticks:
				errors.append("Node %s has an invalid action cancel window" % combo_node.id)
	for edge_index in rest_edges.size():
		var edge: ComboEdge = rest_edges[edge_index]
		if edge == null or not ids.has(edge.target):
			errors.append("Rest edge targets a missing node")
		elif not _validate_edge(edge, null, edge_ids, errors, edge_index):
			pass
	_validate_input_edge_overlaps(rest_edges, null, errors)
	for combo_node in nodes:
		if combo_node == null:
			continue
		for edge_index in combo_node.edges.size():
			var edge: ComboEdge = combo_node.edges[edge_index]
			if edge == null or not ids.has(edge.target):
				errors.append("Node %s has an edge to a missing node" % combo_node.id)
			else:
				_validate_edge(edge, combo_node, edge_ids, errors, edge_index)
		_validate_input_edge_overlaps(combo_node.edges, combo_node, errors)
	if rest_edges.is_empty():
		errors.append("Graph has no path from Rest")
	elif _reachable_nodes(ids).size() != ids.size():
		errors.append("Graph contains nodes unreachable from Rest")
	return errors

func _validate_edge(edge: ComboEdge, owner: ComboNode, edge_ids: Dictionary, errors: Array[String], edge_index: int) -> bool:
	if edge.input not in [&"light", &"heavy"]:
		errors.append("Combo edge input must be light or heavy")
	if not edge.id.is_empty():
		if edge_ids.has(edge.id):
			var owner_label := "Rest" if owner == null else "Node %s" % owner.id
			errors.append("Combo edge ids must be unique: %s in %s edge[%d]" % [edge.id, owner_label, edge_index])
		edge_ids[edge.id] = true
	if owner == null:
		if edge.transition_mode != ComboEdge.TransitionMode.IMMEDIATE:
			errors.append("Rest edges must start attacks immediately")
		return true
	var window := edge.input_window if edge.input_window.x >= 0 and edge.input_window.y >= 0 else owner.input_window
	if window.x < 0 or window.y < window.x or window.y >= owner.duration_ticks:
			errors.append("Node %s edge[%d] (%s) has an invalid input window" % [owner.id, edge_index, edge.id if not edge.id.is_empty() else "unnamed"])
	if edge.transition_mode == ComboEdge.TransitionMode.AT_TICK:
		if edge.id.is_empty():
			errors.append("Node %s queued edge requires a stable non-empty ID" % owner.id)
		if edge.transition_tick < 0 or edge.transition_tick >= owner.duration_ticks or edge.transition_tick < window.y:
			errors.append("Node %s has an invalid queued transition tick" % owner.id)
	elif edge.transition_mode != ComboEdge.TransitionMode.IMMEDIATE:
		errors.append("Node %s has an unsupported transition mode" % owner.id)
	return true

func _validate_input_edge_overlaps(edges: Array[ComboEdge], owner: ComboNode, errors: Array[String]) -> void:
	for first_index in range(edges.size()):
		var first := edges[first_index]
		if first == null:
			continue
		var first_window := first.input_window if owner != null and first.input_window.x >= 0 and first.input_window.y >= 0 else owner.input_window if owner != null else Vector2i.ZERO
		if first_window.x < 0 or first_window.y < first_window.x:
			continue
		for second_index in range(first_index + 1, edges.size()):
			var second := edges[second_index]
			if second == null or second.input != first.input:
				continue
			var second_window := second.input_window if owner != null and second.input_window.x >= 0 and second.input_window.y >= 0 else owner.input_window if owner != null else Vector2i.ZERO
			if second_window.x < 0 or second_window.y < second_window.x:
				continue
			if maxi(first_window.x, second_window.x) <= mini(first_window.y, second_window.y):
				errors.append("%s has overlapping %s input edges in ticks %d-%d and %d-%d" % ["Rest" if owner == null else "Node %s" % owner.id, first.input, first_window.x, first_window.y, second_window.x, second_window.y])

func _reachable_nodes(ids: Dictionary) -> Dictionary:
	var reachable: Dictionary = {}
	var pending: Array[StringName] = []
	for edge in rest_edges:
		if edge != null and ids.has(edge.target):
			pending.append(edge.target)
	while not pending.is_empty():
		var current: StringName = pending.pop_back()
		if reachable.has(current):
			continue
		reachable[current] = true
		var combo_node := get_node(current)
		if combo_node == null:
			continue
		for edge in combo_node.edges:
			if edge != null and ids.has(edge.target) and not reachable.has(edge.target):
				pending.append(edge.target)
	return reachable

