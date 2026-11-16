@tool
class_name ComboGraphCanvas
extends GraphEdit

signal attack_selected(node_id: StringName)
signal graph_changed

var graph: ComboGraph
var layout: ComboGraphLayout
var _commands := ComboEditCommands.new()
var _history: Object
var _editor: EditorInterface
var _id_to_control: Dictionary = {}

func configure(editor: EditorInterface, history: Object) -> void:
	_editor = editor
	_history = history
	if not connection_request.is_connected(_on_connection_request):
		connection_request.connect(_on_connection_request)
	if not disconnection_request.is_connected(_on_disconnection_request):
		disconnection_request.connect(_on_disconnection_request)
	if not node_selected.is_connected(_on_node_selected):
		node_selected.connect(_on_node_selected)
	if not delete_nodes_request.is_connected(_on_delete_nodes_request):
		delete_nodes_request.connect(_on_delete_nodes_request)
	if not end_node_move.is_connected(_save_layout):
		end_node_move.connect(_save_layout)

func show_graph(value: ComboGraph, graph_layout: ComboGraphLayout = null) -> void:
	graph = value
	layout = graph_layout
	_refresh()

func add_attack(display_name: String, animation: StringName) -> ComboNode:
	if graph == null:
		return null
	var node := ComboNode.new()
	var stem := _slug(display_name)
	node.id = StringName("%s_%d" % [stem, graph.nodes.size() + 1])
	while graph.get_node(node.id) != null:
		node.id = StringName("%s_%d" % [stem, randi_range(2, 9999)])
	node.display_name = display_name
	node.animation = animation
	node.input_window = Vector2i(0, node.duration_ticks - 1)
	if _commands.add_node(_history, graph, node):
		if layout != null:
			layout.node_positions[node.id] = scroll_offset + size * 0.5
		_refresh()
		return node
	return null

func duplicate_attack(node_id: StringName) -> ComboNode:
	if graph == null:
		return null
	var source := graph.get_node(node_id)
	if source == null:
		return null
	var duplicate := source.duplicate(true) as ComboNode
	if duplicate == null:
		return null
	duplicate.id = StringName("%s_copy" % source.id)
	var suffix := 2
	while graph.get_node(duplicate.id) != null:
		duplicate.id = StringName("%s_copy_%d" % [source.id, suffix])
		suffix += 1
	duplicate.display_name = "%s Copy" % source.display_name
	for index in duplicate.edges.size():
		var edge := duplicate.edges[index]
		if edge != null:
			edge.id = StringName("%s_%s_%s_%d" % [duplicate.id, edge.input, edge.target, index + 1])
	if _commands.add_node(_history, graph, duplicate):
		if layout != null:
			layout.node_positions[duplicate.id] = layout.node_positions.get(source.id, scroll_offset + size * 0.5) + Vector2(80, 80)
		_refresh()
		return duplicate
	return null

func _refresh() -> void:
	clear_connections()
	for child in get_children():
		if child is GraphNode:
			remove_child(child)
			child.free()
	_id_to_control.clear()
	if graph == null:
		return
	var rest := _make_graph_node(&"__rest", "Rest", true)
	add_child(rest)
	var rest_position: Vector2 = layout.node_positions.get(&"__rest", Vector2(40, 120)) if layout != null else Vector2(40, 120)
	rest.position_offset = rest_position
	for combo_node in graph.nodes:
		if combo_node == null:
			continue
		var control := _make_graph_node(combo_node.id, combo_node.display_name, false)
		add_child(control)
		control.position_offset = layout.node_positions.get(combo_node.id, Vector2(300 + _id_to_control.size() * 230, 120)) if layout != null else Vector2(300 + _id_to_control.size() * 230, 120)
	if layout != null:
		scroll_offset = layout.scroll_offset
		zoom = layout.zoom
	for edge in graph.rest_edges:
		if edge != null:
			connect_node(&"__rest", _port(edge.input), StringName(edge.target), 0, true)
	for combo_node in graph.nodes:
		if combo_node == null:
			continue
		for edge in combo_node.edges:
			if edge != null:
				connect_node(StringName(combo_node.id), _port(edge.input), StringName(edge.target), 0, true)

func _make_graph_node(node_id: StringName, label: String, is_rest: bool) -> GraphNode:
	var control := GraphNode.new()
	control.name = String(node_id)
	control.title = label
	control.set_meta("combo_node_id", node_id)
	for index in 2:
		var row := HBoxContainer.new()
		var text := Label.new()
		text.text = ("Light" if index == 0 else "Heavy") + (" input" if is_rest else "")
		row.add_child(text)
		control.add_child(row)
		control.set_slot(index, not is_rest, 1, Color(0.48, 0.78, 1.0), true, 1, Color(1.0, 0.58, 0.36))
	_id_to_control[node_id] = control
	return control

func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, _to_port: int) -> void:
	if graph == null or not _id_to_control.has(from_node) or not _id_to_control.has(to_node):
		return
	var input := &"light" if from_port == 0 else &"heavy"
	var edge := ComboEdge.new()
	edge.id = StringName("%s_%s_%s" % ["rest" if from_node == &"__rest" else from_node, input, to_node])
	var sequence := 1
	while _edge_id_exists(edge.id):
		sequence += 1
		edge.id = StringName("%s_%s_%s_%d" % ["rest" if from_node == &"__rest" else from_node, input, to_node, sequence])
	edge.input = input
	edge.target = to_node
	var owner_id := &"" if from_node == &"__rest" else from_node
	if _commands.add_edge(_history, graph, owner_id, edge):
		_refresh()
		graph_changed.emit()

func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, _to_port: int) -> void:
	if graph == null:
		return
	var owner: Resource = graph if from_node == &"__rest" else graph.get_node(from_node)
	if owner == null:
		return
	var property: StringName = &"rest_edges" if from_node == &"__rest" else &"edges"
	var values: Array[ComboEdge] = owner.get(property).duplicate()
	var input := &"light" if from_port == 0 else &"heavy"
	for edge in values.duplicate():
		if edge != null and edge.input == input and edge.target == to_node:
			values.erase(edge)
			break
	_set_array(owner, property, values)

func _on_delete_nodes_request(nodes: Array[StringName]) -> void:
	if graph == null:
		return
	for node_id in nodes:
		if node_id != &"__rest":
			_commands.delete_node(_history, graph, node_id)
	_refresh()
	graph_changed.emit()

func _on_node_selected(node: Node) -> void:
	if node.has_meta("combo_node_id"):
		attack_selected.emit(node.get_meta("combo_node_id"))

func select_attack(node_id: StringName) -> void:
	for child in get_children():
		if child is GraphNode and child.get_meta("combo_node_id", &"") == node_id:
			set_selected(child)
			_on_node_selected(child)
			return

func _save_layout() -> void:
	if layout == null:
		return
	for node in get_children():
		if node is GraphNode and node.has_meta("combo_node_id"):
			layout.node_positions[node.get_meta("combo_node_id")] = node.position_offset
	layout.scroll_offset = scroll_offset
	layout.zoom = zoom

func _set_array(owner: Resource, property: StringName, values: Array[ComboEdge]) -> void:
	if _history == null:
		return
	var before: Array[ComboEdge] = owner.get(property).duplicate()
	_history.create_action("Disconnect combo attacks")
	_history.add_do_property(owner, property, values)
	_history.add_undo_property(owner, property, before)
	_history.commit_action()
	_refresh()
	graph_changed.emit()

func _edge_id_exists(edge_id: StringName) -> bool:
	for edge in graph.rest_edges:
		if edge != null and edge.id == edge_id:
			return true
	for node in graph.nodes:
		if node == null:
			continue
		for edge in node.edges:
			if edge != null and edge.id == edge_id:
				return true
	return false

func _port(input: StringName) -> int:
	return 0 if input == &"light" else 1

func _slug(value: String) -> String:
	var result := value.to_lower().strip_edges().replace(" ", "_")
	var valid := "abcdefghijklmnopqrstuvwxyz0123456789_"
	var filtered := ""
	for character in result:
		if valid.contains(character):
			filtered += character
	return filtered if not filtered.is_empty() else "attack"
