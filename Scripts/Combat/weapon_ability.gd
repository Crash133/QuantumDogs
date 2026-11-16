@tool
class_name WeaponAbility
extends Resource

## Config for a weapon special. Subclasses add exported tuning, check it in
## validate() and build their per-equip state in create_runtime().

func validate(_weapon: WeaponData) -> Array[String]:
	return []

func create_runtime(_context: WeaponAbilityContext) -> WeaponAbilityRuntime:
	return WeaponAbilityRuntime.new()
