class_name HitboxProxy
extends Node3D

@export var manager_path: NodePath
var hitbox_id: int = -1
var weapon_id: StringName
## Identifies one attacker's one move (attacker id + attack serial); Game Feel dedupes on it.
var feedback_burst_id: StringName
@export_flags_3d_physics var collision_mask: int = 1
@export var profile_shape: StringName = &"sphere"
@export var profile_size: Vector3 = Vector3.ONE
@export var linger_ticks: int = 8
@export var decay_curve: PackedFloat32Array = PackedFloat32Array()
@export var hit_spec: HitSpec
@export var owner_combatant: Node
## Actor whose local clock advances this hitbox's trail age. Projectiles use
## themselves; melee proxies default to their owner combatant.
var time_domain_actor: Node
## False for projectiles and other non-melee sources; used by procedural parry presentation.
@export var melee: bool = true
## Only push the transform to the native manager while active (enemy melee: no trails to feed).
@export var track_only_when_active: bool = false

var manager: HitManagerNode
var is_active: bool = false

func _ready() -> void:
	if manager == null and not manager_path.is_empty():
		manager = get_node_or_null(manager_path) as HitManagerNode
	if manager == null:
		return
	hitbox_id = manager.register_hitbox_proxy(self)
	if hitbox_id < 0:
		return
	manager.configure_hitbox(hitbox_id, profile_shape, profile_size, linger_ticks, decay_curve)
	manager.set_hitbox_mask(hitbox_id, collision_mask)
	manager.set_hitbox_transform(hitbox_id, global_transform)

func _physics_process(_delta: float) -> void:
	var _probe := ScriptCostProbe.start()
	_physics_process_body(_delta)
	ScriptCostProbe.stop(&"combat.hitbox_proxy", _probe)

func _physics_process_body(_delta: float) -> void:
	if track_only_when_active and not is_active:
		return
	if manager != null and hitbox_id >= 0:
		manager.set_hitbox_transform(hitbox_id, global_transform)

func _exit_tree() -> void:
	if manager != null and hitbox_id >= 0:
		manager.activate_hitbox(hitbox_id, false)
		manager.unregister_hitbox_proxy(self)

func set_active(value: bool) -> void:
	is_active = value
	if manager != null and hitbox_id >= 0:
		if value and track_only_when_active:
			manager.set_hitbox_transform(hitbox_id, global_transform) # Skipped while idle, so catch up.
		manager.activate_hitbox(hitbox_id, value)

func refresh() -> void:
	if manager != null and hitbox_id >= 0:
		manager.refresh(hitbox_id)

func discard_trails() -> void:
	if manager != null and hitbox_id >= 0:
		manager.discard_hitbox_trails(hitbox_id)

func local_time_actor() -> Node:
	if time_domain_actor != null and is_instance_valid(time_domain_actor):
		return time_domain_actor
	return owner_combatant if owner_combatant != null and is_instance_valid(owner_combatant) else null
