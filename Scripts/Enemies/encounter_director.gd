class_name EncounterDirector
extends Node

signal enemy_spawned(enemy: Enemy)
signal spawn_failed(enemy_id: StringName, reason: String)
signal stage_cleared
signal encounter_failed(reason: String)

@export var catalog: EnemyCatalog
@export var max_spawn_retries: int = 3
var spawn_factory: Callable
var player_node: Node3D
## Shared ground pathing for the current arena (see ArenaFlowField); handed to every spawn.
var flow_field: ArenaFlowField
var pending_count: int = 0
var alive_count: int = 0
var defeated_count: int = 0
var manifest_total: int = 0
var interval_ticks: int = 60
var active_cap: int = 5
## Spawn cost (instantiate + add_child), for profiling the horde.
var spawn_count: int = 0
var spawn_usec_total: int = 0
var spawn_usec_max: int = 0
var _tick: int = 0
var _retry_wait: int = 0
var _failures: int = 0
var _running: bool = false
var _cleared: bool = false
var _cancelling: bool = false
var _pending: Array[Dictionary] = []
var _active: Dictionary = {}
var _anchors: Array[Node3D] = []
var _difficulty: Dictionary = {}
var _rng := RandomNumberGenerator.new()

func start_encounter(encounter: Resource, anchors: Array[Node3D], run_seed: int, difficulty: Dictionary, new_interval_ticks: int, new_active_cap: int) -> bool:
	if catalog == null: catalog = EnemyCatalog.new()
	if not validate_encounter(encounter, anchors, difficulty, new_interval_ticks, new_active_cap).is_empty(): return false
	var snapshot: Array[Dictionary] = []
	var total := 0
	for entry in encounter.entries:
		for _i in range(entry.count):
			snapshot.append({"enemy_id": entry.enemy_id, "tags": entry.spawn_tags.duplicate()})
			total += 1
	_rng.seed = run_seed
	for i in range(snapshot.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var temp := snapshot[i]
		snapshot[i] = snapshot[j]
		snapshot[j] = temp
	_pending = snapshot
	_anchors = anchors.duplicate()
	_difficulty = difficulty.duplicate(true)
	manifest_total = total
	pending_count = total
	alive_count = 0
	defeated_count = 0
	interval_ticks = new_interval_ticks
	active_cap = new_active_cap
	_tick = 0
	_failures = 0
	_retry_wait = 0
	_cleared = false
	_cancelling = false
	_running = true
	return true

## Side-effect-free validation for a candidate level before its checkpoint is
## committed or the current arena is retired.
func validate_encounter(encounter: Resource, anchors: Array[Node3D], _difficulty: Dictionary, new_interval_ticks: int, new_active_cap: int) -> PackedStringArray:
	var errors := PackedStringArray()
	if _running or not _active.is_empty():
		errors.append("An encounter is already active")
		return errors
	var definitions_catalog: EnemyCatalog = catalog if catalog != null else EnemyCatalog.new()
	if encounter == null or not "entries" in encounter or not encounter.has_method("get_total_count"):
		errors.append("Encounter definition is missing entries or a total-count contract")
		return errors
	if anchors.is_empty() or new_interval_ticks < 1 or new_active_cap < 1:
		errors.append("Encounter requires spawn anchors, a positive interval, and a positive active cap")
		return errors
	var total := 0
	for entry in encounter.entries:
		if entry == null or not "enemy_id" in entry or not "count" in entry or not "spawn_tags" in entry or entry.enemy_id.is_empty() or entry.count < 0:
			errors.append("Encounter contains an invalid roster entry")
			continue
		var definition := definitions_catalog.get_definition(entry.enemy_id)
		if definition == null:
			errors.append("Encounter references unknown enemy '%s'" % entry.enemy_id)
		elif not definition.validate().is_empty():
			errors.append_array(definition.validate())
		var matching := false
		for anchor in anchors:
			if _anchor_matches(anchor, entry.spawn_tags): matching = true
		if not matching:
			errors.append("No compatible spawn anchor for enemy '%s'" % entry.enemy_id)
		total += entry.count
	if total < 1 or total != encounter.get_total_count():
		errors.append("Encounter roster total is invalid")
	return errors

func set_interval_ticks(value: int) -> void:
	interval_ticks = maxi(1, value)

func pending_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry in _pending: ids.append(entry.enemy_id)
	return ids

func active_enemies() -> Array[Enemy]:
	var enemies: Array[Enemy] = []
	for record in _active.values():
		enemies.append(record.enemy)
	return enemies

func _physics_process(_delta: float) -> void:
	var _probe := ScriptCostProbe.start()
	_physics_process_body(_delta)
	ScriptCostProbe.stop(&"director", _probe)

func _physics_process_body(_delta: float) -> void:
	step_physics()

func step_physics() -> void:
	if not _running or _pending.is_empty() or alive_count >= active_cap: return
	if _retry_wait > 0:
		_retry_wait -= 1
		return
	if _tick > 0:
		_tick -= 1
		return
	_spawn_one()

func _spawn_one() -> void:
	var entry_index := -1
	var compatible: Array[Node3D] = []
	var valid_but_occupied := false
	var usage := {} # anchor -> enemies on it, built once instead of per anchor per candidate
	for record in _active.values():
		usage[record.anchor] = int(usage.get(record.anchor, 0)) + 1
	for i in range(_pending.size()):
		var candidate: Dictionary = _pending[i]
		for anchor in _anchors:
			if not _anchor_matches(anchor, candidate.tags): continue
			if int(usage.get(anchor, 0)) >= int(anchor.get("capacity")):
				valid_but_occupied = true
			else:
				compatible.append(anchor)
		if not compatible.is_empty():
			entry_index = i
			break
	if entry_index < 0:
		if not valid_but_occupied:
			_fail_spawn(_pending[0].enemy_id, "no compatible anchor remains")
		return
	var entry: Dictionary = _pending[entry_index]
	var anchor := compatible[_rng.randi_range(0, compatible.size() - 1)]
	var definition := catalog.get_definition(entry.enemy_id)
	var spawn_started := Time.get_ticks_usec()
	var enemy: Enemy = spawn_factory.call(definition) if spawn_factory.is_valid() else definition.scene.instantiate() as Enemy
	if enemy == null:
		_fail_spawn(entry.enemy_id, "factory returned no Enemy")
		return
	enemy.setup(definition, player_node, _difficulty)
	enemy.flow_field = flow_field
	add_child(enemy)
	enemy.global_position = anchor.global_position + (Vector3.UP * definition.hover_height if definition.role == &"drone" else Vector3.ZERO)
	_pending.remove_at(entry_index)
	pending_count -= 1
	alive_count += 1
	_active[enemy.get_instance_id()] = {"enemy": enemy, "entry": entry, "anchor": anchor}
	enemy.defeated.connect(_on_enemy_defeated)
	enemy.despawned.connect(_on_enemy_despawned)
	_failures = 0
	_tick = interval_ticks - 1
	var spawn_usec := Time.get_ticks_usec() - spawn_started
	spawn_count += 1
	spawn_usec_total += spawn_usec
	spawn_usec_max = maxi(spawn_usec_max, spawn_usec)
	enemy_spawned.emit(enemy)

func _fail_spawn(enemy_id: StringName, reason: String) -> void:
	spawn_failed.emit(enemy_id, reason)
	_failures += 1
	if _failures >= maxi(1, max_spawn_retries):
		_running = false
		encounter_failed.emit("spawn retries exhausted for %s: %s" % [enemy_id, reason])
	else:
		_retry_wait = mini(600, interval_ticks * _failures)

func _anchor_matches(anchor: Node3D, required_tags: Array[StringName]) -> bool:
	if not is_instance_valid(anchor) or not "tags" in anchor or not "capacity" in anchor or int(anchor.get("capacity")) < 1: return false
	var available: Array[StringName] = anchor.get("tags")
	for tag in required_tags:
		if tag not in available: return false
	return true

func _anchor_usage(anchor: Node3D) -> int:
	var count := 0
	for record in _active.values():
		if record.anchor == anchor: count += 1
	return count

func _on_enemy_defeated(enemy: Enemy) -> void:
	var key := enemy.get_instance_id()
	if not _active.has(key): return
	_active.erase(key)
	alive_count -= 1
	defeated_count += 1
	if _running and not _cleared and pending_count == 0 and alive_count == 0 and defeated_count == manifest_total:
		_cleared = true
		_running = false
		stage_cleared.emit()

func _on_enemy_despawned(enemy: Enemy) -> void:
	var key := enemy.get_instance_id()
	if not _active.has(key): return
	var record: Dictionary = _active[key]
	_active.erase(key)
	alive_count -= 1
	if not _cancelling:
		_pending.append(record.entry)
		pending_count += 1

## Debug cheat: end the running stage now, as if every enemy had been defeated.
func force_clear() -> bool:
	if not _running or _cleared:
		return false
	cancel_encounter()
	_cleared = true
	stage_cleared.emit()
	return true

func cancel_encounter() -> void:
	_running = false
	_cancelling = true
	for enemy in active_enemies():
		if is_instance_valid(enemy): enemy.despawn()
	_active.clear()
	_pending.clear()
	pending_count = 0
	alive_count = 0
	defeated_count = 0
	manifest_total = 0
