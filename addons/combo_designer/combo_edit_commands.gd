@tool
class_name ComboEditCommands
extends RefCounted

## Resource mutations are recorded in the editor's undo history. Layout-only
## movement stays outside this command object and never dirties combat data.

func set_resource_property(history: Object, resource: Resource, property: StringName, value: Variant) -> bool:
	if history == null or resource == null or not _has_property(resource, property):
		return false
	var previous: Variant = resource.get(property)
	if previous == value:
		return false
	history.create_action("Set %s" % String(property))
	history.add_do_property(resource, property, value)
	history.add_undo_property(resource, property, previous)
	history.commit_action()
	return true

func add_node(history: Object, graph: ComboGraph, node: ComboNode) -> bool:
	if history == null or graph == null or node == null or node.id == &"" or graph.get_node(node.id) != null:
		return false
	var before := graph.nodes.duplicate()
	var after := before.duplicate()
	after.append(node)
	return _set_resource_array(history, graph, &"nodes", before, after, "Add combo attack")

func add_edge(history: Object, graph: ComboGraph, owner_id: StringName, edge: ComboEdge) -> bool:
	if history == null or graph == null or edge == null or edge.id == &"" or edge.target == &"" or graph.get_node(edge.target) == null:
		return false
	var owner: Resource = graph.get_node(owner_id) if owner_id != &"" else graph
	if owner == null:
		return false
	var property: StringName = &"edges" if owner_id != &"" else &"rest_edges"
	var before: Array = owner.get(property).duplicate()
	for existing in before:
		if existing != null and existing.id == edge.id:
			return false
	var after: Array = before.duplicate()
	after.append(edge)
	return _set_resource_array(history, owner, property, before, after, "Connect combo attack")

func delete_node(history: Object, graph: ComboGraph, node_id: StringName) -> bool:
	if history == null or graph == null:
		return false
	var node := graph.get_node(node_id)
	if node == null:
		return false
	var before_nodes := graph.nodes.duplicate()
	var after_nodes := before_nodes.duplicate()
	after_nodes.erase(node)
	history.create_action("Delete combo attack")
	history.add_do_property(graph, &"nodes", after_nodes)
	history.add_undo_property(graph, &"nodes", before_nodes)
	var owners: Array[Resource] = [graph]
	owners.append_array(before_nodes)
	for owner: Resource in owners:
		var property: StringName = &"rest_edges" if owner is ComboGraph else &"edges"
		var before: Array[ComboEdge] = owner.get(property).duplicate()
		var after: Array[ComboEdge] = []
		for edge in before:
			if edge == null or edge.target != node_id:
				after.append(edge)
		if before.size() != after.size():
			history.add_do_property(owner, property, after)
			history.add_undo_property(owner, property, before)
	history.commit_action()
	return true

func _set_resource_array(history: Object, resource: Resource, property: StringName, before: Array, after: Array, label: String) -> bool:
	history.create_action(label)
	history.add_do_property(resource, property, after)
	history.add_undo_property(resource, property, before)
	history.commit_action()
	return true

func _has_property(object: Object, property: StringName) -> bool:
	for info in object.get_property_list():
		if info.name == property:
			return true
	return false
