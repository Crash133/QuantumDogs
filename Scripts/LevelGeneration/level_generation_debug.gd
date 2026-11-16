extends Node3D
class_name LevelGenerationDebug

const RequestType = preload("res://Scripts/LevelGeneration/arena_generation_request.gd")
const GeneratorType = preload("res://Scripts/LevelGeneration/arena_generator.gd")
const MetricsType = preload("res://Scripts/LevelGeneration/spawn_pacing_metrics.gd")
const TuningType = preload("res://Scripts/LevelGeneration/spawn_pacing_tuning.gd")
const EncounterType = preload("res://Scripts/LevelGeneration/encounter_definition.gd")
const EntryType = preload("res://Scripts/LevelGeneration/encounter_entry.gd")
const PacingControllerType = preload("res://Scripts/LevelGeneration/spawn_pacing_controller.gd")
const PROFILE_IDS := ["plus_balcony", "column_corridor", "square_funnel", "balcony", "coliseum", "square"]

@export var default_profile: Resource
@export var pacing_tuning: Resource

var active_arena: Node3D
var last_result: Resource
var last_interval_ticks: int = 0
var last_request: RequestType
var _generation_ms: float = 0.0

@onready var _arena_container: Node3D = $ArenaContainer
@onready var _report: Label = %Report
@onready var _seed_input: LineEdit = %SeedInput
@onready var _profile_selector: OptionButton = %ProfileSelector
@onready var _rig: Node3D = $DebugRig

func _ready() -> void:
	_rig.panel = $CanvasLayer/Panel
	%WalkToggle.toggled.connect(set_walk_mode)
	%ResetViewButton.pressed.connect(reset_view)
	%GenerateButton.pressed.connect(_on_generate_pressed)
	%NextSeedButton.pressed.connect(func(): regenerate_from_controls(true))
	%AnchorToggle.toggled.connect(set_anchor_markers_visible)
	_profile_selector.add_item("Plus / balcony")
	_profile_selector.add_item("Column / corridor")
	_profile_selector.add_item("Square / funnel")
	_profile_selector.add_item("Balcony (T)")
	_profile_selector.add_item("Coliseum")
	_profile_selector.add_item("Square")
	_profile_selector.item_selected.connect(func(_index): regenerate_from_controls())
	for slider in [%StyleInput, %LivingInput, %HealthInput]:
		slider.value_changed.connect(func(_value): update_pacing_from_controls())
	if _seed_input != null:
		_seed_input.text = "8142"
	if default_profile != null:
		var request := _make_request(8142)
		generate_request(request, MetricsType.new())

func generate_request(request: RequestType, metrics: MetricsType = null) -> bool:
	var generator = GeneratorType.new()
	var started := Time.get_ticks_usec()
	var result = generator.generate(request)
	_generation_ms = float(Time.get_ticks_usec() - started) / 1000.0
	if result == null or not result.success or result.root == null:
		var failure := "Arena generation failed."
		if result != null:
			failure = result.error
		if _report != null:
			_report.text = failure
		return false
	# Generation and validation finish before this point; keep the current arena until now.
	var replacement: Node3D = result.root
	_arena_container.add_child(replacement)
	var previous := active_arena
	active_arena = replacement
	last_result = result
	last_request = request
	if previous != null and is_instance_valid(previous):
		_arena_container.remove_child(previous)
		previous.free()
	var effective_metrics: MetricsType = metrics if metrics != null else MetricsType.new()
	var tuning: TuningType = pacing_tuning as TuningType
	if tuning == null:
		tuning = TuningType.new()
	last_interval_ticks = PacingControllerType.new().get_interval_ticks(effective_metrics, tuning)
	_rebuild_anchor_markers()
	_reset_rig_to_start()
	_update_report(effective_metrics)
	return true

func _make_request(seed_value: int) -> RequestType:
	var request: RequestType = RequestType.new()
	request.run_seed = seed_value
	request.profile = default_profile
	var encounter: EncounterType = EncounterType.new()
	var entry: EntryType = EntryType.new()
	entry.enemy_id = &"grunt"
	entry.count = 8
	entry.spawn_tags.append(&"ground")
	encounter.entries.append(entry)
	request.encounter = encounter
	return request

func _on_generate_pressed() -> void:
	regenerate_from_controls()

func regenerate_from_controls(advance_seed: bool = false) -> bool:
	var text := _seed_input.text.strip_edges()
	if not text.is_valid_int():
		_report.text = "Enter a whole-number seed. The current arena is still active."
		return false
	var digits := text.trim_prefix("+").trim_prefix("-").lstrip("0")
	var limit := "9223372036854775808" if text.begins_with("-") else "9223372036854775807"
	if digits.length() > limit.length() or (digits.length() == limit.length() and digits.casecmp_to(limit) > 0):
		_report.text = "Seed must be between -9223372036854775808 and 9223372036854775807. The current arena is still active."
		return false
	var seed_value := text.to_int()
	if advance_seed:
		seed_value = seed_value + 1 if seed_value < 9223372036854775807 else 0
	_seed_input.text = str(seed_value)
	var request := _make_request(seed_value)
	var profile_id: String = PROFILE_IDS[_profile_selector.selected]
	request.profile = load("res://Scenes/LevelGeneration/Profiles/%s.tres" % profile_id)
	return generate_request(request, _metrics_from_controls())

func _metrics_from_controls() -> MetricsType:
	var metrics := MetricsType.new()
	metrics.style_result = %StyleInput.value
	metrics.living_enemy_ratio = %LivingInput.value
	metrics.player_health_ratio = %HealthInput.value
	return metrics

func update_pacing_from_controls() -> void:
	var metrics := _metrics_from_controls()
	var tuning := pacing_tuning as TuningType
	if tuning == null:
		tuning = TuningType.new()
	last_interval_ticks = PacingControllerType.new().get_interval_ticks(metrics, tuning)
	_update_report(metrics)

func set_anchor_markers_visible(enabled: bool) -> void:
	$AnchorMarkers.visible = enabled

func set_walk_mode(enabled: bool) -> void:
	%WalkToggle.set_pressed_no_signal(enabled)
	_rig.set_walk_mode(enabled)
	%ModeHint.text = "WALK: click the arena to look.\nWASD move | Space jump\nEscape releases the mouse." if enabled else "OVERVIEW: right-drag to orbit.\nMouse wheel zooms.\nAmber: start | Teal: spawn anchors."

func reset_view() -> void:
	_reset_rig_to_start()
	if not _rig.walk_mode:
		_rig.reset_overview()

func _reset_rig_to_start() -> void:
	if active_arena == null:
		return
	var start := active_arena.find_child("PlayerStart", true, false) as Node3D
	if start != null:
		_rig.reset_to_start(start.global_transform)

func _rebuild_anchor_markers() -> void:
	for child in $AnchorMarkers.get_children():
		child.free()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.1, 0.9, 0.85)
	for anchor in last_result.spawn_anchors:
		var marker := MeshInstance3D.new()
		marker.mesh = sphere
		marker.material_override = material
		$AnchorMarkers.add_child(marker)
		marker.global_position = anchor.global_position + Vector3.UP * 0.2
	var start := active_arena.find_child("PlayerStart", true, false) as Node3D
	if start != null:
		var marker := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.3
		mesh.bottom_radius = 0.3
		mesh.height = 0.08
		marker.mesh = mesh
		var start_material := material.duplicate() as StandardMaterial3D
		start_material.albedo_color = Color(1.0, 0.75, 0.15)
		marker.material_override = start_material
		$AnchorMarkers.add_child(marker)
		marker.global_position = start.global_position

func _update_report(metrics: MetricsType) -> void:
	if _report == null or last_result == null:
		return
	var module_ids: Dictionary = {}
	for placement in last_result.placements:
		var module_id: String = String(placement.definition.module_id)
		module_ids[module_id] = module_ids.get(module_id, 0) + 1
	var module_lines: Array[String] = []
	for module_id in module_ids:
		module_lines.append("%s x%d" % [module_id, module_ids[module_id]])
	var tag_names: Dictionary = {}
	for anchor in last_result.spawn_anchors:
		for tag in anchor.tags:
			tag_names[tag] = true
	var tags: Array[String] = []
	for tag in tag_names:
		tags.append(String(tag))
	tags.sort()
	_report.text = "Seed: %d\nSilhouette: %s\nModules: %d\nAnchors: %d (%s)\nFallback: %s | Attempts: %d\nGeneration: %.1f ms\n\nMetrics (Style / living / health):\n%.2f / %.2f / %.2f\nInterval: %d ticks (60 Hz)\nNeutral curves are active.\n\nModule catalogue:\n%s" % [
		last_result.seed,
		last_result.silhouette_id,
		last_result.placements.size(),
		last_result.spawn_anchors.size(),
		", ".join(tags),
		str(last_result.diagnostics.get("fallback_used", false)),
		last_result.diagnostics.get("attempts", 1),
		_generation_ms,
		metrics.normalized_style_result(),
		metrics.normalized_living_enemy_ratio(),
		metrics.normalized_player_health_ratio(),
		last_interval_ticks,
		"\n".join(module_lines),
	]
