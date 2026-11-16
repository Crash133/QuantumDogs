class_name BatteryMeter
extends Resource

signal value_changed(value: float, maximum: float)
signal died
signal revived(remaining: int)

var tuning: CombatTuning
var maximum: float = 100.0
var value: float = 100.0
var ramp_multiplier: float = 1.0
var inactive_ticks: int = 0
var parry_pause_ticks: int = 0
var revives: int = 0
var drain_enabled: bool = true
var is_dead: bool = false

func configure(combat_tuning: CombatTuning, enable_drain: bool = true) -> void:
	tuning = combat_tuning
	maximum = tuning.battery_max
	value = maximum
	drain_enabled = enable_drain
	value_changed.emit(value, maximum)

func step(active: bool, enabled: bool = true) -> void:
	if tuning == null or is_dead:
		return
	if active:
		inactive_ticks = 0
	else:
		inactive_ticks += 1
		if inactive_ticks > tuning.battery_ramp_delay_ticks:
			ramp_multiplier = minf(tuning.battery_ramp_max_multiplier, ramp_multiplier + tuning.battery_ramp_per_second / float(tuning.tick_rate))
	if parry_pause_ticks > 0:
		parry_pause_ticks -= 1
		return
	if not drain_enabled or not enabled:
		return
	var amount := tuning.battery_baseline_drain_per_second * ramp_multiplier / float(tuning.tick_rate)
	_reduce(amount)

func take_damage(amount: float) -> void:
	ramp_multiplier = 1.0
	inactive_ticks = 0
	_reduce(amount)

func heal(amount: float) -> void:
	if amount <= 0.0 or is_dead:
		return
	var old_value := value
	value = minf(maximum, value + amount)
	if value != old_value:
		value_changed.emit(value, maximum)

func pause_drain(ticks: int) -> void:
	parry_pause_ticks = maxi(parry_pause_ticks, ticks)

func set_revives(amount: int) -> void:
	revives = maxi(0, amount)

func _reduce(amount: float) -> void:
	if amount <= 0.0 or is_dead:
		return
	var old_value := value
	value = maxf(0.0, value - amount)
	if value != old_value:
		value_changed.emit(value, maximum)
	if value > 0.0:
		return
	if revives > 0:
		revives -= 1
		value = maximum
		ramp_multiplier = 1.0
		inactive_ticks = 0
		value_changed.emit(value, maximum)
		revived.emit(revives)
	else:
		is_dead = true
		died.emit()

