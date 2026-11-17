class_name FeedbackDirector
extends Node

## Run-scoped adapter from resolved Combat, Enemy and Style signals to typed
## FeedbackRequests, routed to separate time, camera and VFX handlers.
## It is presentation only: it cannot deal damage, award Style Points, change
## spawns, or own Style rank animation. Every handler runs independently, so a
## missing asset in one never suppresses the others.
##
## Public surface: request(), bind_world(), bind_combat(), bind_style(),
## bind_encounter(), bind_camera(), bind_hit_adapter(), bind_player(), bind_run(),
## set_accessibility(), clear_level(). Handlers expose play(request, profile).

@export_group("Content")
## Cue-to-profile data. Replace or edit it without touching code.
@export var catalog: FeedbackCatalog
## Per-attack presentation cues (swing trails) for the attack observer.
@export var attack_catalog: AttackPresentationCatalog

@export_group("Handlers")
@export var time_handler: FeedbackTimeHandler
@export var camera_handler: FeedbackCameraHandler
@export var vfx_handler: FeedbackVfxHandler
@export var attack_observer: AttackPresentationObserver

@export_group("Tuning")
## After an execution, hit/kill impacts for the same target are skipped this long.
@export_range(0.0, 2.0, 0.05, "suffix:s") var execution_suppress_seconds: float = 0.4
## Warning cue to enemy variant; a role that is not listed uses the cue's default profile.
@export var warning_variants: Dictionary = {&"head_light": &"common", &"camera_glow": &"drone", &"elite_warning": &"elite"}

const RECENT_LIMIT := 64

var _events: Node
var _style: Node
var _generation: int = 0
var _recent: Array[StringName] = []
var _executed_until: Dictionary = {}
var _enemy_links: Dictionary = {}
var _encounter: Node
var _adapter: Node
var _run: Node
var _last_rank: int = 0
var _reduced_motion: bool = false
var _requests: int = 0
var _handled: int = 0

func _ready() -> void:
	# JuiceManager.hit_stop() forwards to the single time owner.
	var juice := get_node_or_null("/root/JuiceManager")
	if juice != null and time_handler != null:
		juice.set(&"time_handler", time_handler)

func generation() -> int:
	return _generation

## Cue ids of every handled request, oldest first (bounded; for tests and tuning).
func recent_cues() -> Array[StringName]:
	return _recent

func stats() -> Dictionary:
	return {&"requests": _requests, &"handled": _handled, &"vfx": vfx_handler.stats() if vfx_handler != null else {}}

## Routes one request to the handlers. Returns true when any handler acted.
func request(feedback: FeedbackRequest, channels: Dictionary = {}) -> bool:
	if feedback == null or not feedback.is_valid() or catalog == null:
		return false
	if feedback.generation >= 0 and feedback.generation != _generation:
		return false # Belongs to a level that has been cleared.
	_requests += 1
	var profile := catalog.resolve(feedback.cue_id, feedback.variant_id)
	if profile == null:
		return false
	var acted := false
	var all_channels := channels.is_empty()
	if (all_channels or bool(channels.get(&"time", false))) and time_handler != null and profile.stop_duration > 0.0:
		acted = time_handler.request_stop(profile.stop_duration, profile.stop_scale, feedback.correlation_key) or acted
	if (all_channels or bool(channels.get(&"camera", false))) and camera_handler != null and profile.camera_trauma > 0.0:
		acted = camera_handler.apply(profile.camera_trauma * clampf(feedback.potency, 0.25, 1.0), feedback.correlation_key) or acted
	if (all_channels or bool(channels.get(&"vfx", false))) and vfx_handler != null:
		acted = vfx_handler.play(feedback, profile) or acted
	_remember(feedback.cue_id)
	_handled += 1
	return acted

func bind_world(world: Node3D) -> void:
	if vfx_handler != null:
		vfx_handler.bind(world)

func bind_camera(rig: CameraRig) -> void:
	if camera_handler != null:
		camera_handler.bind(rig)

func set_accessibility(reduced_motion: bool, flash_strength: float) -> void:
	_reduced_motion = reduced_motion
	for link in _enemy_links.values():
		_apply_bridge_motion(link[&"enemy"])
	if camera_handler != null:
		camera_handler.set_reduced_motion(reduced_motion)
	if vfx_handler != null:
		vfx_handler.set_accessibility(reduced_motion, flash_strength)

func bind_combat(events: Node) -> void:
	_unbind_combat()
	_events = events
	if _events == null:
		return
	for pair in _combat_links():
		if _events.has_signal(pair[0]) and not _events.is_connected(pair[0], pair[1]):
			_events.connect(pair[0], pair[1])

func bind_style(style: Node) -> void:
	_unbind_style()
	_style = style
	if _style == null:
		return
	if _style.has_signal(&"style_points_awarded"):
		_style.connect(&"style_points_awarded", _on_style_award)
	if _style.has_signal(&"style_changed"):
		_style.connect(&"style_changed", _on_style_changed)

func bind_encounter(encounter: Node) -> void:
	_unbind_encounter()
	_encounter = encounter
	if _encounter != null and _encounter.has_signal(&"enemy_spawned"):
		_encounter.connect(&"enemy_spawned", _on_enemy_spawned)

func bind_hit_adapter(adapter: Node) -> void:
	if is_instance_valid(_adapter) and _adapter.is_connected(&"shot_resolved", _on_shot_resolved):
		_adapter.disconnect(&"shot_resolved", _on_shot_resolved)
	if is_instance_valid(_adapter) and _adapter.has_signal(&"swing_started") and _adapter.is_connected(&"swing_started", _on_swing_started):
		_adapter.disconnect(&"swing_started", _on_swing_started)
	if is_instance_valid(_adapter) and _adapter.has_signal(&"swing_updated") and _adapter.is_connected(&"swing_updated", _on_swing_updated):
		_adapter.disconnect(&"swing_updated", _on_swing_updated)
	if is_instance_valid(_adapter) and _adapter.has_signal(&"swing_ended") and _adapter.is_connected(&"swing_ended", _on_swing_ended):
		_adapter.disconnect(&"swing_ended", _on_swing_ended)
	_adapter = adapter
	if _adapter != null and _adapter.has_signal(&"shot_resolved"):
		_adapter.connect(&"shot_resolved", _on_shot_resolved)
	if _adapter != null and _adapter.has_signal(&"swing_started"):
		_adapter.connect(&"swing_started", _on_swing_started)
	if _adapter != null and _adapter.has_signal(&"swing_updated"):
		_adapter.connect(&"swing_updated", _on_swing_updated)
	if _adapter != null and _adapter.has_signal(&"swing_ended"):
		_adapter.connect(&"swing_ended", _on_swing_ended)

## Starts attack-phase cues (swing trails and swing sounds) for this player.
func bind_player(player: Node) -> void:
	if attack_observer == null or attack_catalog == null:
		return
	var controller: Variant = player.get(&"combat_controller") if player != null else null
	if controller == null:
		attack_observer.clear()
		return
	attack_observer.sink = _on_phase_cue
	attack_observer.bind(controller, self, attack_catalog)

## Clears effects and listeners when a level is replaced or the run ends.
func bind_run(run: Node) -> void:
	if is_instance_valid(_run):
		if _run.is_connected(&"level_started", _on_level_started):
			_run.disconnect(&"level_started", _on_level_started)
		if _run.is_connected(&"run_ended", _on_run_ended):
			_run.disconnect(&"run_ended", _on_run_ended)
	_run = run
	if _run != null:
		if _run.has_signal(&"level_started"):
			_run.connect(&"level_started", _on_level_started)
		if _run.has_signal(&"run_ended"):
			_run.connect(&"run_ended", _on_run_ended)

func clear_level() -> void:
	_generation += 1
	_unlink_enemies()
	_executed_until.clear()
	if attack_observer != null:
		attack_observer.clear()
	if vfx_handler != null:
		vfx_handler.clear_level()
	if time_handler != null:
		time_handler.clear()

func _exit_tree() -> void:
	_unbind_combat()
	_unbind_style()
	_unbind_encounter()
	bind_hit_adapter(null)
	bind_run(null)
	_unlink_enemies()

# --- Combat events -------------------------------------------------------

func _combat_links() -> Array:
	return [
		[&"hit_landed", _on_hit_landed],
		[&"parry_contact_presented", _on_parry_contact_presented],
		[&"executed", _on_executed],
		[&"blocked", _on_blocked],
		[&"damage_taken", _on_damage_taken],
		[&"dash_used", _on_dash_used],
		[&"weapon_switched", _on_weapon_switched],
		[&"enemy_killed", _on_enemy_killed],
	]

func _unbind_combat() -> void:
	if not is_instance_valid(_events):
		_events = null
		return
	for pair in _combat_links():
		if _events.has_signal(pair[0]) and _events.is_connected(pair[0], pair[1]):
			_events.disconnect(pair[0], pair[1])
	_events = null

# Signal arguments are Variants so a stale (freed) reference reaches validation
# instead of failing the call: Object-typed parameters reject freed instances.
func _on_hit_landed(hit: Variant, target: Variant) -> void:
	if not hit is HitData or (hit as HitData).feedback_cue_id.is_empty() or not _live(target):
		return
	# A hit on the player is player damage; damage_taken drives that feedback.
	if target.has_method(&"get_battery_meter"):
		return
	if _recently_executed(target):
		return
	hit = hit as HitData
	if hit.reaction_outcome == &"defeated":
		_request_defeat(hit, target)
	# Closed armor still shows the damage, but never the move's flourish.
	var feedback := _new_request(&"armor_hit" if hit.reaction_outcome == &"resisted" else hit.feedback_cue_id)
	feedback.variant_id = hit.weapon_id
	feedback.target = target
	feedback.source = hit.source if _live(hit.source) else null
	feedback.weapon_id = hit.weapon_id
	feedback.potency = hit.potency
	feedback.correlation_key = hit.feedback_burst_id
	request(feedback)

func _on_enemy_killed(_target: Variant, _hit: Variant) -> void:
	# The landed (lethal) hit already produced the impact and defeat burst.
	pass

## One short burst at the target's captured position; never holds the actor.
func _request_defeat(hit: HitData, target: Object) -> void:
	if not target is Node3D or not (target as Node3D).is_inside_tree():
		return
	var feedback := _new_request(&"enemy_defeated")
	var center: Vector3 = target.call(&"get_combat_center") if target.has_method(&"get_combat_center") else (target as Node3D).global_position
	feedback.set_world_position(center)
	feedback.direction = hit.reaction_direction
	feedback.correlation_key = StringName("defeat:%d" % target.get_instance_id())
	request(feedback)

func _on_parry_contact_presented(action_id: int, world_point: Vector3) -> void:
	if not world_point.is_finite():
		return
	var feedback := _new_request(&"parry_contact_fallback" if action_id < 0 else &"parry_contact")
	feedback.set_world_position(world_point)
	feedback.correlation_key = StringName("parry-contact:%d" % action_id)
	request(feedback)

func _on_executed(target: Variant) -> void:
	if _live(target):
		_executed_until[target.get_instance_id()] = Time.get_ticks_msec() + int(execution_suppress_seconds * 1000.0)
	var feedback := _new_request(&"execution")
	feedback.target = target if _live(target) else null
	feedback.correlation_key = StringName("execution:%d" % Engine.get_physics_frames())
	request(feedback)

func _on_blocked(attacker: Variant) -> void:
	var feedback := _new_request(&"block")
	feedback.target = attacker if _live(attacker) else null
	request(feedback)

func _on_damage_taken(_amount: float, source: Variant) -> void:
	var feedback := _new_request(&"player_hurt")
	feedback.source = source if _live(source) else null
	feedback.correlation_key = StringName("hurt:%d" % Engine.get_physics_frames())
	request(feedback)

func _on_dash_used(_charges_left: int) -> void:
	request(_new_request(&"dash"))

func _on_weapon_switched(_previous: StringName, current: StringName) -> void:
	var feedback := _new_request(&"weapon_switch")
	feedback.variant_id = current
	request(feedback)

func _live(value: Variant) -> bool:
	return typeof(value) == TYPE_OBJECT and is_instance_valid(value)

func _recently_executed(target: Object) -> bool:
	var until: int = int(_executed_until.get(target.get_instance_id(), 0))
	if until == 0:
		return false
	if Time.get_ticks_msec() > until:
		_executed_until.erase(target.get_instance_id())
		return false
	return true

# --- Revolver, Style, attack phases -------------------------------------

func _on_shot_resolved(origin: Vector3, endpoint: Vector3, target: Variant, _hit: Variant) -> void:
	var feedback := _new_request(&"revolver_shot")
	feedback.target = target if _live(target) else null
	feedback.set_world_position(origin)
	feedback.set_world_endpoint(endpoint)
	feedback.direction = endpoint - origin
	feedback.correlation_key = StringName("shot:%d" % Engine.get_physics_frames())
	request(feedback)

## Keep the established layered arc and drive its pose from each active hitbox.
func _on_swing_started(correlation_key: StringName, pose: Transform3D, _profile_shape: StringName, profile_size: Vector3, spec: HitSpec, weapon: WeaponData, _serial: int) -> void:
	if spec == null or weapon == null:
		return
	var reach := _slash_reach(_profile_shape, profile_size)
	var active_ticks := maxi(1, spec.active_ticks.y - spec.active_ticks.x + 1)
	var feedback := _new_request(&"slash_trace")
	feedback.variant_id = weapon.id
	feedback.weapon_id = weapon.id
	feedback.correlation_key = correlation_key
	feedback.set_world_position(pose.origin) # Fallback effects use the actual hitbox center.
	feedback.set_world_transform(pose)
	feedback.direction = -pose.basis.z
	feedback.visual = {
		&"core_color": weapon.trace_core_color,
		&"edge_color": weapon.trace_edge_color,
		&"size": reach,
		&"sweep_seconds": maxf(0.08, float(active_ticks) / 60.0),
		&"fade_seconds": maxf(0.1, float(spec.linger_ticks) / 60.0 + 0.12),
	}
	request(feedback)

func _slash_reach(profile_shape: StringName, profile_size: Vector3) -> float:
	match profile_shape:
		&"sphere":
			return maxf(0.5, profile_size.x)
		&"capsule":
			return maxf(0.5, profile_size.x + profile_size.z * 0.5)
		&"box":
			return maxf(0.5, maxf(profile_size.x, profile_size.z) * 0.5)
		&"cone":
			return maxf(0.5, profile_size.z * 0.5)
		&"ring":
			return maxf(0.5, profile_size.x + profile_size.y)
	return maxf(0.5, maxf(profile_size.x, profile_size.z) * 0.5)

## Add each active native pose to the same VFX instance; never poll a diagnostic snapshot.
func _on_swing_updated(correlation_key: StringName, pose: Transform3D) -> void:
	if vfx_handler != null:
		vfx_handler.update_transform(correlation_key, pose)

func _on_swing_ended(correlation_key: StringName) -> void:
	if vfx_handler != null:
		vfx_handler.finalize_trace(correlation_key)

func _on_style_award(_award: Object) -> void:
	request(_new_request(&"style_payout")) # Presentation accent only; Style owns the points.

func _on_style_changed(_rating: float, rank_index: int, _normalized: float) -> void:
	if rank_index > _last_rank:
		request(_new_request(&"style_rank_up"))
	_last_rank = rank_index

func _on_phase_cue(cue: StringName, variant: StringName, phase: StringName, attack_key: String, _anchor: StringName, potency: float) -> void:
	var trail_key := StringName("%s:trail" % attack_key)
	if phase == &"end":
		if vfx_handler != null:
			vfx_handler.release(trail_key)
		return
	var feedback := _new_request(cue)
	feedback.variant_id = variant
	feedback.phase = phase
	feedback.potency = potency
	feedback.correlation_key = trail_key if phase == &"trail" else StringName("%s:%s" % [attack_key, phase])
	if attack_observer != null and is_instance_valid(attack_observer.controller):
		var owner_node: Variant = attack_observer.controller.get_parent()
		if owner_node is Node3D:
			feedback.source = owner_node
			feedback.target = owner_node
			var facing: Vector3 = (owner_node as Node).call(&"get_combat_facing") if (owner_node as Node).has_method(&"get_combat_facing") else Vector3.ZERO
			feedback.direction = facing
	request(feedback)

# --- Enemy warnings --------------------------------------------------------

func _unbind_style() -> void:
	if is_instance_valid(_style):
		if _style.is_connected(&"style_points_awarded", _on_style_award):
			_style.disconnect(&"style_points_awarded", _on_style_award)
		if _style.is_connected(&"style_changed", _on_style_changed):
			_style.disconnect(&"style_changed", _on_style_changed)
	_style = null
	_last_rank = 0

func _unbind_encounter() -> void:
	if is_instance_valid(_encounter) and _encounter.is_connected(&"enemy_spawned", _on_enemy_spawned):
		_encounter.disconnect(&"enemy_spawned", _on_enemy_spawned)
	_encounter = null

func _on_enemy_spawned(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var id := enemy.get_instance_id()
	if _enemy_links.has(id):
		return
	var role := enemy.get_node_or_null("RoleController")
	if role == null or not role.has_signal(&"cue"):
		return
	var on_cue := _on_enemy_cue.bind(enemy)
	var on_attack := _on_enemy_attack_started.bind(enemy)
	var on_interrupt := _on_enemy_attack_interrupted.bind(enemy)
	var on_despawn := _on_enemy_despawned
	role.connect(&"cue", on_cue)
	if role.has_signal(&"attack_started"):
		role.connect(&"attack_started", on_attack)
	if role.has_signal(&"attack_interrupted"):
		role.connect(&"attack_interrupted", on_interrupt)
	if enemy.has_signal(&"despawned"):
		enemy.connect(&"despawned", on_despawn)
	_enemy_links[id] = {&"enemy": enemy, &"role": role, &"cue": on_cue, &"attack": on_attack, &"interrupt": on_interrupt, &"despawn": on_despawn}
	_apply_bridge_motion(enemy)

func _on_enemy_cue(cue: StringName, enemy: Node) -> void:
	if not is_instance_valid(enemy):
		return
	var feedback := _new_request(cue)
	feedback.variant_id = warning_variants.get(cue, &"")
	feedback.source = enemy
	feedback.target = enemy
	feedback.role_id = feedback.variant_id
	feedback.correlation_key = _warning_key(enemy)
	request(feedback)

func _on_enemy_attack_started(_attack_id: StringName, enemy: Node) -> void:
	if is_instance_valid(enemy) and vfx_handler != null:
		vfx_handler.release(_warning_key(enemy))

## An accepted reaction or parry cancelled the windup: drop its warning now.
func _on_enemy_attack_interrupted(enemy: Node) -> void:
	if is_instance_valid(enemy) and vfx_handler != null:
		vfx_handler.release(_warning_key(enemy))

func _apply_bridge_motion(enemy: Variant) -> void:
	if not is_instance_valid(enemy):
		return
	var bridge := (enemy as Node).get_node_or_null("AnimationBridge")
	if bridge != null and &"reduced_motion" in bridge:
		bridge.set(&"reduced_motion", _reduced_motion)

func _on_enemy_despawned(enemy: Node) -> void:
	if enemy == null:
		return
	var id := enemy.get_instance_id()
	if vfx_handler != null:
		vfx_handler.release(_warning_key(enemy))
	_unlink_enemy(id)

func _warning_key(enemy: Node) -> StringName:
	return StringName("warn:%d" % enemy.get_instance_id())

func _unlink_enemy(id: int) -> void:
	var link: Dictionary = _enemy_links.get(id, {})
	_enemy_links.erase(id)
	if link.is_empty():
		return
	var role: Variant = link[&"role"]
	if is_instance_valid(role):
		if role.is_connected(&"cue", link[&"cue"]):
			role.disconnect(&"cue", link[&"cue"])
		if role.has_signal(&"attack_started") and role.is_connected(&"attack_started", link[&"attack"]):
			role.disconnect(&"attack_started", link[&"attack"])
		if role.has_signal(&"attack_interrupted") and role.is_connected(&"attack_interrupted", link[&"interrupt"]):
			role.disconnect(&"attack_interrupted", link[&"interrupt"])
	var enemy: Variant = link[&"enemy"]
	if is_instance_valid(enemy) and enemy.has_signal(&"despawned") and enemy.is_connected(&"despawned", link[&"despawn"]):
		enemy.disconnect(&"despawned", link[&"despawn"])

func _unlink_enemies() -> void:
	for id in _enemy_links.keys():
		_unlink_enemy(id)

# --- Run lifetime ------------------------------------------------------------

func _on_level_started(_depth: int, _context: Object) -> void:
	clear_level()

func _on_run_ended(_summary: Dictionary) -> void:
	clear_level()

# --- Helpers ---------------------------------------------------------------

func _new_request(cue: StringName) -> FeedbackRequest:
	var feedback := FeedbackRequest.new()
	feedback.cue_id = cue
	feedback.generation = _generation
	return feedback

func _remember(cue: StringName) -> void:
	_recent.append(cue)
	if _recent.size() > RECENT_LIMIT:
		_recent.pop_front()
