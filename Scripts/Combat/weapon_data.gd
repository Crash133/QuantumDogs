@tool
class_name WeaponData
extends Resource

@export var id: StringName
@export var display_name: String
@export var scene: PackedScene
@export var contact_profile: WeaponContactProfile
@export var graph: ComboGraph
## HitSpec.profile names a key here.
@export var hitbox_profiles: Dictionary[StringName, HitboxProfile] = {}
@export var character_scene: PackedScene
@export var character_weapon_bone: StringName
## Hand mount: where the weapon's Grip/OrientationGuide frame sits in the hand
## bone's local space (bone units, basis may carry the weapon's display scale).
## Lace's values are fitted from the weapon placement in Assets/Objects/Lace.blend.
@export var character_weapon_transform: Transform3D = Transform3D.IDENTITY
## Dual-wield: WeaponUnit.unit_id -> rig bone. When set, the weapon scene mounts once
## per entry on that bone, keeping only that unit, with its Grip placed on the bone
## (character_weapon_transform is applied on top). Empty = one mount on character_weapon_bone.
@export var character_unit_bones: Dictionary[StringName, StringName] = {}
## Dual-wield: WeaponUnit.unit_id -> its own hand mount (same meaning as
## character_weapon_transform). Units missing here use character_weapon_transform.
@export var character_unit_transforms: Dictionary[StringName, Transform3D] = {}
## ComboNode.animation -> clip name on character_scene's AnimationPlayer.
@export var animation_aliases: Dictionary[StringName, StringName] = {}
## Jump-attack clips: ComboNode.animation -> clip used when that attack starts
## airborne. Moves missing here play their animation_aliases clip in the air too.
@export var air_animation_aliases: Dictionary[StringName, StringName] = {}
@export var poses: WeaponPoses
@export var fallback_animation: StringName
## Slash trace and projectile colours: the weapon's dominant texture hue,
## brightened (hot core, saturated edge).
@export var trace_core_color: Color = Color(0.78, 0.99, 1.0)
@export var trace_edge_color: Color = Color(0.1, 0.95, 1.0)
## Weapon specials; see WeaponAbility.
@export var abilities: Array[WeaponAbility] = []

## Empty when the weapon is safe to equip. Runs at controller startup, in GUT
## over the catalog, and when the resource is saved in the editor.
func validate() -> Array[String]:
	var errors: Array[String] = []
	if graph == null:
		errors.append("Weapon %s has no combo graph" % id)
		return errors
	errors.append_array(graph.validate())
	if contact_profile != null:
		if scene == null:
			errors.append("Weapon %s contact profile requires a weapon scene with at least one WeaponUnit" % id)
		else:
			var weapon_root := scene.instantiate()
			var units: Array[WeaponUnit] = []
			if weapon_root == null:
				errors.append("Weapon %s contact profile could not instantiate its weapon scene" % id)
			else:
				if weapon_root is WeaponUnit:
					units.append(weapon_root)
				for candidate in weapon_root.find_children("*", "Node", true, false):
					if candidate is WeaponUnit:
						units.append(candidate)
				errors.append_array(contact_profile.validate(units))
				weapon_root.free()
	var animations: Dictionary = {}
	for combo_node in graph.nodes:
		if combo_node == null:
			continue
		animations[combo_node.animation] = true
		for spec in combo_node.hit_specs:
			if spec == null:
				continue
			var profile: HitboxProfile = hitbox_profiles.get(spec.profile)
			if profile == null:
				errors.append("Node %s uses missing hitbox profile '%s'" % [combo_node.id, spec.profile])
	for key: StringName in hitbox_profiles:
		var profile: HitboxProfile = hitbox_profiles[key]
		if profile == null:
			errors.append("Hitbox profile '%s' is empty" % key)
			continue
		for error in profile.validate():
			errors.append("Hitbox profile '%s': %s" % [key, error])
	for animation: StringName in animation_aliases:
		if not animations.has(animation):
			errors.append("Animation alias '%s' matches no combo node animation" % animation)
	for animation: StringName in air_animation_aliases:
		if not animations.has(animation):
			errors.append("Air animation alias '%s' matches no combo node animation" % animation)
	for ability in abilities:
		if ability == null:
			errors.append("Weapon %s has an empty ability slot" % id)
		else:
			errors.append_array(ability.validate(self))
	return errors

## Hand mount for one WeaponUnit (see character_unit_transforms).
func hand_mount_for(unit_id: StringName) -> Transform3D:
	return character_unit_transforms.get(unit_id, character_weapon_transform)

## Every character_scene clip this weapon can play (attacks, jump attacks, poses,
## fallback). The pose mixer caches only these, since one rig holds all weapons' clips.
func referenced_clips() -> PackedStringArray:
	var clips := PackedStringArray()
	for clip: StringName in animation_aliases.values() + air_animation_aliases.values():
		clips.append(clip)
	if poses != null:
		for key in WeaponPoses.KEYS:
			clips.append(poses.clip(key))
	clips.append(fallback_animation)
	var unique := PackedStringArray()
	for clip in clips:
		if clip != "" and not unique.has(clip):
			unique.append(clip)
	return unique
