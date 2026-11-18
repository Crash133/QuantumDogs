class_name RunController
extends Node

## Integrator-owned run lifecycle. Wires the owners without changing their rules:
## Progression (service/coordinator/adapter, profile + level-start checkpoint),
## Level Generation (sliced, non-blocking generation), Enemies (EncounterDirector),
## Style (awards -> profile credit once; normalized rating -> pacing) and Combat
## (Battery ratio -> pacing, player_died -> run end). Menus/UI are not built here.

signal level_started(depth: int, context: StageContext)
signal reward_offered(offer: Dictionary)
signal transition_failed(error: String)
signal run_ended(summary: Dictionary)
signal level_transition_committed(result: Resource, context: StageContext)

@export var enable_enemy_attacks: bool = true
@export var active_enemy_cap: int = 20
## Upper bound on ticks between spawns so a thinned horde is refilled quickly.
@export var horde_max_interval_ticks: int = 12
@export var pacing_sample_ticks: int = 30
@export var pacing_tuning: SpawnPacingTuning
## Falling this far below the arena is fatal, for Lace and for enemies.
@export var fall_depth: float = 10.0
@export_group("Debug Cheats")
## Debug builds only. Alt+F3 finishes the current level; Alt+1..Alt+4 unlock the
## weapon at that index in cheat_unlock_order for the running run.
@export var cheats_enabled: bool = true
## Weapon ids unlocked by Alt+1, Alt+2, ... in order.
@export var cheat_unlock_order: Array[StringName] = [&"mantis_blades", &"saber", &"rocket_lance", &"greatsword"]
@export_group("")

var world: Node3D
var player: Player
var style_system: Node
var catalog: ProgressionCatalog
var profile_store := ProfileStore.new()
var checkpoint_store := RunCheckpointStore.new()
var service := ProgressionService.new()
var coordinator := StageRewardCoordinator.new()
var adapter := ProgressionRuntimeAdapter.new()
var generation: SlicedArenaGeneration
var director: EncounterDirector
var cinematic: PlaceholderDownedCinematic
var context: StageContext
var arena: Node3D
var last_generation_diagnostics: Dictionary = {}
var style_points_earned: float = 0.0
var last_flow_error: String = ""
## Captured exactly once before any derived run build is applied.
var _base_tuning: CombatTuning
var _base_weapons: Array[WeaponData] = []
@export var build_policy: CombatBuildPolicy
var _build_compiler := CombatBuildCompiler.new()
var _difficulty_adapter := DifficultyAdapter.new()
var pending_combat_build: CombatRunBuild
var _initial_request := 0
var _checkpoint_invalidated_in_memory := false
var _pacing := SpawnPacingController.new()
var _pacing_tick := 0

func setup(world_node: Node3D, player_node: Player, style_node: Node, run_catalog: ProgressionCatalog) -> void:
	world = world_node
	player = player_node
	style_system = style_node
	catalog = run_catalog
	if build_policy == null:
		# shortcut: placeholder stat effects until D1 values are approved; replace this resource then.
		build_policy = (load("res://Resources/Integration/placeholder_build_policy.tres") as CombatBuildPolicy).duplicate(true)
	if player != null and player.combat_controller != null:
		_base_tuning = player.combat_controller.tuning.duplicate(true) as CombatTuning
		_base_weapons.assign(player.combat_controller.weapons)
	else:
		last_flow_error = "Cannot capture base Combat tuning and weapons: Player CombatController is missing."
	if pacing_tuning == null:
		pacing_tuning = SpawnPacingTuning.new()
	generation = get_node_or_null("ArenaGeneration") as SlicedArenaGeneration
	# Bare-controller fixtures may supply services without instantiating the scene.
	if generation == null:
		generation = SlicedArenaGeneration.new()
		generation.name = "ArenaGeneration"
		# Narrow fallback for bare RunController test fixtures.
		add_child(generation)
	generation.max_concurrent = active_enemy_cap
	director = get_node_or_null("EncounterDirector") as EncounterDirector
	# Bare-controller fixtures may supply services without instantiating the scene.
	if director == null:
		director = EncounterDirector.new()
		director.name = "EncounterDirector"
		# Narrow fallback for bare RunController test fixtures.
		add_child(director)
	director.catalog = EnemyCatalog.new()
	director.player_node = player
	director.stage_cleared.connect(_on_stage_cleared)
	director.encounter_failed.connect(func(reason: String) -> void: transition_failed.emit("Encounter failed: " + reason))
	director.enemy_spawned.connect(_on_enemy_spawned)
	cinematic = get_node_or_null("DownedCinematic") as PlaceholderDownedCinematic
	# Bare-controller fixtures may supply services without instantiating the scene.
	if cinematic == null:
		cinematic = PlaceholderDownedCinematic.new()
		cinematic.name = "DownedCinematic"
		# Narrow fallback for bare RunController test fixtures.
		add_child(cinematic)
	coordinator.service = service
	coordinator.show_reward.connect(func(offer: Dictionary) -> void:
		var pending_error := checkpoint_store.mark_reward_pending()
		if pending_error != OK:
			last_flow_error = "Could not save the active-run checkpoint: " + error_string(pending_error)
			transition_failed.emit(last_flow_error)
			return
		reward_offered.emit(offer))
	# The coordinator also reports "Run ended" here on death; run_ended covers that.
	coordinator.transition_failed.connect(func(error: String) -> void:
		if service.run != null and not service.run.ended:
			transition_failed.emit(error))
	adapter.configure(service, coordinator, _submit_generation, _commit_and_activate_level)
	service.run_ended.connect(_on_run_ended)
	var events := get_node_or_null("/root/CombatEvents")
	if events != null:
		events.player_died.connect(_on_player_died)

func start_new_run(mode: StringName, seed: int) -> bool:
	var prepared := _prepare_new_game(mode, seed)
	if not prepared.get("success", false): return false
	_configure(prepared.profile, prepared.run, prepared.build)
	return true

## Reconcile level-start currency before entering the menu or leaving a run.
func prepare_menu_profile() -> Error:
	last_flow_error = ""
	profile_store.last_error = OK
	var error := checkpoint_store.reconcile_profile(profile_store, catalog)
	if error != OK:
		last_flow_error = "Could not reconcile the active run: " + error_string(error)
	return error

## Continue restarts the checkpointed level with the full run build and only
## rolls Style Points back; permanent stat levels remain current.
func continue_run() -> bool:
	if _checkpoint_invalidated_in_memory:
		last_flow_error = "The active run has ended."
		return false
	if prepare_menu_profile() != OK: return false
	var checkpoint := checkpoint_store.load_checkpoint(catalog)
	if checkpoint.is_empty():
		last_flow_error = "No valid active-run checkpoint is available."
		return false
	var profile := profile_store.load_profile(catalog)
	if profile_store.last_error != OK:
		last_flow_error = "Could not load the player profile: " + error_string(profile_store.last_error)
		return false
	var build_result := _prepare_combat_build(profile, checkpoint.run)
	if not build_result.get("ok", false):
		last_flow_error = _combat_build_error(build_result)
		return false
	_configure(profile, checkpoint.run, build_result.build)
	return true

func _prepare_new_game(mode: StringName, seed: int) -> Dictionary:
	var run := RunProgressionState.begin_run(mode, seed, catalog)
	if run == null:
		last_flow_error = "The selected run mode or progression catalog is invalid."
		return {"success": false}
	var reconcile_error := prepare_menu_profile()
	if reconcile_error != OK:
		# A corrupt checkpoint can be replaced after the player confirms New Game.
		# A profile load/save failure must keep the existing run and wallet intact.
		if profile_store.last_error != OK and FileAccess.file_exists(profile_store.path):
			return {"success": false}
		if not checkpoint_store.has_checkpoint(): return {"success": false}
	var profile := profile_store.load_profile(catalog)
	if FileAccess.file_exists(profile_store.path) and profile_store.last_error != OK:
		last_flow_error = "Could not load the player profile: " + error_string(profile_store.last_error)
		return {"success": false}
	var build_result := _prepare_combat_build(profile, run)
	if not build_result.get("ok", false):
		last_flow_error = _combat_build_error(build_result)
		return {"success": false}
	var clear_error := checkpoint_store.clear()
	if clear_error != OK:
		last_flow_error = "Could not replace the active run: " + error_string(clear_error)
		return {"success": false}
	return {"success": true, "profile": profile, "run": run, "build": build_result.build}

func _prepare_combat_build(profile: PersistentProfile, run: RunProgressionState) -> Dictionary:
	if _base_tuning == null or _base_weapons.is_empty() or catalog == null:
		return {"ok": false, "build": null, "errors": PackedStringArray(["Base Combat build inputs are unavailable"])}
	return _build_compiler.compile(profile, run, catalog, _base_tuning, _base_weapons, build_policy)

func _combat_build_error(result: Dictionary) -> String:
	var details := "; ".join(result.get("errors", PackedStringArray()))
	return "Combat build validation failed" + (": " + details if not details.is_empty() else ".")

func select_reward(ids: Array[StringName]) -> bool:
	return service.select_reward_ids(ids, coordinator.current_offer)

func purchase_stat(stat_id: StringName) -> Dictionary:
	return service.purchase_stat(stat_id)

## After transition_failed during stage clear: request the same prepared stage again.
func retry_stage_clear() -> void:
	coordinator.begin_stage_clear(service.run.make_next_stage_context(catalog), adapter, cinematic)

func _configure(profile: PersistentProfile, run: RunProgressionState, build: CombatRunBuild) -> void:
	service.configure(profile, run, catalog, profile_store)
	pending_combat_build = build
	style_points_earned = 0.0
	bind_style()
	_start_first_level()

## Idempotent: the adapter replaces its own connection, so awards credit once.
func bind_style() -> void:
	if style_system == null:
		return
	adapter.connect_style(style_system, service)
	if style_system.has_signal(&"style_points_awarded") and not style_system.is_connected(&"style_points_awarded", _on_style_award):
		style_system.connect(&"style_points_awarded", _on_style_award)

func _on_style_award(award) -> void:
	if award != null and not service.run.ended:
		style_points_earned += float(award.amount)

func _start_first_level() -> void:
	# No arena exists yet: without this Lace falls through the void while it generates.
	if player != null: player.set_physics_process(false)
	var next := service.run.make_next_stage_context(catalog)
	# Negative ids never collide with the coordinator's positive request ids.
	_initial_request -= 1
	generation.submit(adapter.make_arena_request_payload(next), _initial_request, _on_first_level_generated.bind(next, pending_combat_build))

func _on_first_level_generated(request_id: int, result: ArenaGenerationResult, next: StageContext, build: CombatRunBuild) -> void:
	if request_id != _initial_request or service.run.ended or not result.success or not is_instance_valid(result.root):
		if is_instance_valid(result.root):
			result.root.free()
		transition_failed.emit(result.error if not result.success else "Stale first-level result")
		return
	_commit_and_activate_level(result, next, build)

func _submit_generation(payload: Dictionary, request_id: int) -> void:
	generation.submit(payload, request_id, _on_stage_generated)

func _on_stage_generated(request_id: int, result: ArenaGenerationResult) -> void:
	adapter.on_generation_completed(request_id, result)
	# The coordinator ignores stale/failed completions; their roots are ours to free.
	if coordinator.arena_result != result and is_instance_valid(result.root) and not result.root.is_inside_tree():
		result.root.free()

## Commit a level-start checkpoint before advancing run state or retiring the
## current arena. Reward selection remains in memory if this write fails.
func _commit_and_activate_level(result: Resource, next: StageContext, candidate_build: CombatRunBuild = null) -> bool:
	if result == null or result.get("success") != true or next == null or service.run == null or service.run.ended:
		transition_failed.emit("Prepared stage is no longer valid")
		return false
	var expected := service.run.make_next_stage_context(catalog)
	if expected == null or next.run_seed != expected.run_seed or next.ascent_depth != expected.ascent_depth or next.mode != expected.mode or next.band != expected.band:
		transition_failed.emit("Prepared stage does not match the active run")
		return false
	if candidate_build == null:
		var build_result := _prepare_combat_build(service.profile, service.run)
		if not build_result.get("ok", false):
			last_flow_error = _combat_build_error(build_result)
			transition_failed.emit(last_flow_error)
			var invalid_root = result.get("root")
			if is_instance_valid(invalid_root) and not invalid_root.is_inside_tree(): invalid_root.free()
			return false
		candidate_build = build_result.build
	var controller := player.combat_controller if player != null else null
	var has_unsafe_controller := player != null and (controller == null or controller.state != CombatController.State.IDLE or controller.combo.current_node != null)
	var preflight := _preflight_level_activation(result, next, candidate_build)
	if not preflight.ok or has_unsafe_controller:
		var problems := PackedStringArray(preflight.get("errors", PackedStringArray()))
		if has_unsafe_controller:
			problems.append("Combat is not at a safe level boundary (%s)" % (CombatController.State.keys()[controller.state] if controller != null else "no controller"))
		last_flow_error = "Level activation validation failed: " + "; ".join(problems)
		transition_failed.emit(last_flow_error)
		var invalid_root = result.get("root")
		if is_instance_valid(invalid_root) and not invalid_root.is_inside_tree(): invalid_root.free()
		return false
	var save_error := checkpoint_store.save_next_level(service.run, next, service.profile)
	if save_error != OK:
		if coordinator != null: coordinator.state = StageRewardCoordinator.State.FAILED
		last_flow_error = "Could not save the next level checkpoint: " + error_string(save_error)
		transition_failed.emit(last_flow_error)
		var failed_root = result.get("root")
		if is_instance_valid(failed_root) and not failed_root.is_inside_tree(): failed_root.free()
		return false
	if not service.run.advance_stage(next):
		checkpoint_store.invalidate_checkpoint()
		transition_failed.emit("Prepared stage could not be applied")
		return false
	_retire_arena()
	if not _activate_level(result, next, candidate_build, preflight.parameters):
		return false
	_checkpoint_invalidated_in_memory = false
	last_flow_error = ""
	_set_player_input(true)
	level_transition_committed.emit(result, next.duplicate(true))
	return true

## Validate every expected rejection before persistence or retiring the arena.
func _preflight_level_activation(result: Resource, next: StageContext, build: CombatRunBuild) -> Dictionary:
	var errors := PackedStringArray()
	if not result is ArenaGenerationResult or result.success != true or not result.root is Node3D:
		errors.append("Generated arena result/root is invalid")
		return {"ok": false, "errors": errors}
	if result.root.is_inside_tree() or result.seed != next.run_seed:
		errors.append("Generated arena seed or root lifecycle does not match the prepared stage")
	if not next.arena_profile is ArenaProfile or not next.encounter is EncounterDefinition:
		errors.append("Prepared stage profile or encounter has an incompatible resource type")
	else:
		errors.append_array(next.arena_profile.validate())
		errors.append_array(next.encounter.validate())
		var catalog_key := String(next.mode) + "/" + String(next.band)
		var catalog_profile = catalog.arena_profiles.get(catalog_key) if catalog != null else null
		if not catalog_profile is ArenaProfile or not _same_arena_profile(catalog_profile, next.arena_profile):
			errors.append("Prepared arena profile does not match the active progression catalog")
		var catalog_encounter: Resource = catalog.get_encounter(next.mode, next.band, next.ascent_depth, next.run_seed) if catalog != null else null
		if catalog_encounter == null or not _same_encounter_manifest(catalog_encounter, next.encounter):
			errors.append("Prepared encounter manifest does not match the active progression catalog")
	var player_starts := 0
	for marker in result.root.find_children("PlayerStart", "", true, false):
		if marker is Node3D: player_starts += 1
	if player_starts != 1:
		errors.append("Generated arena must contain exactly one PlayerStart")
	var anchors: Array[Node3D] = []
	for anchor in result.spawn_anchors:
		if not anchor is ArenaSpawnAnchor or not result.root.is_ancestor_of(anchor):
			errors.append("Generated spawn anchor is invalid or outside its arena root")
			continue
		anchors.append(anchor)
	var difficulty := _difficulty_adapter.normalize(next.difficulty_parameters, next.ascent_depth)
	for diagnostic in difficulty.get("diagnostics", PackedStringArray()):
		push_warning("Difficulty adapter: " + diagnostic)
	if not difficulty.get("ok", false):
		errors.append_array(difficulty.get("errors", PackedStringArray()))
	if build == null:
		errors.append("Prepared Combat build is missing")
	else:
		errors.append_array(build.validate())
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var encounter_errors := director.validate_encounter(next.encounter, anchors, difficulty.parameters, _sample_interval(), active_enemy_cap)
	if not encounter_errors.is_empty():
		errors.append_array(encounter_errors)
	return {"ok": errors.is_empty(), "errors": errors, "parameters": difficulty.parameters.duplicate(true)}

func _same_encounter_manifest(first: Resource, second: Resource) -> bool:
	if first == null or second == null or not "entries" in first or not "entries" in second or first.entries.size() != second.entries.size():
		return false
	for index in range(first.entries.size()):
		var a = first.entries[index]
		var b = second.entries[index]
		if a == null or b == null or a.enemy_id != b.enemy_id or a.count != b.count or a.spawn_tags != b.spawn_tags:
			return false
	return true

func _same_arena_profile(first: ArenaProfile, second: ArenaProfile) -> bool:
	if first == null or second == null:
		return false
	if first.allowed_silhouettes != second.allowed_silhouettes or not is_equal_approx(first.module_unit_size, second.module_unit_size):
		return false
	if first.silhouette_weights != second.silhouette_weights or first.normalized_footprints != second.normalized_footprints:
		return false
	if first.max_attempts != second.max_attempts or first.silhouette_source_note != second.silhouette_source_note:
		return false
	if first.core_modules.keys() != second.core_modules.keys() or first.fallback_scenes.keys() != second.fallback_scenes.keys():
		return false
	for silhouette_id in first.core_modules:
		var a = first.core_modules[silhouette_id]
		var b = second.core_modules[silhouette_id]
		if a == null or b == null or a.module_id != b.module_id:
			return false
	for silhouette_id in first.fallback_scenes:
		var a: PackedScene = first.fallback_scenes[silhouette_id]
		var b: PackedScene = second.fallback_scenes[silhouette_id]
		if a == null or b == null or a.resource_path != b.resource_path:
			return false
	if first.module_catalogue.size() != second.module_catalogue.size():
		return false
	for index in range(first.module_catalogue.size()):
		if first.module_catalogue[index] == null or second.module_catalogue[index] == null or first.module_catalogue[index].module_id != second.module_catalogue[index].module_id:
			return false
	return true

## Presentation consumer: run state and checkpoint have already committed.
func _activate_level(result: Resource, next: StageContext, build: CombatRunBuild, difficulty_parameters: Dictionary) -> bool:
	var apply_error := player.combat_controller.apply_run_build(build)
	if apply_error != OK:
		last_flow_error = "Unexpected Combat build rejection after activation commit; Continue can restore the saved level: " + error_string(apply_error)
		if is_instance_valid(result.root) and not result.root.is_inside_tree(): result.root.free()
		transition_failed.emit(last_flow_error)
		return false
	var adapter := player.get_node_or_null("CombatHitAdapter") as CombatHitAdapter
	if adapter != null and adapter.abilities != null:
		adapter.abilities.reset_for_level() # Weapon charges never carry into the next level.
	context = next.duplicate(true)
	context.difficulty_parameters = difficulty_parameters.duplicate(true)
	last_generation_diagnostics = result.diagnostics.duplicate(true)
	arena = result.root
	arena.name = "Arena_%d" % context.ascent_depth
	world.add_child(arena)
	var start := arena.find_child("PlayerStart", true, false) as Node3D
	player.global_position = start.global_position if start != null else Vector3.UP
	player.velocity = Vector3.ZERO
	player.set_physics_process(true)
	var battery := player.combat_controller.battery
	_refill_battery_for_level_start(battery)
	var heat := player.combat_controller.heat
	if heat != null: heat.reduce_heat(heat.maximum)
	_flow_field = ArenaFlowField.new()
	_flow_field.setup(result.placements, context.arena_profile.module_unit_size, arena.global_position)
	_flow_field.update_goal(player.global_position)
	director.flow_field = _flow_field
	var anchors: Array[Node3D] = []
	for anchor in result.spawn_anchors:
		anchors.append(anchor)
	if not director.start_encounter(context.encounter, anchors, context.run_seed + context.ascent_depth, difficulty_parameters, _sample_interval(), active_enemy_cap):
		last_flow_error = "Unexpected encounter rejection after activation commit; Continue can restore the saved level: %d" % context.ascent_depth
		director.cancel_encounter()
		arena.queue_free()
		arena = null
		context = null
		transition_failed.emit(last_flow_error)
		return false
	level_started.emit(context.ascent_depth, context)
	pending_combat_build = null
	return true

func _refill_battery_for_level_start(battery: BatteryMeter) -> void:
	if battery != null: battery.heal(battery.maximum)

func _retire_arena() -> void:
	director.cancel_encounter()
	if is_instance_valid(arena):
		arena.queue_free()
	arena = null

## Lace is downed between stage clear and the next level: no input, so combat
## settles at a safe boundary before the next level's loadout is applied.
func _set_player_input(enabled: bool) -> void:
	if player != null and player.combat_controller != null:
		player.combat_controller.input_sampling_enabled = enabled

func _unhandled_input(event: InputEvent) -> void:
	if not cheats_enabled or not OS.is_debug_build():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or not key.alt_pressed:
		return
	if key.keycode == KEY_F3:
		print("Cheat: finish level -> ", director != null and director.force_clear())
		get_viewport().set_input_as_handled()
		return
	var slot := key.keycode - KEY_1
	if slot >= 0 and slot < cheat_unlock_order.size():
		print("Cheat: unlock %s -> %s" % [cheat_unlock_order[slot], cheat_unlock_weapon(cheat_unlock_order[slot])])
		get_viewport().set_input_as_handled()

## Debug cheat: add a melee weapon to the active run and re-apply the combat build now.
func cheat_unlock_weapon(weapon_id: StringName) -> String:
	var run := service.run
	if run == null or run.ended:
		return "no active run"
	if not catalog.melee_weapon_ids.has(weapon_id):
		return "unknown weapon"
	if run.acquired_melee_weapon_ids.has(weapon_id):
		return "already unlocked"
	var controller := player.combat_controller if player != null else null
	if controller == null or controller.state != CombatController.State.IDLE or controller.combo.current_node != null:
		return "busy: retry while idle"
	run.acquired_melee_weapon_ids.append(weapon_id)
	run.deck.add_weapon(weapon_id, catalog)
	var build_result := _prepare_combat_build(service.profile, run)
	var error := controller.apply_run_build(build_result.build) if build_result.get("ok", false) else ERR_INVALID_DATA
	if error != OK:
		run.acquired_melee_weapon_ids.erase(weapon_id) # shortcut: deck card stays added; fine for a debug cheat.
		return "build rejected: %s" % _combat_build_error(build_result)
	return "unlocked"

func _on_stage_cleared() -> void:
	_set_player_input(false)
	coordinator.begin_stage_clear(service.run.make_next_stage_context(catalog), adapter, cinematic)

func _on_enemy_spawned(enemy: Enemy) -> void:
	# Combat rejects same-faction contacts before parry/damage/events (verified),
	# so spawned enemies may attack Lace.
	enemy.enemy_attacks_enabled = enable_enemy_attacks

func _on_player_died() -> void:
	if service.run != null and not service.run.ended:
		service.on_player_dead(0)

func _on_run_ended() -> void:
	if director != null: director.cancel_encounter()
	_checkpoint_invalidated_in_memory = true
	var invalidate_error := checkpoint_store.invalidate_checkpoint()
	var failure := ""
	if invalidate_error != OK:
		failure = "Could not invalidate the ended run checkpoint: " + error_string(invalidate_error)
		last_flow_error = failure
	run_ended.emit({"depth": service.run.ascent_depth, "style_points_earned": style_points_earned, "checkpoint_kept": false, "checkpoint_error": failure})

const FALL_CHECK_TICKS := 10
var _fall_tick: int = 0
var _flow_field: ArenaFlowField

func _physics_process(_delta: float) -> void:
	var _probe := ScriptCostProbe.start()
	_physics_process_body(_delta)
	ScriptCostProbe.stop(&"run.controller", _probe)

func _physics_process_body(_delta: float) -> void:
	if context == null or service.run == null or service.run.ended:
		return
	_fall_tick += 1
	if _fall_tick >= FALL_CHECK_TICKS: # A fall takes far longer than this to matter.
		_fall_tick = 0
		_kill_fallen()
		if _flow_field != null and player != null:
			_flow_field.update_goal(player.global_position)
	_pacing_tick += 1
	if _pacing_tick >= pacing_sample_ticks:
		_pacing_tick = 0
		director.set_interval_ticks(_sample_interval())

## Anything below the arena has left it. Enemies die (counted as defeats, so the
## stage can still clear); Lace dies outright, ignoring revives.
func _kill_fallen() -> void:
	if not is_instance_valid(arena) or not arena.is_inside_tree():
		return
	var limit := arena.global_position.y - fall_depth
	# Enemies first: Lace's death ends the run and cancels the encounter.
	for enemy in director.active_enemies():
		if is_instance_valid(enemy) and enemy.is_alive() and enemy.global_position.y < limit:
			var health: Node = enemy.get_node("HealthComponent")
			health.reduce_health(health.get_health())
	var combat := player.combat_controller if player != null else null
	if combat != null and combat.state != CombatController.State.DEAD and player.global_position.y < limit:
		combat.battery.set_revives(0)
		combat.battery.take_damage(combat.battery.maximum + combat.battery.value)

func _sample_interval() -> int:
	var metrics := SpawnPacingMetrics.new()
	if style_system != null and style_system.has_method("get_normalized_rating"):
		metrics.style_result = style_system.get_normalized_rating()
	metrics.living_enemy_ratio = float(director.alive_count) / float(maxi(1, director.manifest_total))
	var battery := player.combat_controller.battery
	metrics.player_health_ratio = battery.value / battery.maximum if battery.maximum > 0.0 else -1.0
	return mini(_pacing.get_interval_ticks(metrics, pacing_tuning), maxi(1, horde_max_interval_ticks))
