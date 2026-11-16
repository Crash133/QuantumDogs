class_name ComboRunner
extends RefCounted

signal advanced(weapon_id: StringName, node_id: StringName, depth: int)
signal weapon_changed(previous: StringName, current: StringName)
signal transition_started(transition: ComboTransition)
signal cancelled

var weapon: WeaponData
var current_node: ComboNode
var node_tick: int = 0
var depth: int = 0
var attack_serial: int = 0
var _entry_tick_pending: bool = false
var _transition_consumed_this_tick: bool = false
var _pending_edge_id: StringName = &""
var _pending_target: StringName = &""
var _pending_airborne: bool = false

func set_weapon(new_weapon: WeaponData) -> void:
	if new_weapon == null:
		return
	var previous := weapon.id if weapon != null else &""
	_clear_pending()
	weapon = new_weapon
	current_node = null
	node_tick = 0
	depth = 0
	_entry_tick_pending = false
	weapon_changed.emit(previous, weapon.id)

## Advance the authored gameplay clock. An accepted destination is held at tick
## zero through this call so downstream hit evaluation observes its entry tick.
func step() -> void:
	_transition_consumed_this_tick = false
	if current_node == null:
		return
	if _entry_tick_pending:
		_entry_tick_pending = false
		return
	if not _pending_edge_id.is_empty() and node_tick >= _pending_transition_tick():
		_dispatch_pending()
		_transition_consumed_this_tick = false
		return
	node_tick += 1
	if not _pending_edge_id.is_empty() and node_tick >= _pending_transition_tick():
		_dispatch_pending()
		_transition_consumed_this_tick = false
		return
	if current_node != null and node_tick >= current_node.duration_ticks:
		current_node = null
		node_tick = 0
		depth = 0
		_clear_pending()

func press(action: StringName, airborne: bool = false) -> bool:
	if not can_press(action, airborne):
		return false
	if not _pending_edge_id.is_empty():
		return false
	if current_node == null:
		var rest_edge := _find_edge(weapon.graph.rest_edges, action)
		if rest_edge == null:
			return false
		return _start_node(rest_edge.target, airborne, rest_edge)
	var edge := _find_edge(current_node.edges, action, current_node, node_tick)
	if edge == null or not _edge_accepts_at(edge, current_node, node_tick):
		return false
	var destination := weapon.graph.get_node(edge.target)
	if destination == null or (airborne and not destination.airborne_ok):
		return false
	if edge.transition_mode == ComboEdge.TransitionMode.IMMEDIATE:
		return _start_node(edge.target, airborne, edge)
	if edge.transition_mode != ComboEdge.TransitionMode.AT_TICK or edge.id.is_empty():
		return false
	if edge.transition_tick < node_tick or edge.transition_tick >= current_node.duration_ticks:
		return false
	_pending_edge_id = edge.id
	_pending_target = edge.target
	_pending_airborne = airborne
	if edge.transition_tick <= node_tick:
		return _dispatch_pending()
	return true

## Read-only acceptance query used by simultaneous action arbitration.
func can_press(action: StringName, airborne: bool = false) -> bool:
	if weapon == null or weapon.graph == null or action not in [&"light", &"heavy"] or _transition_consumed_this_tick or not _pending_edge_id.is_empty():
		return false
	var edge := _find_edge(weapon.graph.rest_edges, action) if current_node == null else _find_edge(current_node.edges, action, current_node, node_tick)
	if edge == null:
		return false
	if current_node != null:
		if not _edge_accepts_at(edge, current_node, node_tick):
			return false
		if edge.transition_mode == ComboEdge.TransitionMode.AT_TICK and (edge.id.is_empty() or edge.transition_tick < node_tick or edge.transition_tick >= current_node.duration_ticks):
			return false
	var destination := weapon.graph.get_node(edge.target)
	return destination != null and not (airborne and not destination.airborne_ok)

func switch_weapon(new_weapon: WeaponData) -> bool:
	if new_weapon == null:
		return false
	if current_node == null:
		set_weapon(new_weapon)
		return true
	if not can_cancel(&"switch"):
		return false
	set_weapon(new_weapon)
	return true

## Returns whether a voluntary action may interrupt this attack on node_tick.
func can_cancel(action: StringName) -> bool:
	if current_node == null:
		return true
	var action_id := _cancel_action_id(action)
	if action_id < 0:
		return false
	var legacy_graph := weapon != null and weapon.graph != null and weapon.graph.schema_version == 0
	var has_explicit_action_window := false
	for window in current_node.cancel_windows:
		if window != null and window.action == action_id:
			has_explicit_action_window = true
			if window.contains(node_tick):
				return true
	if legacy_graph and not has_explicit_action_window:
		if action_id in [ComboCancelWindow.Action.DODGE, ComboCancelWindow.Action.EXECUTE]:
			return true
		if action_id == ComboCancelWindow.Action.SWITCH:
			return node_tick >= current_node.switch_window.x and node_tick <= current_node.switch_window.y
	return false

func cancel() -> void:
	_clear_pending()
	current_node = null
	node_tick = 0
	depth = 0
	_entry_tick_pending = false
	cancelled.emit()

func _edge_accepts_at(edge: ComboEdge, node: ComboNode, tick: int) -> bool:
	var window := edge.input_window
	if window.x < 0 or window.y < 0:
		window = node.input_window
	return tick >= window.x and tick <= window.y

func _start_node(node_id: StringName, airborne: bool, edge: ComboEdge) -> bool:
	var next_node := weapon.graph.get_node(node_id)
	if next_node == null or (airborne and not next_node.airborne_ok):
		return false
	var previous := current_node
	var outgoing_tick := node_tick if previous != null else -1
	current_node = next_node
	node_tick = 0
	depth = 1 if previous == null else depth + 1
	attack_serial += 1
	_entry_tick_pending = true
	_transition_consumed_this_tick = true
	_clear_pending()
	var transition := ComboTransition.new(
		previous.id if previous != null else &"",
		next_node.id,
		outgoing_tick,
		attack_serial,
		edge.blend_ticks if edge != null else 0,
		edge.id if edge != null else &"",
		false
	)
	transition_started.emit(transition)
	advanced.emit(weapon.id, current_node.id, depth)
	return true

func _dispatch_pending() -> bool:
	var edge := _find_edge_by_id(current_node.edges, _pending_edge_id) if current_node != null else null
	var target := weapon.graph.get_node(_pending_target) if weapon != null and weapon.graph != null else null
	var airborne := _pending_airborne
	var valid := edge != null and target != null and edge.target == _pending_target and not (airborne and not target.airborne_ok)
	if not valid:
		_clear_pending()
		return false
	return _start_node(_pending_target, airborne, edge)

func _pending_transition_tick() -> int:
	var edge := _find_edge_by_id(current_node.edges, _pending_edge_id) if current_node != null else null
	return edge.transition_tick if edge != null else 2147483647

func _clear_pending() -> void:
	_pending_edge_id = &""
	_pending_target = &""
	_pending_airborne = false

func _cancel_action_id(action: StringName) -> int:
	match action:
		&"dodge", &"dash": return ComboCancelWindow.Action.DODGE
		&"block", &"parry", &"block_parry": return ComboCancelWindow.Action.BLOCK_PARRY
		&"switch": return ComboCancelWindow.Action.SWITCH
		&"jump": return ComboCancelWindow.Action.JUMP
		&"execute": return ComboCancelWindow.Action.EXECUTE
	return -1

func _find_edge(edges: Array[ComboEdge], action: StringName, node: ComboNode = null, tick: int = -1) -> ComboEdge:
	for edge in edges:
		if edge == null or edge.input != action:
			continue
		if node == null or _edge_accepts_at(edge, node, tick):
			return edge
	return null

func _find_edge_by_id(edges: Array[ComboEdge], edge_id: StringName) -> ComboEdge:
	for edge in edges:
		if edge != null and edge.id == edge_id:
			return edge
	return null
