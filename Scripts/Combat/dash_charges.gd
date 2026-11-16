class_name DashCharges
extends Resource

var tuning: CombatTuning
var capacity: int = 1
var current: int = 1
var regen_ticks_left: int = 0
var iframe_ticks_left: int = 0
var _spent_this_tick: bool = false

func configure(combat_tuning: CombatTuning, extra_charges: int = 0) -> void:
	tuning = combat_tuning
	capacity = maxi(1, tuning.dash_charges_base + extra_charges)
	current = capacity
	regen_ticks_left = 0
	iframe_ticks_left = 0
	_spent_this_tick = false

func spend() -> bool:
	if current <= 0 or tuning == null:
		return false
	current -= 1
	iframe_ticks_left = tuning.dash_iframe_ticks
	_spent_this_tick = true
	if regen_ticks_left == 0:
		regen_ticks_left = tuning.dash_regen_ticks
	return true

func step() -> void:
	if _spent_this_tick:
		_spent_this_tick = false
		return
	if iframe_ticks_left > 0:
		iframe_ticks_left -= 1
	if tuning == null or current >= capacity:
		regen_ticks_left = 0
		return
	regen_ticks_left -= 1
	if regen_ticks_left <= 0:
		current += 1
		regen_ticks_left = tuning.dash_regen_ticks if current < capacity else 0

func is_invulnerable() -> bool:
	return iframe_ticks_left > 0

