class_name Combatant
extends Node3D

@export var maximum_health: float = 100.0
@export var elite: bool = false
@export var flying: bool = false
@export var tuning: CombatTuning

var health: float = 100.0
var heat_meter: HeatMeter
var alive: bool = true
## Lightweight test/debug adapter: same reaction decisions as Enemy, moved by
## position instead of a CharacterBody. Uses an authored "Reactions" child when
## present, otherwise builds one documented debug component from the common or
## elite profile.
var reactions: EnemyReactionController
var _ground_y: float

# Read-only views of the reaction component (migration compatibility).
var air_reaction: EnemyAirReaction:
	get: return reactions.air if reactions != null else null
var gather_reaction: CombatGatherReaction:
	get: return reactions.gather if reactions != null else null
var throw_velocity: Vector3:
	get: return reactions.planar_velocity if reactions != null else Vector3.ZERO

func _ready() -> void:
	add_to_group("combatants")
	health = maximum_health
	_ground_y = global_position.y
	if tuning == null:
		tuning = CombatTuning.new()
	if elite:
		heat_meter = HeatMeter.new()
		heat_meter.configure(tuning, true)
		heat_meter.value_changed.connect(_on_heat_changed)
		heat_meter.staggered.connect(_on_staggered)
	reactions = get_node_or_null("Reactions") as EnemyReactionController
	if reactions == null:
		reactions = EnemyReactionController.new()
		reactions.name = "Reactions"
		reactions.profile = load("res://Resources/Combat/Reactions/%s.tres" % ("elite" if elite else "common"))
		add_child(reactions)
	reactions.configure(null, tuning, heat_meter)

func _physics_process(delta: float) -> void:
	if not alive:
		return
	if heat_meter != null:
		heat_meter.advance_simulation(delta, false)
	var grounded := global_position.y <= _ground_y + 0.0001
	var velocity := reactions.step(delta, global_position, Vector3.ZERO, grounded, flying)
	global_position += velocity * delta
	var landed := global_position.y <= _ground_y and velocity.y <= 0.0
	if landed:
		global_position.y = _ground_y
	reactions.after_move(velocity, landed or (grounded and velocity.y <= 0.0))

func take_hit(hit: HitData) -> void:
	if not alive or hit == null:
		return
	var was_airborne := is_combat_airborne()
	health = maxf(0.0, health - hit.damage)
	if health <= 0.0:
		alive = false
		hit.reaction_outcome = &"defeated"
		reactions.mark_defeated()
		return
	if heat_meter != null:
		heat_meter.add_heat(hit.heat)
	reactions.apply_hit(hit, was_airborne)

func is_combat_airborne() -> bool:
	return flying or reactions.air.airborne or global_position.y > _ground_y + 0.01

func get_combat_center() -> Vector3:
	for child in get_children():
		if child is HurtboxProxy:
			return child.global_position
	return global_position

## Returns whether the lease was accepted (closed elite armor refuses it).
func begin_combat_gather(provider: Node, speed: float) -> bool:
	return alive and reactions.begin_gather(provider, speed)

func end_combat_gather(provider: Node, release_velocity: Vector3) -> void:
	reactions.end_gather(provider, release_velocity if alive else Vector3.ZERO)

func get_heat_meter() -> HeatMeter:
	return heat_meter

func try_parry(_hit: HitData) -> bool:
	return false

func is_staggered() -> bool:
	return heat_meter != null and heat_meter.is_staggered()

func is_execution_shockwave_locked() -> bool:
	return reactions != null and reactions.is_execution_shockwave_locked()

func is_alive() -> bool:
	return alive

func execute() -> bool:
	if not elite or not is_staggered() or not alive or heat_meter.value < heat_meter.maximum:
		return false
	health = 0.0
	alive = false
	reactions.mark_defeated()
	return true

func _on_heat_changed(value: float, maximum: float) -> void:
	var events := get_node_or_null("/root/CombatEvents")
	if events != null:
		events.heat_changed.emit(self, value, maximum)

func _on_staggered(duration: int) -> void:
	var events := get_node_or_null("/root/CombatEvents")
	if events != null:
		events.staggered.emit(self, duration)
