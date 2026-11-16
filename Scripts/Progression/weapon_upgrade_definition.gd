class_name WeaponUpgradeDefinition
extends Resource

@export var upgrade_id: StringName
@export var family_id: StringName
@export var level: int = 1
@export var eligible_weapon_ids: Array[StringName] = []
@export var prerequisite_upgrade_id: StringName
@export var modifier_data: Dictionary = {}
