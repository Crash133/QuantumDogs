class_name FeedbackRequest
extends RefCounted

## A presentation request, never a gameplay command. Producers fill what they
## know; everything except `cue_id` is optional. Handlers receive the same
## object and must not keep it past the call.

const VERSION := 1

## Semantic cue, for example routine_hit, heavy_hit, parry, execution, attack_start, head_light.
var cue_id: StringName
## Optional weapon/move/role variant such as saber, rocket_lance/fire or common.
var variant_id: StringName
var source: Object
var target: Object
var weapon_id: StringName
var role_id: StringName
## 0..1 strength carried from the resolved hit.
var potency: float = 1.0
## Dedupes one burst or phase across contacts (attack serial, warning owner...).
var correlation_key: StringName
## Level generation this request belongs to; stale generations are dropped.
var generation: int = -1
## Optional phase for attack cues (start, trail, end).
var phase: StringName
var direction: Vector3 = Vector3.ZERO
## Optional look overrides read by effects that implement configure_from_request
## (slash traces: core_color, edge_color, sweep_seconds, fade_seconds).
## Presentation only.
var visual: Dictionary = {}

var _has_position: bool = false
var _position: Vector3 = Vector3.ZERO
var _has_endpoint: bool = false
var _endpoint: Vector3 = Vector3.ZERO
var _has_world_transform: bool = false
var _world_transform: Transform3D = Transform3D.IDENTITY

func is_valid() -> bool:
	return not cue_id.is_empty()

func set_world_position(value: Vector3) -> void:
	_has_position = value.is_finite()
	_position = value if _has_position else Vector3.ZERO

## Far end of a trace (the Revolver's resolved shot endpoint); the position is its origin.
func set_world_endpoint(value: Vector3) -> void:
	_has_endpoint = value.is_finite()
	_endpoint = value if _has_endpoint else Vector3.ZERO

func has_world_endpoint() -> bool:
	return _has_endpoint

func world_endpoint() -> Vector3:
	return _endpoint

func set_world_transform(value: Transform3D) -> void:
	_has_world_transform = value.origin.is_finite() and value.basis.x.is_finite() and value.basis.y.is_finite() and value.basis.z.is_finite()
	_world_transform = value if _has_world_transform else Transform3D.IDENTITY

func has_world_transform() -> bool:
	return _has_world_transform

func world_transform() -> Transform3D:
	return _world_transform

func has_world_position() -> bool:
	return _has_position

func has_live_target() -> bool:
	return target != null and is_instance_valid(target)

## Explicit position, else the live target's visual centre, else the origin.
func resolve_position() -> Vector3:
	if _has_position:
		return _position
	if has_live_target() and target is Node3D and (target as Node3D).is_inside_tree():
		var node := target as Node3D
		return node.global_position + Vector3(0.0, 0.9 if node.has_method("get_combat_facing") else 0.0, 0.0)
	if has_live_target() and target is Node3D:
		return (target as Node3D).position
	return Vector3.ZERO
