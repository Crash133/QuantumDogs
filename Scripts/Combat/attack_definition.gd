class_name AttackDefinition
extends Resource

@export var attack_name: StringName
@export var animation_name: StringName

@export_category("Combat")
@export var damage: float = 10.0
@export var hitstun: float = 0.2
@export var knockback: float = 2.0

@export_category("Combo")
@export var next_light: AttackDefinition
@export var next_heavy: AttackDefinition

@export_category("Hitboxes")
@export var hitboxes: Array[AttackHitboxData] = []
