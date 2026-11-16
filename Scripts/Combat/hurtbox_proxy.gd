class_name HurtboxProxy
extends Node3D

# Scene transforms locate the capsule center, matching meshes/combat centers.
# The native schema locates its base; convert only at the adapter boundary.

@export var combatant: Node
@export var manager_path: NodePath
## Capsule radius in world meters. A zero radius is permitted for disabled test
## fixtures; production combatants should use a positive value.
@export_range(0.0, 3.0, 0.01, "suffix:m") var radius: float = 0.6
## Capsule total height in world meters. Values below twice the radius behave
## like a capsule with a zero-length center segment.
@export_range(0.0, 5.0, 0.01, "suffix:m") var height: float = 1.8
@export var layer: int = 1
@export var use_combat_center: bool = false

var manager: HitManagerNode
var native_id: int = -1

func _ready() -> void:
	if manager == null and not manager_path.is_empty():
		manager = get_node_or_null(manager_path) as HitManagerNode
	if manager != null:
		_register()

func _exit_tree() -> void:
	if manager != null and native_id >= 0:
		manager.unregister_hurtbox(native_id)

func _register() -> void:
	native_id = manager.register_hurtbox_proxy(self)

func native_base_position() -> Vector3:
	var center := global_position
	if use_combat_center and is_instance_valid(combatant) and combatant.has_method("get_combat_center"):
		center = combatant.get_combat_center()
	return center - Vector3.UP * maxf(0.0, height) * 0.5
