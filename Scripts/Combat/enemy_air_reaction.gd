class_name EnemyAirReaction
extends RefCounted

## Air reaction state: launch, air-hit hold (gravity suspended) and slam.
## Hold ticks are authored at 60 Hz and consumed from scaled elapsed time, so
## hitstop slows them and pause stops them.

const AUTHORED_TICKS_PER_SECOND := 60.0
const TICK_EPSILON := 0.000001

var airborne: bool = false
var vertical_velocity: float = 0.0
var hold_ticks_left: int = 0
var _hold_fraction: float = 0.0
var _apex_capture_available: bool = false

func receive_hit(hit: HitData, already_airborne: bool, tuning: CombatTuning) -> void:
	if hit.damage > 0.0 and already_airborne:
		hold(tuning.enemy_air_hit_hold_ticks)
	elif hit.effect == &"launch":
		var upward := hit.knockback.y if hit.knockback.y > 0.0 else tuning.launcher_upward_speed * hit.potency
		if upward <= 0.0:
			return
		launch(upward, tuning.enemy_air_hit_hold_ticks)

## Airborne hit: stop vertical motion and suspend gravity for the hold.
func hold(ticks: int) -> void:
	airborne = true
	vertical_velocity = 0.0
	hold_ticks_left = maxi(0, ticks)
	_hold_fraction = 0.0

func launch(upward_speed: float, ticks: int) -> void:
	airborne = true
	vertical_velocity = upward_speed
	hold_ticks_left = maxi(0, ticks)
	_hold_fraction = 0.0
	_apex_capture_available = upward_speed > 0.0

## Freeze one launch at its apex for a bounded, authored number of ticks.
## Returns false when disabled or when this launch has already been captured.
func capture_apex(ticks: int) -> bool:
	if not airborne or vertical_velocity > 0.0 or not _apex_capture_available or ticks <= 0:
		return false
	_apex_capture_available = false
	hold(ticks)
	return true

## Fall now: cancel any hold and any upward speed.
func drop() -> void:
	airborne = true
	hold_ticks_left = 0
	_hold_fraction = 0.0
	_apex_capture_available = false
	vertical_velocity = minf(vertical_velocity, 0.0)

## Drive straight down; any hold ends.
func slam(downward_speed: float) -> void:
	airborne = true
	hold_ticks_left = 0
	_hold_fraction = 0.0
	vertical_velocity = -absf(downward_speed)

func step(gravity: float, delta: float) -> float:
	if not airborne:
		return 0.0
	if hold_ticks_left > 0:
		_hold_fraction += maxf(0.0, delta) * AUTHORED_TICKS_PER_SECOND
		while hold_ticks_left > 0 and _hold_fraction >= 1.0 - TICK_EPSILON:
			hold_ticks_left -= 1
			_hold_fraction -= 1.0
		if hold_ticks_left == 0:
			_hold_fraction = 0.0
	else:
		vertical_velocity -= gravity * delta
	return vertical_velocity

func land() -> void:
	airborne = false
	vertical_velocity = 0.0
	hold_ticks_left = 0
	_hold_fraction = 0.0
	_apex_capture_available = false
