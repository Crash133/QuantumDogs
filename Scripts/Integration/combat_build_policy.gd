class_name CombatBuildPolicy
extends Resource

## Per-level absolute factors/additions. Values are authored only after D1.
@export var stat_values: Dictionary = {}
## Per-upgrade scalar modifiers. Production entries are gated by D2.
@export var upgrade_values: Dictionary = {}
