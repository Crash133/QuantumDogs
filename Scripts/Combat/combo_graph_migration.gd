class_name ComboGraphMigration
extends RefCounted

## Produce a deep copy with explicit edge identity and legacy timing policy.
## The source graph and every nested authored Resource are left untouched.
static func migrate_copy(source: ComboGraph) -> Dictionary:
	var result := {"graph": null, "changes": PackedStringArray(), "errors": PackedStringArray()}
	if source == null:
		result.errors.append("Cannot migrate a null ComboGraph")
		return result
	var graph := source.duplicate(true) as ComboGraph
	if graph == null:
		result.errors.append("ComboGraph deep duplication failed")
		return result
	var changes: PackedStringArray = result.changes
	var migrating_legacy := graph.schema_version == 0
	for node in graph.nodes:
		if node == null:
			continue
		var last_tick := maxi(0, node.duration_ticks - 1)
		var normalized_input := Vector2i(clampi(node.input_window.x, 0, last_tick), clampi(node.input_window.y, 0, last_tick))
		if normalized_input != node.input_window:
			changes.append("Node %s: clamped legacy input window %s to %s (duration is %d ticks)" % [node.id, node.input_window, normalized_input, node.duration_ticks])
			node.input_window = normalized_input
		var normalized_switch := Vector2i(clampi(node.switch_window.x, 0, last_tick), clampi(node.switch_window.y, 0, last_tick))
		if normalized_switch != node.switch_window:
			changes.append("Node %s: clamped legacy switch window %s to %s (duration is %d ticks)" % [node.id, node.switch_window, normalized_switch, node.duration_ticks])
			node.switch_window = normalized_switch
		if migrating_legacy and node.switch_window.x >= 0 and node.switch_window.y >= node.switch_window.x and not _has_cancel(node, ComboCancelWindow.Action.SWITCH):
			var switch_window := ComboCancelWindow.new()
			switch_window.action = ComboCancelWindow.Action.SWITCH
			switch_window.start_tick = node.switch_window.x
			switch_window.end_tick = node.switch_window.y
			node.cancel_windows.append(switch_window)
			changes.append("Node %s: converted legacy switch window %s to a SWITCH cancel" % [node.id, node.switch_window])
		if migrating_legacy:
			for action: int in [ComboCancelWindow.Action.DODGE, ComboCancelWindow.Action.EXECUTE]:
				if _has_cancel(node, action):
					continue
				var implicit_window := ComboCancelWindow.new()
				implicit_window.action = action
				implicit_window.start_tick = 0
				implicit_window.end_tick = last_tick
				node.cancel_windows.append(implicit_window)
				changes.append("Node %s: made legacy always-available %s cancellation explicit for ticks 0-%d" % [node.id, ComboCancelWindow.Action.keys()[action].to_lower(), last_tick])
		for spec_index in node.hit_specs.size():
			var spec := node.hit_specs[spec_index]
			if spec == null:
				continue
			if spec.active_windows.is_empty():
				spec.active_windows.append(spec.active_ticks)
				changes.append("Node %s hit spec %d: copied legacy active_ticks %s into active_windows" % [node.id, spec_index, spec.active_ticks])
			if migrating_legacy and not spec.survive_transition:
				spec.survive_transition = true
				changes.append("Node %s hit spec %d: preserved legacy outgoing linger trails across attack transitions" % [node.id, spec_index])
			var trail_policy := "preserve baked potency" if spec.survive_transition else "discard on handoff"
			changes.append("Node %s hit spec %d: outgoing linger trail policy is %s" % [node.id, spec_index, trail_policy])
		var edge_index := 0
		for edge in node.edges:
			if edge == null:
				edge_index += 1
				continue
			if edge.id.is_empty():
				edge.id = StringName("%s_%s_%s_%d" % [node.id, edge.input, edge.target, edge_index])
				changes.append("Node %s edge %d: assigned stable id %s" % [node.id, edge_index, edge.id])
			if edge.input_window.x < 0 or edge.input_window.y < 0:
				edge.input_window = node.input_window
				changes.append("Node %s edge %s: copied legacy input window %s" % [node.id, edge.id, edge.input_window])
			var normalized_edge_window := Vector2i(clampi(edge.input_window.x, 0, last_tick), clampi(edge.input_window.y, 0, last_tick))
			if normalized_edge_window != edge.input_window:
				changes.append("Node %s edge %s: clamped input window %s to %s" % [node.id, edge.id, edge.input_window, normalized_edge_window])
				edge.input_window = normalized_edge_window
			if edge.transition_mode == ComboEdge.TransitionMode.AT_TICK and (edge.transition_tick < edge.input_window.y or edge.transition_tick > last_tick):
				var normalized_transition := clampi(edge.transition_tick, edge.input_window.y, last_tick)
				changes.append("Node %s edge %s: clamped queued transition tick %d to %d" % [node.id, edge.id, edge.transition_tick, normalized_transition])
				edge.transition_tick = normalized_transition
			edge_index += 1
	var rest_index := 0
	for edge in graph.rest_edges:
		if edge != null and edge.id.is_empty():
			edge.id = StringName("rest_%s_%d" % [edge.input, rest_index])
			changes.append("Rest edge %d: assigned stable id %s" % [rest_index, edge.id])
		rest_index += 1
	if migrating_legacy:
		graph.schema_version = ComboGraph.CURRENT_SCHEMA_VERSION
		changes.append("Graph: migrated schema version 0 to %d" % graph.schema_version)
	var errors: Array[String] = graph.validate()
	for error in errors:
		result.errors.append(error)
	result.graph = graph
	return result

static func _has_cancel(node: ComboNode, action: int) -> bool:
	for window in node.cancel_windows:
		if window != null and window.action == action:
			return true
	return false
