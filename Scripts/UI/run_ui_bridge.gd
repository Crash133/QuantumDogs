class_name RunUiBridge
extends Node

signal level_started(depth: int, context: StageContext)
signal reward_offered(offer: Dictionary)
signal transition_failed(error: String)
signal run_ended(summary: Dictionary)
signal level_transition_committed(result: Resource, context: StageContext)

const BOOTSTRAP_SCENE := "res://Scenes/Integration/RunBootstrap.tscn"
const OPTIONS_STORE_SCRIPT = preload("res://Scripts/UI/options_store.gd")

var catalog: ProgressionCatalog = IntegrationContent.make_catalog()
var profile_store := ProfileStore.new()
var checkpoint_store := RunCheckpointStore.new()
var bootstrap: RunBootstrap
var controller: RunController
var last_flow_error := ""
var last_mode: StringName = &"Normal"
var _seed := 0

func continue_available() -> bool:
	if controller != null and controller.service.run != null and controller.service.run.ended:
		return false
	return checkpoint_store.has_valid_checkpoint(catalog)

func prepare_menu() -> Error:
	last_flow_error = ""
	profile_store.last_error = OK
	var error := checkpoint_store.reconcile_profile(profile_store, catalog)
	if error != OK:
		last_flow_error = "Could not reconcile the active run: " + error_string(error)
	return error

func start_new_run(mode: StringName) -> bool:
	last_mode = mode
	var reconcile_error := prepare_menu()
	if reconcile_error != OK:
		# Confirmed New Game may replace an invalid checkpoint, but it cannot
		# proceed when profile persistence itself failed.
		if profile_store.last_error != OK and FileAccess.file_exists(profile_store.path): return false
		if not checkpoint_store.has_checkpoint(): return false
	if not _ensure_controller(): return false
	controller.profile_store = profile_store
	controller.checkpoint_store = checkpoint_store
	controller.catalog = catalog
	controller.profile_store.last_error = OK
	var ok := controller.start_new_run(mode, _seed if _seed != 0 else randi())
	last_flow_error = controller.last_flow_error
	if ok:
		_seed = randi()
		last_flow_error = ""
	else:
		_discard_run()
	return ok

func continue_run() -> bool:
	if prepare_menu() != OK: return false
	if not continue_available():
		last_flow_error = "No valid active-run checkpoint is available."
		return false
	if not _ensure_controller(): return false
	controller.profile_store = profile_store
	controller.checkpoint_store = checkpoint_store
	controller.catalog = catalog
	var ok := controller.continue_run()
	last_flow_error = controller.last_flow_error
	if not ok:
		_discard_run()
	return ok

func leave_run() -> Error:
	var error := prepare_menu()
	if error != OK: return error
	_discard_run()
	return OK

## A refused start must not leave its world (camera, falling player) behind the menu.
func _discard_run() -> void:
	if is_instance_valid(bootstrap):
		bootstrap.queue_free()
	bootstrap = null
	controller = null

func attach_controller(run_controller: RunController) -> void:
	controller = run_controller
	if controller == null: return
	controller.level_started.connect(func(depth: int, context: StageContext) -> void: level_started.emit(depth, context))
	controller.reward_offered.connect(func(offer: Dictionary) -> void: reward_offered.emit(offer))
	controller.transition_failed.connect(_on_transition_failed)
	controller.run_ended.connect(func(summary: Dictionary) -> void: run_ended.emit(summary))
	controller.level_transition_committed.connect(func(result: Resource, context: StageContext) -> void: level_transition_committed.emit(result, context))

func retry_stage_clear() -> void:
	if controller == null: return
	controller.retry_stage_clear()

func _ensure_controller() -> bool:
	last_flow_error = ""
	if controller != null and is_instance_valid(controller): return true
	var packed := load(BOOTSTRAP_SCENE) as PackedScene
	if packed == null:
		last_flow_error = "Run startup scene could not be loaded."
		return false
	bootstrap = packed.instantiate() as RunBootstrap
	bootstrap.autostart = false
	# The front end always processes (menus work while paused); gameplay must freeze with the tree.
	bootstrap.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(bootstrap)
	if bootstrap.run == null:
		last_flow_error = "Combat could not start because the native hit library is unavailable."
		bootstrap.queue_free()
		bootstrap = null
		return false
	controller = bootstrap.run
	controller.profile_store = profile_store
	controller.checkpoint_store = checkpoint_store
	controller.catalog = catalog
	_apply_run_options()
	attach_controller(controller)
	return true

func _apply_run_options() -> void:
	if controller == null or controller.player == null or controller.player.combat_controller == null: return
	var options_store: RefCounted = OPTIONS_STORE_SCRIPT.new()
	var settings: Dictionary = options_store.load_settings()
	controller.player.combat_controller.battery_drain_enabled = bool(settings.get("battery_drain_enabled", true))
	if controller.player.combat_controller.battery != null:
		controller.player.combat_controller.battery.drain_enabled = bool(settings.get("battery_drain_enabled", true))

func _on_transition_failed(error: String) -> void:
	last_flow_error = error
	transition_failed.emit(error)
