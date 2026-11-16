class_name EnemyReactionController
extends Node

## Owns an enemy's reaction to clean hits: flinch time, bounded horizontal
## reaction velocity, knockdown/get-up, elite armor openings, and arbitration
## of the existing air (launch/hold/slam) and gather helpers. It never changes
## health, heat, damage, score, battery or feedback, never moves a node, and
## has no _physics_process: the body steps it once per physics update, moves,
## then reports the collision-resolved result back through after_move().
## HeatMeter keeps owning stagger; this only reads it.

const PRIORITY_NONE := 0
const PRIORITY_FLINCH := 1
const PRIORITY_PUSHBACK := 2
const PRIORITY_STRONG := 3 # launch, knockdown, slam
enum Down { NONE, HOLD, GET_UP }
const TIME_EPSILON := 0.000001

@export var profile: EnemyReactionProfile

var tuning: CombatTuning
var heat: HeatMeter
## Helpers (single owners of their state; read them, do not mirror them).
var air: EnemyAirReaction = EnemyAirReaction.new()
var gather: CombatGatherReaction = CombatGatherReaction.new()
## Read-only from outside.
var stun_seconds_left: float = 0.0
var planar_velocity: Vector3 = Vector3.ZERO

var _priority: int = PRIORITY_NONE
var _down: Down = Down.NONE
var _down_left: float = 0.0
var _slamming: bool = false
var _slam_speed: float = 0.0
var _dropping: bool = false
var _drop_hold_seconds: float = 0.0
var _down_on_landing: bool = false
var _opening_left: float = 0.0
var _cooldown_left: float = 0.0
var execution_shockwave_lock_seconds_left: float = 0.0
var _defeated: bool = false
var _last_actual_vertical_velocity: float = 0.0

## Fresh-spawn reset. The profile is shared and never mutated.
func configure(new_profile: EnemyReactionProfile, combat_tuning: CombatTuning, heat_meter: HeatMeter) -> void:
	if new_profile != null:
		profile = new_profile
	tuning = combat_tuning
	heat = heat_meter
	if profile == null:
		push_error("EnemyReactionController needs an authored EnemyReactionProfile")
	clear()

func clear() -> void:
	stun_seconds_left = 0.0
	planar_velocity = Vector3.ZERO
	_priority = PRIORITY_NONE
	_down = Down.NONE
	_down_left = 0.0
	_slamming = false
	_slam_speed = 0.0
	_down_on_landing = false
	_opening_left = 0.0
	_cooldown_left = 0.0
	execution_shockwave_lock_seconds_left = 0.0
	_defeated = false
	_last_actual_vertical_velocity = 0.0
	air.land()
	gather.provider = null

## Lethal damage ends reaction ownership: no further reactions or actions.
func mark_defeated() -> void:
	clear()
	_defeated = true

## Decides and records the target's reaction to an already-resolved hit.
## Fills hit.reaction_outcome / reaction_direction; applies no damage or heat.
func apply_hit(hit: HitData, already_airborne: bool) -> StringName:
	var outcome := _decide(hit, already_airborne)
	if hit != null:
		hit.reaction_outcome = outcome
	return outcome

## Applies a no-damage execution pulse, bypassing closed elite armor while
## keeping reaction ownership and local-clock recovery in this controller.
func apply_execution_shockwave(stun_seconds: float, execution_lock_seconds: float, force_down: bool, slam_speed: float) -> void:
	if _defeated or profile == null:
		return
	execution_shockwave_lock_seconds_left = maxf(execution_shockwave_lock_seconds_left, maxf(0.0, execution_lock_seconds))
	if force_down:
		stun_seconds_left = 0.0
		_slamming = true
		_slam_speed = maxf(0.1, slam_speed)
		_down_on_landing = true
		air.slam(_slam_speed)
		planar_velocity = Vector3.ZERO
		_priority = PRIORITY_STRONG
		return
	stun_seconds_left = maxf(stun_seconds_left, maxf(0.0, stun_seconds))

## Shockwave-tagged enemies cannot start another execution during their reaction lock.
func is_execution_shockwave_locked() -> bool:
	return execution_shockwave_lock_seconds_left > 0.0 or stun_seconds_left > 0.0 or _down != Down.NONE or _slamming

func _decide(hit: HitData, airborne: bool) -> StringName:
	if hit == null or _defeated or profile == null:
		return &"none"
	var planar := Vector3(hit.knockback.x, 0.0, hit.knockback.z) if hit.knockback.is_finite() else Vector3.ZERO
	hit.reaction_direction = planar.normalized() if not planar.is_zero_approx() else Vector3.ZERO
	var kind := hit.reaction_kind
	if kind == &"flinch" and hit.effect == &"launch":
		kind = &"launch" # Legacy alias for direct HitData authors.
	if kind == &"":
		return &"none"
	var stun: float = hit.hitstun if is_finite(hit.hitstun) and hit.hitstun > 0.0 else 0.0
	if _armor_closed():
		if not hit.interrupts_armor or _cooldown_left > 0.0:
			return &"resisted"
		_opening_left = profile.heavy_opening
		_cooldown_left = profile.heavy_opening_cooldown
	# Down, slamming and get-up targets still take damage/heat but no new reaction.
	if _down != Down.NONE or _slamming:
		return &"none"
	if gather.active():
		_add_stun(stun) # Gather owns movement: only the lesser flinch is accepted.
		return &"flinch"
	match kind:
		&"flinch", &"pushback":
			_add_stun(stun)
			_push(planar, PRIORITY_FLINCH if kind == &"flinch" else PRIORITY_PUSHBACK)
			if airborne and hit.damage > 0.0:
				air.hold(tuning.enemy_air_hit_hold_ticks)
				return &"air_hold"
			return kind
		&"launch":
			_add_stun(stun)
			_push(planar, PRIORITY_STRONG)
			if airborne:
				air.hold(tuning.enemy_air_hit_hold_ticks) # A second launcher freezes, never relaunches.
				return &"air_hold"
			var upward: float = hit.knockback.y if hit.knockback.is_finite() and hit.knockback.y > 0.0 else tuning.launcher_upward_speed * maxf(hit.potency, 0.0)
			if upward <= 0.0:
				return &"flinch"
			air.launch(upward, tuning.enemy_air_hit_hold_ticks)
			_last_actual_vertical_velocity = 0.0
			return &"launch"
		&"knockdown":
			_push(planar, PRIORITY_STRONG)
			if airborne:
				_down_on_landing = true
			else:
				_enter_knockdown()
			return &"knockdown"
		&"slam":
			_push(planar, PRIORITY_STRONG)
			if not airborne:
				_enter_knockdown()
				return &"knockdown"
			_slamming = true
			_slam_speed = profile.slam_speed
			air.slam(_slam_speed)
			return &"slam"
	return &"none"

## 1 when a get-up starts, 0 when it ends (presentation easing only).
func get_up_fraction() -> float:
	if _down != Down.GET_UP or profile == null or profile.get_up_recovery <= 0.0:
		return 0.0
	return clampf(_down_left / profile.get_up_recovery, 0.0, 1.0)

func open_from_parry() -> void:
	if profile != null and profile.armor_enabled and not _defeated:
		_opening_left = maxf(_opening_left, profile.parry_opening)

## Lying on the ground (the hold, not the get-up): a common enemy can be executed now.
func is_knocked_down() -> bool:
	return _down == Down.HOLD and not _defeated

## True while the enemy must not start or continue an attack.
func blocks_actions() -> bool:
	return _defeated or stun_seconds_left > 0.0 or _down != Down.NONE or _slamming or air.airborne or gather.active() or (heat != null and heat.is_staggered())

## Read-only state for animation, in priority order.
func presentation_state() -> StringName:
	if _defeated: return &"dead"
	if _down == Down.HOLD: return &"knockdown"
	if _down == Down.GET_UP: return &"get_up"
	if heat != null and heat.is_staggered(): return &"stagger"
	if _slamming or air.airborne: return &"airborne"
	if stun_seconds_left > 0.0: return &"flinch"
	return &"none"

## One simulation step. Returns the velocity the body should move with.
## desired_velocity is the role's locomotion; delta is scaled simulation time.
func step(delta: float, position: Vector3, desired_velocity: Vector3, grounded: bool, flying: bool) -> Vector3:
	if not is_finite(delta) or delta < 0.0:
		delta = 0.0
	if gather.provider != null and not is_instance_valid(gather.provider):
		gather.provider = null # Freed provider: release with zero velocity.
	if delta > 0.0:
		stun_seconds_left = maxf(0.0, stun_seconds_left - delta)
		execution_shockwave_lock_seconds_left = maxf(0.0, execution_shockwave_lock_seconds_left - delta)
		_opening_left = maxf(0.0, _opening_left - delta)
		_cooldown_left = maxf(0.0, _cooldown_left - delta)
		_step_down(delta)
	var horizontal: Vector3
	if gather.active():
		horizontal = gather.velocity_at(position, delta) if delta > 0.0 else Vector3.ZERO
	elif blocks_actions() or _priority != PRIORITY_NONE:
		horizontal = planar_velocity
	else:
		horizontal = Vector3(desired_velocity.x, 0.0, desired_velocity.z)
	if delta > 0.0 and _priority != PRIORITY_NONE:
		planar_velocity = planar_velocity.move_toward(Vector3.ZERO, profile.horizontal_deceleration * delta)
		if planar_velocity.is_zero_approx():
			planar_velocity = Vector3.ZERO
			_priority = PRIORITY_NONE
	var vertical := 0.0
	if _slamming:
		vertical = -_slam_speed
	elif flying and not air.airborne:
		vertical = 0.0 # Ordinary hover: no reaction flight.
	else:
		if not grounded and not flying:
			air.airborne = true
		if grounded:
			_dropping = false
		var gravity := tuning.enemy_gravity * (tuning.drone_drop_gravity_scale if _dropping else 1.0)
		vertical = air.step(gravity, delta) if delta > 0.0 else air.vertical_velocity
		if flying and air.hold_ticks_left <= 0 and air.vertical_velocity <= 0.0:
			air.land() # A hovering drone's hold ends where it is.
			vertical = 0.0
	return Vector3(horizontal.x, vertical, horizontal.z)

## A hit drone leaves the air immediately and falls at boosted gravity until it lands.
func begin_drop(hold_seconds: float = 0.0) -> void:
	_dropping = true
	_drop_hold_seconds = maxf(0.0, hold_seconds)
	air.drop()

## Collision feedback after move_and_slide. Never moves a node.
func after_move(actual_velocity: Vector3, grounded: bool) -> void:
	if not actual_velocity.is_finite():
		return
	# Capture only a real upward-to-downward transition. Checking the requested
	# velocity too avoids mistaking an overhead collision for an apex.
	var captured_apex := false
	if not grounded and not _slamming and air.airborne and air.hold_ticks_left <= 0 \
			and _last_actual_vertical_velocity > 0.0 and air.vertical_velocity <= 0.0:
		captured_apex = air.capture_apex(tuning.enemy_apex_hold_ticks)
	air.vertical_velocity = 0.0 if captured_apex else actual_velocity.y
	_last_actual_vertical_velocity = actual_velocity.y if not grounded else 0.0
	if _priority != PRIORITY_NONE and not gather.active():
		# A wall stops the reaction; do not push into it again every frame.
		var actual_planar := Vector3(actual_velocity.x, 0.0, actual_velocity.z)
		if actual_planar.length() < planar_velocity.length():
			planar_velocity = actual_planar
	if grounded and actual_velocity.y <= 0.0 and (air.airborne or _slamming):
		var landed_down := _slamming or _down_on_landing
		var drop_hold := _drop_hold_seconds if _dropping else 0.0
		air.land()
		_slamming = false
		_slam_speed = 0.0
		_down_on_landing = false
		_dropping = false
		_drop_hold_seconds = 0.0
		if landed_down:
			_enter_knockdown()
		elif drop_hold > 0.0:
			_enter_knockdown(drop_hold)

func begin_gather(provider: Node, speed: float) -> bool:
	if _defeated or provider == null or _armor_closed():
		return false
	gather.begin(provider, speed)
	planar_velocity = Vector3.ZERO # No hidden impulse banked behind the lease.
	_priority = PRIORITY_NONE
	return true

func end_gather(provider: Node, release_velocity: Vector3) -> void:
	if not gather.release(provider):
		return
	var planar := Vector3(release_velocity.x, 0.0, release_velocity.z) if release_velocity.is_finite() else Vector3.ZERO
	if not planar.is_zero_approx():
		planar_velocity = planar.limit_length(profile.max_horizontal_speed)
		_priority = PRIORITY_PUSHBACK

func _armor_closed() -> bool:
	return profile != null and profile.armor_enabled and _opening_left <= 0.0 and not (heat != null and heat.is_staggered())

func _add_stun(seconds: float) -> void:
	stun_seconds_left = maxf(stun_seconds_left, seconds)
	if profile.armor_enabled and not (heat != null and heat.is_staggered()):
		# Ordinary flinch never outlives an elite's opening.
		stun_seconds_left = minf(stun_seconds_left, _opening_left)

func _push(planar: Vector3, priority: int) -> void:
	if planar.is_zero_approx():
		return
	var incoming := planar.limit_length(profile.max_horizontal_speed)
	if priority < _priority and not planar_velocity.is_zero_approx():
		return # A weaker reaction never redirects a stronger one.
	if priority == _priority and incoming.length() < planar_velocity.length():
		return
	planar_velocity = incoming
	_priority = priority

func _enter_knockdown(hold_seconds: float = -1.0) -> void:
	stun_seconds_left = 0.0 # No flinch is banked past recovery.
	_down = Down.HOLD
	_down_left = hold_seconds if hold_seconds >= 0.0 else profile.knockdown_hold
	if _down_left <= 0.0:
		_down = Down.GET_UP
		_down_left = profile.get_up_recovery
		if _down_left <= 0.0:
			_down = Down.NONE

func _step_down(delta: float) -> void:
	if _down == Down.NONE:
		return
	_down_left -= delta
	while _down != Down.NONE and _down_left <= TIME_EPSILON:
		if _down == Down.HOLD:
			_down = Down.GET_UP
			_down_left += profile.get_up_recovery
		else:
			_down = Down.NONE
			_down_left = 0.0
