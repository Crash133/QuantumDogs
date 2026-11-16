class_name CombatHitAdapter
extends Node

signal shot_resolved(origin: Vector3, endpoint: Vector3, target: Object, hit: HitData)
## Presentation-only trace lifecycle. Pose samples mirror the native hitbox's
## submitted transforms while active; these signals carry no gameplay authority.
signal swing_started(correlation_key: StringName, pose: Transform3D, profile_shape: StringName, profile_size: Vector3, spec: HitSpec, weapon: WeaponData, serial: int)
signal swing_updated(correlation_key: StringName, pose: Transform3D)
signal swing_ended(correlation_key: StringName)

@export var manager_path: NodePath
@export var combatant_path: NodePath = NodePath("..")
@export_flags_3d_physics var ranged_collision_mask: int = 1
@export var ranged_aim_cone_degrees: float = 15.0

var manager: HitManagerNode
var combatant: Node
var controller: CombatController
var hitbox: HitboxProxy
var player_hurtbox: HurtboxProxy
var abilities: WeaponAbilityHost
var weapon_rig: WeaponRigPresentation
var _active_node: ComboNode
var _attack_serial: int = -1
var _node_hitboxes: Array[HitboxProxy] = []
var _retired: Array[Dictionary] = []
var _last_refresh_ticks: Dictionary = {}
var _active_swing_keys: Dictionary[int, StringName] = {}
var _warned_missing_markers: Dictionary[StringName, bool] = {}

func _enter_tree() -> void:
	# Animation/pose writers run at the default priority; native submissions follow them.
	process_physics_priority = 8

func _ready() -> void:
	combatant = get_node_or_null(combatant_path)
	controller = combatant.get_node_or_null("CombatController") as CombatController if combatant != null else null
	weapon_rig = combatant.get_node_or_null("WeaponRigPresentation") as WeaponRigPresentation if combatant != null else null
	if not manager_path.is_empty():
		manager = get_node_or_null(manager_path) as HitManagerNode
	else:
		manager = get_tree().get_first_node_in_group("combat_hit_managers") as HitManagerNode
	if manager == null or combatant == null or controller == null:
		return
	_create_hitbox()

func bind(manager_node: HitManagerNode, combatant_node: Node, combat_controller: CombatController) -> void:
	manager = manager_node
	combatant = combatant_node
	controller = combat_controller
	weapon_rig = combatant_node.get_node_or_null("WeaponRigPresentation") as WeaponRigPresentation if combatant_node != null else null
	_create_hitbox()

func _create_hitbox() -> void:
	if manager == null or combatant == null or controller == null or hitbox != null:
		return
	hitbox = _new_proxy()
	if combatant is Player:
		player_hurtbox = HurtboxProxy.new()
		player_hurtbox.name = "PlayerHurtboxProxy"
		player_hurtbox.combatant = combatant
		player_hurtbox.manager = manager
		player_hurtbox.use_combat_center = true
		var body_scale: float = (combatant as Player).body_scale
		player_hurtbox.position = Vector3.UP * body_scale
		# Layer 1 receives player melee/Revolver; layer 2 receives incoming hits.
		# Match the movement capsule with a slightly forgiving combat volume.
		player_hurtbox.layer = 2
		var player := combatant as Player
		player_hurtbox.height = player.combat_hurtbox_height_scale * body_scale
		player_hurtbox.radius = player.combat_hurtbox_radius_scale * body_scale
		add_child(player_hurtbox)
	abilities = WeaponAbilityHost.new()
	add_child(abilities)
	abilities.setup(controller, combatant, manager)
	controller.weapon_ability_host = abilities
	if not controller.revolver_shot_requested.is_connected(_on_revolver_shot_requested):
		controller.revolver_shot_requested.connect(_on_revolver_shot_requested)

func _on_revolver_shot_requested(origin: Vector3, direction: Vector3) -> void:
	var preferred: Object
	if controller.targeting_service != null:
		preferred = controller.targeting_service.locked_target
	var contact := manager.raycast(origin, direction, controller.tuning.lock_range, ranged_aim_cone_degrees, ranged_collision_mask, preferred)
	var target: Object = contact.get(&"combatant")
	var hit: HitData
	if target != null:
		var spec := HitSpec.new()
		spec.damage = controller.ranged_weapon.damage
		spec.heat = controller.ranged_weapon.heat
		hit = manager.resolver.resolve_contact(spec, 1.0, combatant, target, controller.battery, &"revolver")
	var events := get_node_or_null("/root/CombatEvents") if is_inside_tree() else combatant.get_node_or_null("/root/CombatEvents")
	if events != null:
		events.revolver_fired.emit(target, hit)
	var endpoint: Vector3 = contact.get(&"position", origin + direction.normalized() * controller.tuning.lock_range)
	shot_resolved.emit(origin, endpoint, target, hit)

func _new_proxy() -> HitboxProxy:
	var proxy := HitboxProxy.new()
	proxy.name = "CombatHitboxProxy"
	proxy.position = Vector3(0.0, 1.0, -0.9)
	proxy.owner_combatant = combatant
	proxy.manager = manager
	# In _ready the actor is still adding its scene children. Own proxies here
	# rather than adding a sibling to that busy parent; Node3D inherits the actor.
	var proxy_parent: Node = self if is_inside_tree() else combatant
	proxy_parent.add_child(proxy)
	if proxy.hitbox_id < 0:
		proxy.queue_free()
		return null
	return proxy

func _physics_process(_delta: float) -> void:
	var _probe := ScriptCostProbe.start()
	_physics_process_body(_delta)
	ScriptCostProbe.stop(&"combat.hit_adapter", _probe)

func _physics_process_body(_delta: float) -> void:
	if manager == null or controller == null:
		return
	_step_retired()
	var node := controller.combo.current_node
	if node != _active_node or controller.combo.attack_serial != _attack_serial:
		_retire_node_hitboxes()
		_active_node = node
		_attack_serial = controller.combo.attack_serial
		if node != null:
			for spec in node.hit_specs:
				if spec == null:
					continue
				var proxy: HitboxProxy
				if is_instance_valid(hitbox) and hitbox.hit_spec == null:
					proxy = hitbox
				else:
					proxy = _new_proxy()
				if proxy == null:
					continue
				_configure_spec(proxy, spec)
				_node_hitboxes.append(proxy)
				manager.refresh(proxy.hitbox_id)
			if not _node_hitboxes.is_empty():
				hitbox = _node_hitboxes[0]
	var node_tick := controller.combo.node_tick
	for proxy in _node_hitboxes:
		var spec := proxy.hit_spec
		var pose_available := _update_proxy_pose(proxy)
		var should_be_active := pose_available and spec.is_active_at_tick(node_tick)
		if should_be_active and not proxy.is_active:
			var weapon := controller.combo.weapon as WeaponData
			var serial: int = controller.combo.attack_serial
			var correlation_key := _make_swing_key(proxy, weapon, serial)
			_active_swing_keys[proxy.hitbox_id] = correlation_key
			swing_started.emit(correlation_key, proxy.global_transform, proxy.profile_shape, proxy.profile_size, spec, weapon, serial)
		elif should_be_active:
			var active_key: StringName = _active_swing_keys.get(proxy.hitbox_id, _make_swing_key(proxy, controller.combo.weapon as WeaponData, controller.combo.attack_serial))
			swing_updated.emit(active_key, proxy.global_transform)
		elif proxy.is_active:
			var ended_key: StringName = _active_swing_keys.get(proxy.hitbox_id, &"")
			if not ended_key.is_empty():
				swing_ended.emit(ended_key)
			_active_swing_keys.erase(proxy.hitbox_id)
		proxy.set_active(should_be_active)
		if node_tick in spec.refresh_ticks and _last_refresh_ticks.get(proxy.hitbox_id, -1) != node_tick:
			manager.refresh(proxy.hitbox_id)
			_last_refresh_ticks[proxy.hitbox_id] = node_tick
	abilities.tick(node, node_tick, _node_hitboxes)

func _make_swing_key(proxy: HitboxProxy, weapon: WeaponData, serial: int) -> StringName:
	var weapon_id: StringName = weapon.id if weapon != null else &"unknown"
	return StringName("slash:%d:%s:%d" % [serial, weapon_id, proxy.hitbox_id])

func _update_proxy_pose(proxy: HitboxProxy) -> bool:
	if not combatant is Node3D:
		return false
	var spec := proxy.hit_spec
	if spec == null:
		return false
	var marker: Node3D
	if spec.placement == HitSpec.Placement.WEAPON_MARKER:
		marker = weapon_rig.get_hitbox_marker(spec.marker_id) if weapon_rig != null else null
		if not is_instance_valid(marker):
			if not _warned_missing_markers.has(spec.marker_id):
				_warned_missing_markers[spec.marker_id] = true
				push_warning("CombatHitAdapter [%s]: HitSpec requires missing weapon marker '%s'; hitbox disabled" % [controller.combo.weapon.id if controller.combo.weapon != null else &"unknown", spec.marker_id])
			return false
	var actor_pose := Transform3D.IDENTITY
	if spec.placement == HitSpec.Placement.ACTOR:
		var direction := controller.attack_direction.normalized()
		if direction.is_zero_approx():
			direction = Vector3.FORWARD
		var up := Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.999 else Vector3.UP
		# Attacks start at the attacker's chest; forward reach stays world-unit tuning.
		var chest := Vector3.UP * ((combatant as Player).body_scale if combatant is Player else 1.0)
		actor_pose = Transform3D(Basis.looking_at(direction, up), combatant.global_position + chest + direction * 0.9)
	var placement := resolve_placement_pose(spec, actor_pose, marker)
	if not bool(placement[&"available"]):
		return false
	proxy.global_transform = placement[&"transform"]
	# Adapter priority is intentionally after animation. Submit directly here so
	# the manager's later physics step cannot consume the previous marker pose.
	manager.set_hitbox_transform(proxy.hitbox_id, proxy.global_transform)
	return true

## Resolve world placement while stripping art scale before offsets and native
## world-unit dimensions are applied. A missing marker fails closed.
static func resolve_placement_pose(spec: HitSpec, actor_pose: Transform3D, marker: Node3D = null) -> Dictionary:
	if spec == null:
		return {&"available": false, &"transform": Transform3D.IDENTITY}
	var base := actor_pose
	if spec.placement == HitSpec.Placement.WEAPON_MARKER:
		if not is_instance_valid(marker):
			return {&"available": false, &"transform": Transform3D.IDENTITY}
		base = Transform3D(marker.global_basis.orthonormalized(), marker.global_position)
	else:
		base = Transform3D(actor_pose.basis.orthonormalized(), actor_pose.origin)
	var evaluated := base * spec.local_pose
	return {&"available": true, &"transform": Transform3D(evaluated.basis.orthonormalized(), evaluated.origin)}

func _retire_node_hitboxes() -> void:
	var handoff := _active_node != null and controller != null and controller.combo.current_node != null
	var force_discard_trails := controller != null and controller.state in [CombatController.State.EXECUTING, CombatController.State.STAGGERED, CombatController.State.DEAD]
	var legacy_trail_behavior := controller != null and controller.combo.weapon != null and controller.combo.weapon.graph != null and controller.combo.weapon.graph.schema_version == 0
	for proxy in _node_hitboxes:
		if force_discard_trails or (handoff and proxy.hit_spec != null and not proxy.hit_spec.survive_transition and not legacy_trail_behavior):
			manager.discard_hitbox_trails(proxy.hitbox_id)
		var key: StringName = _active_swing_keys.get(proxy.hitbox_id, &"")
		if proxy.is_active and not key.is_empty():
			swing_ended.emit(key)
		_active_swing_keys.erase(proxy.hitbox_id)
		proxy.set_active(false)
		_retired.append({&"proxy": proxy, &"ticks": clampi(proxy.linger_ticks, 0, 256) + 2})
	if force_discard_trails:
		for entry in _retired:
			var retired_proxy: HitboxProxy = entry[&"proxy"]
			if is_instance_valid(retired_proxy):
				manager.discard_hitbox_trails(retired_proxy.hitbox_id)
	_node_hitboxes.clear()
	_last_refresh_ticks.clear()

func _step_retired() -> void:
	for index in range(_retired.size() - 1, -1, -1):
		var entry := _retired[index]
		entry[&"ticks"] -= 1
		if int(entry[&"ticks"]) > 0:
			continue
		var proxy: HitboxProxy = entry[&"proxy"]
		if is_instance_valid(proxy):
			if hitbox == proxy:
				hitbox = null
			proxy.queue_free()
		_retired.remove_at(index)

## One id per attacker and move (attack serial); shared by all of the move's hitboxes.
static func burst_id(attacker: Object, serial: int) -> StringName:
	return StringName("%d:%d" % [attacker.get_instance_id() if attacker != null else 0, serial])

func _configure_spec(hitbox: HitboxProxy, spec: HitSpec) -> void:
	hitbox.hit_spec = spec
	hitbox.feedback_burst_id = burst_id(combatant, controller.combo.attack_serial)
	hitbox.weapon_id = controller.combo.weapon.id
	var profile: HitboxProfile = controller.combo.weapon.hitbox_profiles.get(spec.profile)
	if profile != null:
		var native := profile.to_native()
		hitbox.profile_shape = native[&"shape"]
		hitbox.profile_size = native[&"size"]
	hitbox.linger_ticks = clampi(hitbox.hit_spec.linger_ticks, 0, 256)
	hitbox.decay_curve = _make_decay_curve(hitbox.hit_spec)
	manager.configure_hitbox(hitbox.hitbox_id, hitbox.profile_shape, hitbox.profile_size, hitbox.linger_ticks, hitbox.decay_curve)

func _make_decay_curve(spec: HitSpec) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	var sample_count := clampi(spec.linger_ticks + 1, 2, 257)
	for age in range(sample_count):
		var normalized_age := float(age) / float(sample_count - 1)
		samples.append(1.0 - 0.7 * normalized_age if spec.decay == null else spec.decay.sample(normalized_age))
	return samples
