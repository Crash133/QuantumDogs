class_name ComboTransition
extends RefCounted

## Immutable description of one accepted attack handoff.
var from_id: StringName = &""
var to_id: StringName = &""
var outgoing_tick: int = -1
var incoming_tick: int = 0
var serial: int = 0
var blend_ticks: int = 6
var edge_id: StringName = &""
var interrupted: bool = false

func _init(
	p_from_id: StringName = &"",
	p_to_id: StringName = &"",
	p_outgoing_tick: int = -1,
	p_serial: int = 0,
	p_blend_ticks: int = 6,
	p_edge_id: StringName = &"",
	p_interrupted: bool = false
) -> void:
	from_id = p_from_id
	to_id = p_to_id
	outgoing_tick = p_outgoing_tick
	serial = p_serial
	blend_ticks = p_blend_ticks
	edge_id = p_edge_id
	interrupted = p_interrupted
