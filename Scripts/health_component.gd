class_name HealthComponent
extends Node

@export var max_health := 100.0
@export var decay: Curve
@export var decay_holdup: Curve

var _health := 0.0
var time_since_last_heal: float = 0

signal health_changed(amount: float, curr_health: float, percentage: float)
signal died(amount: float)

func _ready() -> void:
	heal_health(max_health)
	
func _process(delta: float) -> void:
	time_since_last_heal += delta
	
	if decay:
		var rate = decay.sample(get_health_perc())
		var potency = decay_holdup.sample(time_since_last_heal)
		
		reduce_health(rate * delta * potency) 
	
	
func get_health() -> float:
	return _health
	
func get_health_perc() -> float:
	return _health / max_health
	
	
func reduce_health(amount: float) -> void:
	if _reduce_health(amount):
		died.emit(amount)
	else:
		health_changed.emit(-amount, _health, get_health_perc())
	
func heal_health(amount: float) -> void:
	_health = min(_health + amount, max_health)
	health_changed.emit(amount, _health, get_health_perc())
	time_since_last_heal = 0

func _reduce_health(amount: float) -> bool:
	_health -= amount
	
	if _health <= 0:
		_health = 0
		return true
		
	return false
	

func _on_hurtbox_took_damage(amount: float) -> void:
	reduce_health(amount)
