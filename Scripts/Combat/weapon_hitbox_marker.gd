@tool
class_name WeaponHitboxMarker
extends Node3D

## Stable marker_id referenced by HitSpec placement. The evaluated basis is
## orthonormalized before applying world-unit hitbox dimensions.
@export var marker_id: StringName
