class_name ScriptCostProbe
extends RefCounted

## Opt-in script profiler for the per-frame hot paths. Off by default: every probe is one
## boolean check. A profiling harness sets `enabled = true`, runs, then reads `report()`.
##
##   var t := ScriptCostProbe.start()
##   ... work ...
##   ScriptCostProbe.stop(&"enemy.physics", t)

static var enabled: bool = false
static var _usec: Dictionary = {}
static var _calls: Dictionary = {}
static var _worst: Dictionary = {}

static func start() -> int:
	return Time.get_ticks_usec() if enabled else 0

static func stop(label: StringName, started: int) -> void:
	if not enabled:
		return
	var elapsed := Time.get_ticks_usec() - started
	_usec[label] = int(_usec.get(label, 0)) + elapsed
	_worst[label] = maxi(int(_worst.get(label, 0)), elapsed)
	_calls[label] = int(_calls.get(label, 0)) + 1

static func reset() -> void:
	_usec.clear()
	_calls.clear()
	_worst.clear()

## Rows of [label, total_ms, calls, ms_per_call, worst_single_call_ms], most expensive first.
static func report() -> Array:
	var rows: Array = []
	for label in _usec:
		var total_ms := float(_usec[label]) / 1000.0
		var calls := int(_calls[label])
		rows.append([label, total_ms, calls, total_ms / maxf(1.0, float(calls)), float(_worst[label]) / 1000.0])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	return rows
