class_name CombatProjectile
extends HitboxProxy

var ticks_left: float = 0.0
var born_after_step: int = 0
var velocity: Vector3 = Vector3.ZERO

func _ready() -> void:
	top_level = true
	melee = false
	visible = false
	set_physics_process(false)

func launch(hit_manager: HitManagerNode, data: CombatProjectileData, pose: Transform3D, source: Node, identity: StringName) -> bool:
	recycle()
	manager = hit_manager
	global_transform = pose
	owner_combatant = source
	time_domain_actor = source
	melee = false
	weapon_id = identity
	# Snapshot resolution data: later tuning/weapon changes cannot rewrite an
	# already launched attack. Projectiles have no lingering trail or refresh.
	hit_spec = data.hit_spec.duplicate(true) as HitSpec
	profile_shape = StringName(data.profile_shape)
	profile_size = data.profile_size
	collision_mask = data.collision_mask
	linger_ticks = 0
	hitbox_id = manager.register_hitbox_proxy(self)
	if hitbox_id < 0:
		owner_combatant = null
		hit_spec = null
		return false
	manager.configure_hitbox(hitbox_id, profile_shape, profile_size, 0, PackedFloat32Array([1.0]))
	manager.set_hitbox_mask(hitbox_id, collision_mask)
	# A fresh registration seeds this pose without a sweep from the cached
	# object's previous flight or the pool's origin.
	manager.set_hitbox_transform(hitbox_id, global_transform)
	ticks_left = data.lifetime_ticks
	born_after_step = manager.completed_steps
	velocity = -pose.basis.z.normalized() * data.speed
	set_active(true)
	visible = true
	set_physics_process(true)
	return true

func _physics_process(delta: float) -> void:
	if not is_active:
		return
	if not is_instance_valid(manager) or not is_instance_valid(owner_combatant):
		recycle()
		return
	var local_delta := manager.local_delta_for(time_domain_actor, delta)
	global_position += velocity * local_delta
	manager.set_hitbox_transform(hitbox_id, global_transform)

func set_active(value: bool) -> void:
	if not value:
		recycle()
	elif hitbox_id >= 0:
		super.set_active(true)

func refresh() -> void:
	push_warning("Combat projectiles cannot refresh a flight's hit set")

func recycle() -> void:
	if is_instance_valid(manager) and hitbox_id >= 0:
		manager.unregister_hitbox_proxy(self)
	hitbox_id = -1
	is_active = false
	ticks_left = 0
	velocity = Vector3.ZERO
	owner_combatant = null
	time_domain_actor = null
	hit_spec = null
	visible = false
	set_physics_process(false)

func _exit_tree() -> void:
	recycle()
