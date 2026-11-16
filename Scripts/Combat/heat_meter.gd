class_name HeatMeter
extends Resource

signal value_changed(value: float, maximum: float)
signal staggered(duration_ticks: int)
signal stagger_ended

var tuning: CombatTuning
var maximum: float = 100.0
var value: float = 0.0
var idle_ticks: int = 0
var stagger_ticks_left: int = 0
var stagger_duration: int = 150
var decay_enabled: bool = true
var _tick_fraction: float = 0.0

func configure(combat_tuning: CombatTuning, is_elite: bool = false) -> void:
	tuning = combat_tuning
	maximum = tuning.heat_max
	stagger_duration = tuning.elite_stagger_ticks if is_elite else tuning.stagger_ticks
	_tick_fraction = 0.0

func add_heat(amount: float) -> void:
	if amount <= 0.0:
		return
	value = minf(maximum, value + amount)
	idle_ticks = 0
	value_changed.emit(value, maximum)
	if value >= maximum and not is_staggered():
		start_stagger()

func reduce_heat(amount: float) -> void:
	if amount <= 0.0:
		return
	value = maxf(0.0, value - amount)
	idle_ticks = 0
	value_changed.emit(value, maximum)

## Enemy adapters: consume scaled simulation time, one step() per elapsed
## tick at tuning.tick_rate. Hitstop slows it; pause stops it. Never also call
## step() for the same update.
func advance_simulation(delta: float, active: bool) -> void:
	if tuning == null or not is_finite(delta) or delta <= 0.0:
		return
	_tick_fraction += delta * float(tuning.tick_rate)
	while _tick_fraction >= 1.0 - 0.000001:
		_tick_fraction -= 1.0
		step(active)

## One explicit tick (player controller and fixed-tick callers).
func step(active: bool) -> void:
	if tuning == null:
		return
	if is_staggered():
		stagger_ticks_left -= 1
		if stagger_ticks_left <= 0:
			stagger_ticks_left = 0
			value = 0.0
			idle_ticks = 0
			value_changed.emit(value, maximum)
			stagger_ended.emit()
		return
	if active:
		idle_ticks = 0
		return
	idle_ticks += 1
	if decay_enabled and idle_ticks > tuning.heat_idle_delay_ticks and value > 0.0:
		value = maxf(0.0, value - tuning.heat_decay_per_second / float(tuning.tick_rate))
		value_changed.emit(value, maximum)

func start_stagger() -> void:
	if stagger_ticks_left > 0:
		return
	stagger_ticks_left = maxi(1, stagger_duration)
	staggered.emit(stagger_ticks_left)

func is_staggered() -> bool:
	return stagger_ticks_left > 0

