class_name StageContext
extends Resource

## Treat as an immutable request snapshot. Owners receive deep copies.
@export var run_seed: int
@export var ascent_depth: int
@export var mode: StringName
@export var band: StringName
@export var difficulty_parameters: Dictionary = {}
@export var arena_profile: Resource
@export var encounter: Resource
