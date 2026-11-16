@tool
class_name WeaponPoses
extends Resource

## Non-attack clips on a weapon's own character rig. Empty means "no clip".
@export var idle: StringName
@export var run: StringName
@export var jump_start: StringName
@export var jump_idle: StringName
@export var jump_end: StringName
@export var block: StringName
@export var parry: StringName
@export var hit: StringName
## One-shot played when switching to this weapon on the ground. Empty = go straight to idle.
@export var equip: StringName

const KEYS: Array[StringName] = [&"idle", &"run", &"jump_start", &"jump_idle", &"jump_end", &"block", &"parry", &"hit", &"equip"]

func clip(key: StringName) -> StringName:
	return get(key) if key in KEYS else &""
