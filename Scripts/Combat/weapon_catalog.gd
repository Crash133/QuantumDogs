class_name WeaponCatalog
extends RefCounted

const WEAPON_PATHS: Array[String] = [
	"res://Assets/Weapons/mantis_blades.tres",
	"res://Assets/Weapons/rocket_lance.tres",
	"res://Assets/Weapons/saber.tres",
	"res://Assets/Weapons/greatsword.tres",
]

static func create_default_weapons() -> Array[WeaponData]:
	var weapons: Array[WeaponData] = []
	for path in WEAPON_PATHS:
		weapons.append(load(path) as WeaponData)
	return weapons
