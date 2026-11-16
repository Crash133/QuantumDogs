class_name AirControl
extends RefCounted

## Player gravity suspension: one hover per airtime (from a suspends_gravity
## node) plus refreshable holds (Revolver, follow-ups). Fixed ticks.

var tuning: CombatTuning
var hover_ticks_left: int = 0
var hover_available: bool = true
var hold_ticks_left: int = 0
var _hover_started_this_tick: bool = false
var _hold_started_this_tick: bool = false

func begin_tick() -> void:
	_hover_started_this_tick = false
	_hold_started_this_tick = false

## A timer started this tick keeps its full duration including this tick.
func step() -> void:
	if hover_ticks_left > 0 and not _hover_started_this_tick:
		hover_ticks_left -= 1
	if hold_ticks_left > 0 and not _hold_started_this_tick:
		hold_ticks_left -= 1

func try_hover(node: ComboNode, airborne: bool) -> void:
	if airborne and hover_available and node != null and node.suspends_gravity:
		hover_available = false
		hover_ticks_left = tuning.air_hover_ticks
		_hover_started_this_tick = true

func hold(ticks: int) -> void:
	hold_ticks_left = maxi(hold_ticks_left, ticks)
	_hold_started_this_tick = ticks > 0

func suspends_gravity(airborne: bool) -> bool:
	return airborne and (hover_ticks_left > 0 or hold_ticks_left > 0)

func clear() -> void:
	hover_ticks_left = 0
	hold_ticks_left = 0

## Landing: the hover becomes available again.
func reset() -> void:
	hover_available = true
	clear()
