class_name RevolverAmmo
extends Resource

signal ammo_changed(current: int, capacity: int)
signal fired

var capacity: int = 6
var current: int = 6
var shot_interval_ticks: int = 7
var regen_ticks_per_shot: int = 48
var tick_rate: int = 60
var _shot_cooldown: int = 0
var _regen_ticks: int = 0

func configure(tuning: CombatTuning) -> void:
	capacity = tuning.revolver_capacity
	current = capacity
	shot_interval_ticks = tuning.revolver_shot_interval_ticks
	regen_ticks_per_shot = tuning.revolver_regen_ticks_per_shot
	tick_rate = tuning.tick_rate
	_shot_cooldown = 0
	_regen_ticks = 0
	ammo_changed.emit(current, capacity)

func fire() -> bool:
	if current <= 0 or _shot_cooldown > 0:
		return false
	current -= 1
	_shot_cooldown = shot_interval_ticks
	if _regen_ticks == 0:
		_regen_ticks = regen_ticks_per_shot
	ammo_changed.emit(current, capacity)
	fired.emit()
	return true

func step() -> void:
	if _shot_cooldown > 0:
		_shot_cooldown -= 1
	if current >= capacity:
		_regen_ticks = 0
		return
	_regen_ticks -= 1
	if _regen_ticks <= 0:
		current += 1
		ammo_changed.emit(current, capacity)
		_regen_ticks = regen_ticks_per_shot if current < capacity else 0

