class_name Enemy
extends CharacterBody3D

signal defeated(enemy: Enemy)
signal despawned(enemy: Enemy)

var definition: EnemyDefinition
var difficulty_snapshot: Dictionary = {}
var _terminal: bool = false
var _parry_cooldown: int = 0
var _parry_tick_fraction: float = 0.0
var _parry_rng := RandomNumberGenerator.new()
var _time_domains: Node
var _action_leases: Node
@export var enemy_attacks_enabled: bool = false
## Authored center used by contact-committed executions; position-only target.
@export var execution_center: Node3D

@export var SPEED := 5.0
@export var player: Player
@export var elite: bool = false
@export var flying: bool = false
@export var tuning: CombatTuning
@export_group("Combat Hurtbox")
## Native capsule radius in world meters. 0.45 m is modestly forgiving over the
## authored enemy hurt mesh while staying narrower than the current 0.6 m.
@export_range(0.25, 1.0, 0.01, "suffix:m") var combat_hurtbox_radius: float = 0.45
## Native capsule total height in world meters.
@export_range(0.5, 2.5, 0.05, "suffix:m") var combat_hurtbox_height: float = 1.8
## Vertical center of the native capsule above the enemy origin, in meters.
@export_range(0.0, 2.5, 0.05, "suffix:m") var combat_hurtbox_center_height: float = 0.9

## Legacy rig driver: only the old base scene (Enemy.tscn) has one; the lean role enemies do not.
@onready var tree: AnimationTree = get_node_or_null("AnimationTree") as AnimationTree
## Cached once: these were looked up by path every frame/tick for every enemy.
@onready var _health: HealthComponent = $HealthComponent
var _role: Node # Resolved lazily: some fixtures attach the controller after _ready.
## False once the hidden legacy rig's AnimationTree has been retired (role enemies).
var _legacy_tree_live: bool = true

var direction := Vector3.ZERO
## Set by the encounter director when the arena has gaps; ground enemies steer around them.
var flow_field: ArenaFlowField
## A drone that was hit: down and immobile until it rises back to hover.
var _recover_flight: bool = false
var _was_grounded: bool = false
var _rising: bool = false
var _rise_target_y: float = 0.0
var heat_meter: HeatMeter
var combat_hurtbox: HurtboxProxy
## Authored child (Scenes/Combat/EnemyReactionController.tscn) that owns every
## hit reaction; Enemy only applies health/heat and moves the body.
@onready var reactions: EnemyReactionController = get_node_or_null("Reactions") as EnemyReactionController

# Read-only views of the reaction component (migration compatibility).
var stun: float:
	get: return reactions.stun_seconds_left if reactions != null else 0.0
	set(_value): push_error("Enemy.stun is read-only; apply a HitData instead")
var knockback_velocity: Vector3:
	get: return reactions.planar_velocity if reactions != null else Vector3.ZERO
	set(_value): push_error("Enemy.knockback_velocity is read-only; apply a HitData instead")
var air_reaction: EnemyAirReaction:
	get: return reactions.air if reactions != null else null
	set(_value): push_error("Enemy.air_reaction is owned by the reaction component")
var gather_reaction: CombatGatherReaction:
	get: return reactions.gather if reactions != null else null
	set(_value): push_error("Enemy.gather_reaction is owned by the reaction component")

func _ready() -> void:
	if tuning == null:
		tuning = CombatTuning.new()
	add_to_group("combatants")
	add_to_group("enemy_combatants")
	_retire_hidden_legacy_rigs()
	_time_domains = get_tree().get_first_node_in_group("combat_time_domains") as Node
	_action_leases = get_tree().get_first_node_in_group("combat_action_leases") as Node
	_register_combat_hurtbox()
	if elite:
		heat_meter = HeatMeter.new()
		heat_meter.configure(tuning, true)
		heat_meter.value_changed.connect(_on_combat_heat_changed)
		heat_meter.staggered.connect(_on_combat_staggered)
	if reactions == null:
		push_error("%s has no authored Reactions child (Scenes/Combat/EnemyReactionController.tscn)" % name)
	else:
		reactions.configure(null, tuning, heat_meter)
	if definition != null:
		_apply_definition()
	_parry_rng.randomize()

func setup(new_definition: EnemyDefinition, player_node: Node3D, difficulty: Dictionary = {}) -> void:
	definition = new_definition
	difficulty_snapshot = difficulty.duplicate(true)
	player = player_node as Player
	if is_inside_tree():
		_apply_definition()

func _apply_definition() -> void:
	if definition == null:
		return
	elite = definition.role == &"elite"
	flying = definition.role == &"drone"
	SPEED = definition.move_speed
	var health = get_node_or_null("HealthComponent")
	if health != null:
		var old_health: float = health.get_health()
		health.max_health = definition.max_health * maxf(0.01, float(difficulty_snapshot.get("health_multiplier", 1.0)))
		if old_health > 0.0:
			health.heal_health(health.max_health - old_health)
	if elite and heat_meter == null:
		heat_meter = HeatMeter.new()
		heat_meter.configure(tuning, true)
		heat_meter.value_changed.connect(_on_combat_heat_changed)
		heat_meter.staggered.connect(_on_combat_staggered)
		if reactions != null:
			reactions.configure(null, tuning, heat_meter)
	var controller := get_node_or_null("RoleController")
	if controller != null and controller.has_method("setup"):
		controller.setup(self, definition, player)

func get_faction() -> StringName:
	return &"enemy"

func despawn() -> void:
	if _terminal:
		return
	_terminal = true
	if reactions != null:
		reactions.mark_defeated()
	despawned.emit(self)
	queue_free()

func _exit_tree() -> void:
	if not _terminal:
		_terminal = true
		despawned.emit(self)

func _register_combat_hurtbox() -> void:
	var manager := get_tree().get_first_node_in_group("combat_hit_managers") as HitManagerNode
	if manager == null:
		return
	combat_hurtbox = HurtboxProxy.new()
	combat_hurtbox.name = "CombatHurtboxProxy"
	combat_hurtbox.combatant = self
	combat_hurtbox.manager = manager
	combat_hurtbox.radius = combat_hurtbox_radius
	combat_hurtbox.height = combat_hurtbox_height
	combat_hurtbox.position = Vector3.UP * combat_hurtbox_center_height
	add_child(combat_hurtbox)

## Role enemies show only their RoleVisual; the legacy rigs (and the AnimationTree
## that drives one of them) stay hidden. Stop paying for them every frame.
func _retire_hidden_legacy_rigs() -> void:
	if tree == null:
		_legacy_tree_live = false
	for legacy_name in ["FantasyWarrior", "Mech Type 3"]:
		var rig := get_node_or_null(legacy_name) as Node3D
		if rig != null and not rig.visible:
			rig.process_mode = Node.PROCESS_MODE_DISABLED
			if legacy_name == "Mech Type 3" and tree != null:
				tree.active = false
				_legacy_tree_live = false

## A grounded enemy that is not moving (windup, strike, recovery) needs no collision sweep.
func _slide() -> void:
	if velocity.is_zero_approx() and (_was_grounded or flying):
		return
	var probe := ScriptCostProbe.start()
	move_and_slide()
	_was_grounded = is_on_floor()
	ScriptCostProbe.stop(&"enemy.move_and_slide", probe)

func _role_controller() -> Node:
	if _role == null or not is_instance_valid(_role):
		_role = get_node_or_null("RoleController")
	return _role

func _process(delta: float) -> void:
	var _probe := ScriptCostProbe.start()
	_process_body(delta)
	ScriptCostProbe.stop(&"enemy.process", _probe)

func _process_body(delta: float) -> void:
	if not is_instance_valid(player) or _recover_flight:
		return # A downed drone does not turn either.
	var role := _role_controller()
	if role != null and role.has_method("is_attack_locked") and role.is_attack_locked():
		return # Telegraphed: the strike goes where the windup pointed.
	var pp = player.global_position
	pp.y = global_position.y
	direction = (pp - global_position).normalized()
	
	if not global_position.is_equal_approx(pp):
		look_at(pp, Vector3.UP)

func _physics_process(delta: float) -> void:
	var _probe := ScriptCostProbe.start()
	_physics_process_body(delta)
	ScriptCostProbe.stop(&"enemy.physics", _probe)

func _physics_process_body(delta: float) -> void:
	var time_scale := 1.0
	if is_instance_valid(_time_domains) and _time_domains.has_method("factor_for"):
		time_scale = clampf(float(_time_domains.call("factor_for", self)), 0.01, 1.0)
	var local_delta := delta * time_scale
	var execution_victim := is_instance_valid(_action_leases) and _action_leases.has_method("is_execution_victim") and bool(_action_leases.call("is_execution_victim", self))
	if execution_victim:
		# Reservation freezes AI, movement, gravity and stagger/heat timers. The
		# lease releases into the same airborne mode with vertical speed at zero.
		velocity = Vector3.ZERO
		if reactions != null:
			reactions.air.vertical_velocity = 0.0
		if _legacy_tree_live and tree.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL:
			tree.advance(local_delta)
		_slide()
		return
	var controller := _role_controller()
	if controller != null and controller.has_method("step_physics"):
		controller.step_physics(local_delta)
	_parry_tick_fraction += local_delta * float(tuning.tick_rate if tuning != null else 60)
	while _parry_tick_fraction >= 1.0 - 0.000001:
		_parry_tick_fraction -= 1.0
		if _parry_cooldown > 0:
			_parry_cooldown -= 1
	if heat_meter != null:
		heat_meter.advance_simulation(local_delta, false)
	if reactions == null:
		return
	var probe_reactions := ScriptCostProbe.start()
	var simulated_velocity := reactions.step(local_delta, global_position, direction * SPEED, is_on_floor(), flying)
	ScriptCostProbe.stop(&"enemy.reactions.step", probe_reactions)
	simulated_velocity = _apply_drone_recovery(simulated_velocity)
	var gravity_held := is_instance_valid(_action_leases) and _action_leases.has_method("gravity_held") and bool(_action_leases.call("gravity_held", self))
	if gravity_held:
		simulated_velocity.y = 0.0
		reactions.air.vertical_velocity = 0.0
	velocity = simulated_velocity * time_scale
	if _legacy_tree_live:
		tree.set('parameters/blend_position', clampf(Vector2(simulated_velocity.x, simulated_velocity.z).length(), 0.0, 1.0))
		if tree.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL:
			tree.advance(local_delta)
	_slide()
	reactions.after_move(velocity / time_scale, is_on_floor())

## Once the downed hold ends the drone climbs back to its hover height and flies again.
func _apply_drone_recovery(simulated_velocity: Vector3) -> Vector3:
	if _recover_flight and is_on_floor() and not reactions.blocks_actions():
		_recover_flight = false
		_rising = true
		flying = true
		_rise_target_y = global_position.y + (definition.hover_height if definition != null else 2.0)
	if _rising:
		if global_position.y >= _rise_target_y - 0.05:
			_rising = false
		else:
			simulated_velocity.y = tuning.drone_rise_speed
	return simulated_velocity

## Health, then heat, then the reaction. Lethal hits end reaction ownership.
func take_hit(hit: HitData) -> void:
	if hit == null or not is_alive():
		return
	var was_airborne := is_combat_airborne()
	_health.reduce_health(hit.damage)
	if not is_alive():
		hit.reaction_outcome = &"defeated"
		_cancel_role_attack()
		return
	if heat_meter != null:
		heat_meter.add_heat(hit.heat)
	if not is_alive():
		return
	var drops := flying and hit.damage > 0.0
	if drops:
		flying = false # A hit drone drops out of the air at once and stays grounded.
	if reactions == null:
		return
	reactions.apply_hit(hit, was_airborne)
	if drops:
		_recover_flight = true
		_rising = false
		reactions.begin_drop(tuning.drone_downed_seconds)
	if reactions.blocks_actions():
		_cancel_role_attack()

## The player parried this enemy's attack: open elite armor and stop the swing.
func on_attack_parried() -> void:
	if not is_alive():
		return
	if reactions != null:
		reactions.open_from_parry()
	_cancel_role_attack()

func _cancel_role_attack() -> void:
	var controller := get_node_or_null("RoleController")
	if controller != null and controller.has_method("cancel_attack"):
		controller.cancel_attack()

func is_combat_airborne() -> bool:
	return flying or (reactions != null and reactions.air.airborne) or not is_on_floor()

## Distinguish authored/launch airtime from the brief off-floor spawn settle.
func is_execution_airborne() -> bool:
	return flying or (reactions != null and reactions.air.airborne)

func get_combat_center() -> Vector3:
	return combat_hurtbox.global_position if is_instance_valid(combat_hurtbox) else global_position + global_basis.y * 0.9

## Returns whether the lease was accepted (closed elite armor refuses it).
func begin_combat_gather(provider: Node, speed: float) -> bool:
	return reactions != null and is_alive() and reactions.begin_gather(provider, speed)

func end_combat_gather(provider: Node, release_velocity: Vector3) -> void:
	if reactions != null:
		reactions.end_gather(provider, release_velocity if is_alive() else Vector3.ZERO)

func get_heat_meter() -> HeatMeter:
	return heat_meter

func try_parry(hit: HitData) -> bool:
	if not elite or definition == null or hit == null or hit.damage <= 0.0 or not is_alive() or is_staggered() or _parry_cooldown > 0:
		return false
	if _parry_rng.randf() >= definition.parry_chance:
		return false
	_parry_cooldown = definition.parry_cooldown_ticks
	return true

func is_staggered() -> bool:
	return heat_meter != null and heat_meter.is_staggered()

## Applies an execution finisher's radial reaction without damage or heat.
func apply_execution_shockwave(stun_seconds: float, execution_lock_seconds: float, slam_speed: float) -> void:
	if not is_alive() or reactions == null:
		return
	var force_down := is_execution_airborne()
	if force_down:
		flying = false
	reactions.apply_execution_shockwave(stun_seconds, execution_lock_seconds, force_down, slam_speed)

## True while the enemy is in the execution shockwave's authored lock window.
func is_execution_shockwave_locked() -> bool:
	return reactions != null and reactions.is_execution_shockwave_locked()

func is_alive() -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and _health.get_health() > 0.0

## Staggered elites at full Heat, or any non-elite lying knocked down (greatsword).
func is_executable() -> bool:
	if not is_alive():
		return false
	# Elites wait out any reaction; a common lying down is executable, but not while the shockwave lock runs.
	if elite and is_execution_shockwave_locked():
		return false
	if reactions != null and reactions.execution_shockwave_lock_seconds_left > 0.0:
		return false
	if elite:
		return is_staggered() and heat_meter != null and heat_meter.value >= heat_meter.maximum
	return reactions != null and reactions.is_knocked_down()

func execute() -> bool:
	if not is_executable():
		return false
	_health.reduce_health(_health.get_health())
	return true

## Authored position-only target used by procedural execution contact.
func get_execution_center() -> Node3D:
	return execution_center if is_instance_valid(execution_center) else null

func _on_combat_heat_changed(value: float, maximum: float) -> void:
	var events := get_node_or_null("/root/CombatEvents")
	if events != null:
		events.heat_changed.emit(self, value, maximum)

func _on_combat_staggered(duration: int) -> void:
	var events := get_node_or_null("/root/CombatEvents")
	if events != null:
		events.staggered.emit(self, duration)


func _on_health_component_died(amount: float) -> void:
	if reactions != null:
		reactions.mark_defeated()
	if not _terminal:
		_terminal = true
		defeated.emit(self)
	queue_free()
