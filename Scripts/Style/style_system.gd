extends Node
class_name StyleSystem

signal style_changed(rating: float, rank_index: int, normalized_rating: float)
signal action_tally_changed(entries: Array)
signal style_points_awarded(award: StyleAward)
signal damage_penalty_applied(rating: float, rank_index: int)

@export var event_bus_path: NodePath = NodePath("/root/CombatEvents")
@export var actions: Array[StyleActionDefinition] = []
@export var tuning: StyleTuning

var _state := StyleState.new()
var _event_bus: Node
var _actions_by_event: Dictionary = {}
var _connections: Array[Dictionary] = []
var _configured := false

func _ready() -> void:
	if tuning == null or actions.is_empty():
		return
	var event_bus := get_node_or_null(event_bus_path)
	if event_bus != null:
		configure(event_bus, actions, tuning)

func configure(event_bus: Node, action_definitions: Array[StyleActionDefinition], style_tuning: StyleTuning) -> void:
	_disconnect_events()
	_event_bus = event_bus
	tuning = style_tuning
	actions = action_definitions.duplicate()
	_state = StyleState.new()
	_actions_by_event.clear()
	if _event_bus == null or tuning == null:
		_configured = false
		return
	for action in actions:
		if action == null or action.id.is_empty() or action.event_name.is_empty():
			continue
		var event_actions: Array = _actions_by_event.get(action.event_name, [])
		var already_configured := false
		for existing in event_actions:
			if existing.id == action.id:
				already_configured = true
				break
		if not already_configured:
			event_actions.append(action)
			_actions_by_event[action.event_name] = event_actions
	_connect_combat_events()
	_configured = true
	_publish_state()
	action_tally_changed.emit(_get_ordered_action_counts())

func get_normalized_rating() -> float:
	if tuning == null:
		return 0.0
	return _state.get_normalized_rating(tuning)

func _physics_process(_delta: float) -> void:
	var _probe := ScriptCostProbe.start()
	_physics_process_body(_delta)
	ScriptCostProbe.stop(&"style.system", _probe)

func _physics_process_body(_delta: float) -> void:
	if not _configured:
		return
	var old_rating := _state.rating
	var old_rank := _state.get_rank_index(tuning)
	var award := _state.advance_tick(tuning)
	if not is_equal_approx(old_rating, _state.rating) or old_rank != _state.get_rank_index(tuning):
		_publish_state()
	if award != null:
		action_tally_changed.emit(_get_ordered_action_counts())
		style_points_awarded.emit(award)

func _connect_combat_events() -> void:
	for event_name in _actions_by_event:
		match StringName(event_name):
			&"hit_landed": _connect_signal(&"hit_landed", _on_hit_landed)
			&"enemy_killed": _connect_signal(&"enemy_killed", _on_enemy_killed)
			&"combo_advanced": _connect_signal(&"combo_advanced", _on_combo_advanced)
			&"parried": _connect_signal(&"parried", _on_parried)
			&"executed": _connect_signal(&"executed", _on_executed)
			&"weapon_switched": _connect_signal(&"weapon_switched", _on_weapon_switched)
	if _event_bus.has_signal(&"damage_taken"):
		_connect_signal(&"damage_taken", _on_damage_taken)

func _connect_signal(event_name: StringName, callback: Callable) -> void:
	if not _event_bus.has_signal(event_name) or _event_bus.is_connected(event_name, callback):
		return
	_event_bus.connect(event_name, callback)
	_connections.append({"signal": event_name, "callback": callback})

func _disconnect_events() -> void:
	if is_instance_valid(_event_bus):
		for connection in _connections:
			var event_name: StringName = connection.signal
			var callback: Callable = connection.callback
			if _event_bus.has_signal(event_name) and _event_bus.is_connected(event_name, callback):
				_event_bus.disconnect(event_name, callback)
	_connections.clear()

func _on_hit_landed(_hit_data: Variant, _target: Object) -> void:
	_apply_event_actions(&"hit_landed")

func _on_enemy_killed(_target: Object, _hit_data: Variant) -> void:
	_apply_event_actions(&"enemy_killed")

func _on_combo_advanced(_weapon_id: StringName, _node_id: StringName, _depth: int) -> void:
	_apply_event_actions(&"combo_advanced")

func _on_parried(_parrier: Object, _attacker: Object) -> void:
	_apply_event_actions(&"parried")

func _on_executed(_target: Object) -> void:
	_apply_event_actions(&"executed")

func _on_weapon_switched(_previous: StringName, _current: StringName) -> void:
	_apply_event_actions(&"weapon_switched")

func _on_damage_taken(_amount: float, _source: Object) -> void:
	var previous_rating := _state.rating
	var award := _state.apply_damage(tuning)
	if _state.rating < previous_rating:
		damage_penalty_applied.emit(_state.rating, _state.get_rank_index(tuning))
	_publish_state()
	action_tally_changed.emit(_get_ordered_action_counts())
	if award != null:
		style_points_awarded.emit(award)

func _apply_event_actions(event_name: StringName) -> void:
	var event_actions: Array = _actions_by_event.get(event_name, [])
	if event_actions.is_empty():
		return
	for action in event_actions:
		_state.add_action(action, tuning)
	_publish_state()
	action_tally_changed.emit(_get_ordered_action_counts())

func _get_ordered_action_counts() -> Array:
	var ordered: Array = []
	var seen_ids: Array[StringName] = []
	for action in actions:
		if action == null or seen_ids.has(action.id):
			continue
		seen_ids.append(action.id)
		for entry in _state.action_counts:
			if entry.id == action.id:
				ordered.append(entry.duplicate(true))
				break
	return ordered

func _publish_state() -> void:
	style_changed.emit(_state.rating, _state.get_rank_index(tuning), _state.get_normalized_rating(tuning))
