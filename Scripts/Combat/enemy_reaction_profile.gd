class_name EnemyReactionProfile
extends Resource

## Authored reaction settings for one enemy role. Starting values, not
## playtest-approved balance. Never mutated at runtime.

## Reaction velocity bleeds off at this rate. 0 = never slows down (avoid).
@export_range(0.0, 200.0, 0.1, "suffix:m/s²") var horizontal_deceleration: float = 20.0
## Every accepted horizontal reaction velocity is clamped to this speed.
@export_range(0.0, 50.0, 0.1, "suffix:m/s") var max_horizontal_speed: float = 8.0
## Time spent down after a knockdown or slam landing. 0 = straight to get-up.
@export_range(0.0, 5.0, 0.01, "suffix:s") var knockdown_hold: float = 0.5
## Get-up after the knockdown hold. 0 = acts immediately.
@export_range(0.0, 5.0, 0.01, "suffix:s") var get_up_recovery: float = 0.2
## Downward speed of a slam until it lands.
@export_range(0.0, 50.0, 0.1, "suffix:m/s") var slam_speed: float = 10.0

@export_group("Elite armor")
## Closed armor rejects flinch, launch, knockdown, air hold and displacement
## (never damage or heat). Only the elite profile enables it.
@export var armor_enabled: bool = false
## Opening granted by an armor-interrupting (heavy/finisher) move.
@export_range(0.0, 5.0, 0.01, "suffix:s") var heavy_opening: float = 0.4
## Opening granted by a successful player parry against this enemy.
@export_range(0.0, 5.0, 0.01, "suffix:s") var parry_opening: float = 0.75
## A heavy move cannot open the armor again until this cooldown ends.
@export_range(0.0, 10.0, 0.01, "suffix:s") var heavy_opening_cooldown: float = 1.0
