class_name FeedbackVfxHandler
extends Node

## Spawns and expires the world effects a FeedbackProfile names. It owns every
## effect it creates: each ends by its own `finished` signal or by the profile's
## lifetime cap, and clear_level() frees them all. Warnings (priority 2+) keep
## reserved capacity and displace the oldest routine impact when the budget is full.

## Most routine (priority 0-1) effects alive at once.
@export_range(1, 64) var routine_budget: int = 14
## Most effects of any priority alive at once. Capacity above the routine budget is reserved for warnings and player damage.
@export_range(1, 96) var total_budget: int = 24

## Millisecond clock; replaced in tests.
var clock: Callable = Time.get_ticks_msec

var _world: Node
var _entries: Array[Dictionary] = []
var _last_played: Dictionary = {}
var _reduced_motion: bool = false
var _flash_strength: float = 1.0
var _emitted: int = 0
var _suppressed: int = 0
var _peak_active: int = 0

func bind(world: Node) -> void:
	clear_level()
	_world = world

func set_accessibility(reduced_motion: bool, flash_strength: float) -> void:
	_reduced_motion = reduced_motion
	_flash_strength = clampf(flash_strength, 0.0, 1.0)
	for entry in _entries:
		var node: Variant = entry[&"node"]
		if is_instance_valid(node) and node is PresentationEffect:
			(node as PresentationEffect).reduced_motion = reduced_motion

func active_count() -> int:
	return _entries.size()

func count_with_priority(priority: int) -> int:
	var count := 0
	for entry in _entries:
		if int(entry[&"priority"]) == priority:
			count += 1
	return count

func effect_nodes() -> Array:
	return _entries.map(func(entry: Dictionary) -> Variant: return entry[&"node"])

func effect_positions() -> Array:
	var positions: Array = []
	for entry in _entries:
		var node: Variant = entry[&"node"]
		if is_instance_valid(node) and node is Node3D:
			positions.append((node as Node3D).global_position)
	return positions

## Updates every live effect owned by this swing without spawning per-frame VFX.
func update_transform(correlation_key: StringName, pose: Transform3D) -> bool:
	var updated := false
	for entry in _entries:
		if entry[&"correlation"] != correlation_key:
			continue
		var node: Variant = entry[&"node"]
		if not is_instance_valid(node) or not node is Node3D:
			continue
		if node is PresentationEffect and (node as PresentationEffect).has_pose_trace():
			(node as PresentationEffect).add_pose_sample(pose)
		else:
			(node as Node3D).global_transform = pose
		updated = true
	return updated

## Freezes a swing trace and bakes its bounded pose history into its mesh.
func finalize_trace(correlation_key: StringName) -> bool:
	var finalized := false
	for entry in _entries:
		if entry[&"correlation"] != correlation_key:
			continue
		var node: Variant = entry[&"node"]
		if is_instance_valid(node) and node is PresentationEffect:
			(node as PresentationEffect).finalize_pose_trace()
			finalized = true
	return finalized

func stats() -> Dictionary:
	return {&"emitted": _emitted, &"suppressed": _suppressed, &"peak_active": _peak_active, &"active": _entries.size()}

## Returns true when at least one effect was spawned.
func play(request: FeedbackRequest, profile: FeedbackProfile) -> bool:
	if request == null or profile == null or not request.is_valid() or not is_instance_valid(_world):
		return false
	if profile.vfx_scenes.is_empty():
		return false
	var now: int = clock.call()
	var profile_key := _profile_key(profile)
	if profile.cooldown_seconds > 0.0 and now - int(_last_played.get(profile_key, -1000000)) < int(profile.cooldown_seconds * 1000.0):
		_suppressed += 1
		return false
	if _active_for(profile_key) >= profile.max_active or not _admit(profile.priority):
		_suppressed += 1
		return false
	var spawned := 0
	for scene in profile.vfx_scenes:
		if scene != null and _spawn(scene, request, profile, now, profile_key):
			spawned += 1
	if spawned == 0:
		return false
	_last_played[profile_key] = now
	_emitted += spawned
	_peak_active = maxi(_peak_active, _entries.size())
	return true

## Ends sustained effects spawned for `correlation_key` (a warning's owner released it).
func release(correlation_key: StringName) -> void:
	for index in range(_entries.size() - 1, -1, -1):
		if _entries[index][&"correlation"] == correlation_key:
			_end(index)

func clear_level() -> void:
	for index in range(_entries.size() - 1, -1, -1):
		_end(index)
	_last_played.clear()

func _process(_delta: float) -> void:
	var _probe := ScriptCostProbe.start()
	_process_body(_delta)
	ScriptCostProbe.stop(&"feel.vfx", _probe)

func _process_body(_delta: float) -> void:
	var now: int = clock.call()
	for index in range(_entries.size() - 1, -1, -1):
		var entry := _entries[index]
		if not is_instance_valid(entry[&"node"]) or now >= int(entry[&"expires"]):
			_end(index)

func _exit_tree() -> void:
	clear_level()

func _spawn(scene: PackedScene, request: FeedbackRequest, profile: FeedbackProfile, now: int, profile_key: String) -> bool:
	var node := scene.instantiate() as Node3D
	if node == null:
		return false
	var effect := node as PresentationEffect
	if effect != null:
		effect.reduced_motion = _reduced_motion
		effect.configure_from_request(request)
		effect.sustain = profile.vfx_sustained
		if _flash_strength < 1.0 and profile.priority < 2:
			effect.opacity *= _flash_strength # Warnings keep full strength to stay readable.
	_world.add_child(node)
	if request.has_world_transform():
		node.global_transform = request.world_transform()
	else:
		node.global_position = request.resolve_position()
		if request.direction.length_squared() > 0.0001 and absf(request.direction.normalized().dot(Vector3.UP)) < 0.999:
			node.look_at(node.global_position + request.direction, Vector3.UP)
	node.scale = Vector3.ONE * profile.vfx_scale
	if effect != null and request.has_world_transform() and effect.has_pose_trace():
		effect.begin_pose_trace(request.world_transform())
	if effect != null and effect.shape == PresentationEffect.Shape.TRACE and request.has_world_endpoint():
		# The node is already turned and scaled; give the trace its endpoint in local space.
		effect.set_endpoints(Vector3.ZERO, node.to_local(request.world_endpoint()))
	for particles in node.find_children("*", "GPUParticles3D", true, false):
		(particles as GPUParticles3D).restart()
	var entry := {&"node": node, &"expires": now + int(profile.vfx_lifetime_cap * 1000.0), &"priority": profile.priority, &"profile": profile_key, &"correlation": request.correlation_key}
	_entries.append(entry)
	if effect != null:
		effect.finished.connect(_on_effect_finished, CONNECT_ONE_SHOT)
	return true

func _on_effect_finished(effect: Node) -> void:
	for index in range(_entries.size() - 1, -1, -1):
		if _entries[index][&"node"] == effect:
			_entries.remove_at(index) # The effect frees itself (not pooled).
			return

func _admit(priority: int) -> bool:
	if priority < 2:
		return _routine_count() < routine_budget and _entries.size() < total_budget
	if _entries.size() < total_budget:
		return true
	var oldest := _oldest_routine()
	if oldest < 0:
		return false
	_end(oldest)
	return true

func _routine_count() -> int:
	var count := 0
	for entry in _entries:
		if int(entry[&"priority"]) < 2:
			count += 1
	return count

func _oldest_routine() -> int:
	for index in _entries.size():
		if int(_entries[index][&"priority"]) < 2:
			return index
	return -1

func _active_for(profile_key: String) -> int:
	var count := 0
	for entry in _entries:
		if entry[&"profile"] == profile_key:
			count += 1
	return count

func _profile_key(profile: FeedbackProfile) -> String:
	return "%s/%s" % [profile.cue_id, profile.variant_id]

func _end(index: int) -> void:
	var node: Variant = _entries[index][&"node"]
	_entries.remove_at(index)
	if not is_instance_valid(node):
		return
	if node is PresentationEffect and (node as PresentationEffect).finished.is_connected(_on_effect_finished):
		(node as PresentationEffect).finished.disconnect(_on_effect_finished)
	(node as Node).queue_free()
