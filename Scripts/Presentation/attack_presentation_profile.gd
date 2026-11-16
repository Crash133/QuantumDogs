class_name AttackPresentationProfile
extends Resource

## Presentation cue data for one weapon move (or a weapon default when move_id
## is empty). Cue IDs are semantic: the feedback director's catalog maps
## (cue_id, variant_id) to VFX/SFX. Never describes a hit.
@export var weapon_id: StringName
## ComboNode.id; empty = default for every move of weapon_id.
@export var move_id: StringName
@export var start_cue: StringName = &"attack_start"
@export var trail_cue: StringName = &"attack_trail"
@export var end_cue: StringName = &"attack_end"
## Selects the shape family/move look in the director's catalog.
@export var variant_id: StringName
## Trail span in node ticks. (-1, -1) = derive from the live node's HitSpecs,
## so presentation cannot drift from combat data.
@export var active_ticks: Vector2i = Vector2i(-1, -1)
## Where effects attach: weapon_tip, weapon_hand, body or muzzle.
@export var anchor: StringName = &"weapon_tip"
## 0..1 visual weight for the profile (width/brightness/volume scaling).
@export_range(0.0, 1.0) var potency: float = 0.5

func trail_ticks(node: ComboNode) -> Vector2i:
	if active_ticks.x >= 0:
		return active_ticks
	var span := Vector2i(-1, -1)
	if node == null:
		return span
	for spec in node.hit_specs:
		if spec == null:
			continue
		span.x = spec.active_ticks.x if span.x < 0 else mini(span.x, spec.active_ticks.x)
		span.y = maxi(span.y, spec.active_ticks.y)
	return span
