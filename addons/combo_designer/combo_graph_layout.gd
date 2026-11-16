@tool
class_name ComboGraphLayout
extends Resource

## Per-graph canvas state, stored beside the graph as <graph>.layout.tres.
@export var graph_key: String = ""
@export var node_positions: Dictionary[StringName, Vector2] = {}
@export var scroll_offset: Vector2 = Vector2.ZERO
@export_range(0.25, 2.0, 0.05) var zoom: float = 1.0
