class_name AttackPresentationCatalog
extends Resource

## Per-move cue data. A move-specific profile wins over the weapon default
## (move_id empty); an unknown weapon resolves to null (no cues, no error).
@export var profiles: Array[AttackPresentationProfile] = []
## Other AttackPresentationCatalogs searched after this one (one per weapon).
## Typed as Resource: a script typing its own class leaks at exit (GDScript
## self-reference cycle).
@export var includes: Array[Resource] = []

func resolve(weapon_id: StringName, move_id: StringName) -> AttackPresentationProfile:
	var exact := _find(weapon_id, move_id)
	return exact if exact != null else _find(weapon_id, &"")

func _find(weapon_id: StringName, move_id: StringName) -> AttackPresentationProfile:
	for profile in profiles:
		if profile != null and profile.weapon_id == weapon_id and profile.move_id == move_id:
			return profile
	for catalog in includes:
		if catalog != null and catalog.has_method(&"_find"):
			var found: AttackPresentationProfile = catalog.call(&"_find", weapon_id, move_id)
			if found != null:
				return found
	return null
