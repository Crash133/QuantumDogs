class_name HitManagerNode
extends Node

signal native_step_finished(elapsed_usec: int, contact_count: int)
signal contact_step_finished(native_usec: int, total_usec: int, contact_count: int)

var native_manager: NativeHitManager
var hitboxes: Dictionary = {}
var hurtboxes: Dictionary = {}
var resolver: HitResolver = HitResolver.new()
var completed_steps: int = 0
var _next_hitbox_id: int = 1
var _action_leases: Node
var _time_domains: Node
var _last_global_step_delta: float = 0.0
var _last_actor_tick_deltas: Dictionary[int, float] = {}

func _enter_tree() -> void:
	add_to_group("combat_hit_managers")
	process_physics_priority = 10

func _ready() -> void:
	_action_leases = get_tree().get_first_node_in_group("combat_action_leases") as Node
	_time_domains = get_tree().get_first_node_in_group("combat_time_domains") as Node
	native_manager = NativeHitManager.new()
	if not native_manager.is_ready():
		push_error("HitManager GDExtension failed to load; stopping combat runtime")
		get_tree().quit(1)

func register_hurtbox_proxy(proxy: HurtboxProxy) -> int:
	if not native_manager.is_ready():
		return -1
	var id := native_manager.register_hurtbox(proxy.native_base_position(), proxy.radius, proxy.height, proxy.layer)
	if id < 0:
		return -1
	hurtboxes[id] = proxy
	return id

func unregister_hurtbox(id: int) -> void:
	if native_manager != null:
		native_manager.unregister_hurtbox(id)
	hurtboxes.erase(id)

func update_hurtboxes(ids: PackedInt32Array, positions: PackedVector3Array) -> void:
	if native_manager != null:
		native_manager.update_hurtboxes(ids, positions)

func configure_hitbox(id: int, shape: StringName, size: Vector3, linger_ticks: int, decay_curve: PackedFloat32Array) -> void:
	if native_manager != null:
		native_manager.configure_hitbox(id, shape, size, linger_ticks, decay_curve)

func set_hitbox_mask(id: int, mask: int) -> void:
	if native_manager != null:
		native_manager.set_hitbox_mask(id, mask)

func unregister_hitbox_proxy(proxy: HitboxProxy) -> void:
	if proxy == null:
		return
	if native_manager != null:
		native_manager.unregister_hitbox(proxy.hitbox_id)
	hitboxes.erase(proxy.hitbox_id)

func activate_hitbox(id: int, active: bool) -> void:
	if native_manager != null:
		native_manager.activate_hitbox(id, active)

func set_hitbox_transform(id: int, transform: Transform3D) -> void:
	if native_manager != null:
		native_manager.set_hitbox_transform(id, transform)

func refresh(id: int) -> void:
	if native_manager != null:
		native_manager.refresh(id)

## Remove lingering poses while preserving the hit-once set and current state.
func discard_hitbox_trails(id: int) -> void:
	if native_manager != null:
		native_manager.discard_hitbox_trails(id)

func register_hitbox_proxy(proxy: HitboxProxy) -> int:
	if hitboxes.size() >= 1024:
		push_warning("Combat hitbox registry is full (1024)")
		return -1
	var id := _next_hitbox_id
	_next_hitbox_id += 1
	hitboxes[id] = proxy
	return id

## Cancel damaging melee volumes owned by enemies when an execution lease begins.
## Projectiles and authored attack-enable settings are left untouched.
func clear_enemy_melee_attacks() -> void:
	for id in hitboxes.keys():
		var proxy: HitboxProxy = hitboxes.get(id)
		if not is_instance_valid(proxy) or not proxy.melee:
			continue
		var owner := proxy.owner_combatant
		if not is_instance_valid(owner) or not owner.is_in_group("enemy_combatants"):
			continue
		proxy.set_active(false)
		proxy.discard_trails()

## Return actor-local seconds for one global physics interval. Projectile
## transport calls this before moving so pose advance and native trail aging
## use the same local-time source.
func local_delta_for(actor: Node, global_delta: float) -> float:
	if not is_finite(global_delta) or global_delta <= 0.0:
		return 0.0
	var factor := _time_factor_for(actor)
	return global_delta * factor

## Authored 60 Hz lifetime ticks elapsed for this actor in the last native batch.
func local_tick_delta_for(actor: Node) -> float:
	if actor == null or not is_instance_valid(actor):
		return _last_global_step_delta * 60.0
	return float(_last_actor_tick_deltas.get(actor.get_instance_id(), _last_global_step_delta * 60.0))

func _time_factor_for(actor: Node) -> float:
	if actor == null or not is_instance_valid(actor):
		return 1.0
	if is_instance_valid(_time_domains) and _time_domains.has_method("factor_for"):
		return clampf(float(_time_domains.call("factor_for", actor)), 0.01, 1.0)
	return 1.0

func _physics_process(delta: float) -> void:
	var _probe := ScriptCostProbe.start()
	_physics_process_body(delta)
	ScriptCostProbe.stop(&"combat.hit_manager", _probe)

func _physics_process_body(delta: float) -> void:
	if native_manager == null or not native_manager.is_ready():
		return
	_last_global_step_delta = maxf(0.0, delta)
	_last_actor_tick_deltas.clear()
	var callback_started := Time.get_ticks_usec()
	_submit_hurtboxes()
	var age_ids := PackedInt32Array()
	var age_deltas := PackedFloat32Array()
	for id in hitboxes.keys():
		var proxy: HitboxProxy = hitboxes.get(id)
		if not is_instance_valid(proxy):
			continue
		var actor := proxy.local_time_actor()
		var factor := _time_factor_for(actor)
		var local_tick_delta := maxf(0.0, delta) * 60.0 * factor
		age_ids.append(int(id))
		age_deltas.append(local_tick_delta)
		if actor != null and is_instance_valid(actor):
			_last_actor_tick_deltas[actor.get_instance_id()] = local_tick_delta
	var started_usec := Time.get_ticks_usec()
	var contacts := native_manager.step_with_ages(age_ids, age_deltas)
	var native_usec := Time.get_ticks_usec() - started_usec
	completed_steps += 1
	native_step_finished.emit(native_usec, contacts.size())
	for contact in contacts:
		var hitbox: HitboxProxy = hitboxes.get(int(contact.hitbox_id))
		var hurtbox: HurtboxProxy = hurtboxes.get(int(contact.hurtbox_id))
		if hitbox == null or hurtbox == null or hitbox.hit_spec == null:
			push_warning("Dropped unresolved native contact: hitbox %s, hurtbox %s" % [contact.hitbox_id, contact.hurtbox_id])
			continue
		if is_instance_valid(_action_leases) and _action_leases.has_method("is_protected") and bool(_action_leases.call("is_protected", hurtbox.combatant)):
			continue
		var context := snapshot_contact(hitbox, hurtbox, contact)
		var attack_basis: Basis = context.hitbox_transform.basis if context.has_hitbox_transform else hitbox.global_basis
		resolver.resolve_contact(hitbox.hit_spec, float(contact.potency), hitbox.owner_combatant, hurtbox.combatant, null, hitbox.weapon_id, attack_basis, hitbox.feedback_burst_id, context)
	contact_step_finished.emit(native_usec, Time.get_ticks_usec() - callback_started, contacts.size())

## Capture the submitted native geometry before resolver defense can unregister
## the attacker. native_contact.position is the engine's actual shape contact.
func snapshot_contact(hitbox: HitboxProxy, _hurtbox: HurtboxProxy, native_contact: Dictionary = {}) -> HitContactContext:
	var context := HitContactContext.new()
	if hitbox == null or not is_instance_valid(hitbox):
		return context
	context.attack_id = hitbox.feedback_burst_id
	context.hitbox_id = hitbox.hitbox_id
	context.set_attacker(hitbox.owner_combatant)
	var pose: Variant = native_contact.get(&"transform")
	if pose is Transform3D:
		context.hitbox_transform = pose
		context.has_hitbox_transform = true
	var previous_pose: Variant = native_contact.get(&"previous_transform")
	if previous_pose is Transform3D:
		context.hitbox_previous_transform = previous_pose
		context.has_previous_hitbox_transform = true
	context.swept = bool(native_contact.get(&"swept", false))
	context.trail_age = int(native_contact.get(&"trail_age", 0))
	context.profile_shape = hitbox.profile_shape
	context.profile_size = hitbox.profile_size
	context.physics_tick = completed_steps
	context.melee = hitbox.melee
	var point: Variant = native_contact.get(&"position")
	if point is Vector3 and point.is_finite():
		context.world_point = point
		context.has_world_point = true
	return context

func raycast(origin: Vector3, direction: Vector3, distance: float, cone_degrees: float, mask: int, preferred: Object = null) -> Dictionary:
	if native_manager == null or not native_manager.is_ready():
		return {}
	_submit_hurtboxes()
	var preferred_id := -1
	for id in hurtboxes:
		if hurtboxes[id].combatant == preferred:
			preferred_id = id
			break
	var contact := native_manager.raycast(origin, direction, distance, cone_degrees, mask, preferred_id)
	if contact.is_empty():
		return {}
	var proxy: HurtboxProxy = hurtboxes.get(int(contact.hurtbox_id))
	if not is_instance_valid(proxy) or not is_instance_valid(proxy.combatant):
		push_warning("Dropped unresolved native ray contact")
		return {}
	contact[&"combatant"] = proxy.combatant
	return contact

func _submit_hurtboxes() -> void:
	var ids := PackedInt32Array()
	var positions := PackedVector3Array()
	for id in hurtboxes.keys():
		var proxy: HurtboxProxy = hurtboxes[id]
		if not is_instance_valid(proxy) or not is_instance_valid(proxy.combatant) or (proxy.combatant.has_method("is_alive") and not proxy.combatant.is_alive()):
			unregister_hurtbox(id)
			if is_instance_valid(proxy):
				proxy.native_id = -1
			continue
		ids.append(id)
		positions.append(proxy.native_base_position())
	native_manager.update_hurtboxes(ids, positions)

