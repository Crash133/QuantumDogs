extends Node3D

@export_group("Practice Scene References")
@export var player_scene: PackedScene = preload("res://Scenes/Components/Player.tscn")
@export var camera_scene: PackedScene = preload("res://Scenes/Components/CameraRig.tscn")

@export_group("Crowd and Benchmark")
@export_range(1, 1000) var dummy_count: int = 200
@export var benchmark_ticks: int = 600
@export var benchmark_on_headless: bool = true
@export_enum("sphere", "capsule", "box", "cone", "ring") var benchmark_profile: String = "sphere"
@export var benchmark_weapon: StringName
@export var benchmark_warmup_ticks: int = 120
@export var benchmark_report_path: String
@export var benchmark_quit: bool = false
@export var practice_battery_drain: bool = false

var hit_manager: HitManagerNode
var sweep: HitboxProxy
var ticks: int = 0
var native_usec_total: int = 0
var maximum_native_usec: int = 0
var contacts_total: int = 0
var interactive: bool = true
var player: Player
var last_native_usec: int = 0
var _dummy_serial: int = 0
var incoming_hit_ticks_left: int = 0

func _ready() -> void:
	interactive = not benchmark_on_headless or DisplayServer.get_name() != "headless"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--combat-weapon="):
			benchmark_weapon = StringName(argument.trim_prefix("--combat-weapon="))
		elif argument.begins_with("--combat-report="):
			benchmark_report_path = argument.trim_prefix("--combat-report=")
		elif argument == "--combat-benchmark-quit":
			benchmark_quit = true
		if argument.begins_with("--combat-profile="):
			interactive = false
			var requested := argument.trim_prefix("--combat-profile=")
			if requested in ["sphere", "capsule", "box", "cone", "ring"]:
				benchmark_profile = requested
	if benchmark_weapon != &"":
		if benchmark_weapon not in [&"mantis_blades", &"rocket_lance"]:
			push_error("Unsupported combat benchmark weapon: %s" % benchmark_weapon)
			get_tree().quit(1)
			return
		interactive = false
	hit_manager = $HitManager as HitManagerNode
	if hit_manager.native_manager == null or not hit_manager.native_manager.is_ready():
		# HitManagerNode requested a fatal exit. Do not construct combatants or
		# announce a playable lab while the tree is waiting to quit this frame.
		return
	hit_manager.native_step_finished.connect(_on_native_step)
	_spawn_dummies()
	if benchmark_weapon != &"":
		_build_player()
		var benchmark := CombatWeaponBenchmark.new()
		benchmark.name = "WeaponBenchmark"
		benchmark.arena = self
		add_child(benchmark)
	elif interactive:
		_build_player()
		var gizmos := CombatHitGizmos.new()
		gizmos.name = "HitGizmos"
		gizmos.manager = hit_manager
		gizmos.visible = false
		add_child(gizmos)
		var overlay := CombatDebugOverlay.new()
		overlay.name = "CombatDebugOverlay"
		overlay.arena = self
		overlay.player = player
		add_child(overlay)
		var bridge := get_node_or_null("/root/MCPBridge")
		if bridge != null:
			bridge.process_mode = Node.PROCESS_MODE_ALWAYS
		print("Combat practice arena ready: %d dummies (basic/Elite/flying)." % dummy_count)
	else:
		_build_sweeping_hitbox()
		print("Combat benchmark ready: %d dummies; build native/hit before starting." % dummy_count)

func _physics_process(_delta: float) -> void:
	if incoming_hit_ticks_left > 0 and is_instance_valid(player):
		incoming_hit_ticks_left -= 1
		if incoming_hit_ticks_left == 0:
			var hit := HitData.new()
			hit.damage = 10.0
			player.take_hit(hit)
	if sweep == null:
		return
	var angle := float(ticks) / 60.0
	sweep.global_position = Vector3(cos(angle) * 2.0, 1.0, sin(angle) * 2.0)
	sweep.global_basis = Basis(Vector3.UP, angle)

func queue_incoming_hit(delay_ticks: int = 60) -> void:
	incoming_hit_ticks_left = maxi(1, delay_ticks)

func _spawn_dummies() -> void:
	var radius := maxf(8.0, sqrt(float(dummy_count)) * 1.5)
	for index in range(dummy_count):
		var angle := float(index) * TAU / maxf(1.0, float(dummy_count))
		var distance := radius * sqrt(float(index) / maxf(1.0, float(dummy_count)))
		if interactive:
			distance = maxf(3.0, distance)
		var at := Vector3(cos(angle) * distance, 0.9, sin(angle) * distance)
		if interactive and index == 0:
			at = Vector3(0.0, 0.9, -3.0)
		spawn_dummy(interactive and index % 10 == 0, interactive and index % 10 == 1, at)

func spawn_dummy(elite: bool, flying: bool, at: Vector3) -> Combatant:
	var dummy: Combatant = CombatPracticeDummy.new() if interactive else Combatant.new()
	dummy.name = "Dummy_%03d" % _dummy_serial
	_dummy_serial += 1
	dummy.elite = elite
	dummy.flying = flying
	dummy.position = at
	if flying:
		dummy.position.y = maxf(dummy.position.y, 2.5)
	add_child(dummy)
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.45
	capsule.height = 1.8
	capsule.radial_segments = 8
	capsule.rings = 4
	mesh.mesh = capsule
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.ORANGE if elite else (Color.SKY_BLUE if flying else Color.GRAY)
	mesh.material_override = material
	dummy.add_child(mesh)
	var hurtbox := HurtboxProxy.new()
	hurtbox.name = "HurtboxProxy"
	hurtbox.combatant = dummy
	hurtbox.manager = hit_manager
	hurtbox.radius = 0.55
	hurtbox.height = 1.8
	dummy.add_child(hurtbox)
	return dummy

func _build_player() -> void:
	player = player_scene.instantiate() as Player
	player.name = "Player"
	# Live lab edits belong to this arena instance, never the cached .tres assets.
	var controller := player.get_node("CombatController") as CombatController
	if interactive:
		controller.battery_drain_enabled = practice_battery_drain
	var authored := controller.weapons if not controller.weapons.is_empty() else WeaponCatalog.create_default_weapons()
	controller.weapons = []
	for weapon in authored:
		controller.weapons.append(weapon.duplicate(true) as WeaponData)
	var camera := camera_scene.instantiate() as CameraRig
	camera.name = "CameraRig"
	var point := Node3D.new()
	point.name = "OrbitPoint"
	point.position.y = 1.2
	player.add_child(point)
	camera.orbit_point = point
	player.camera_rig = camera
	camera.get_node("PitchPivot/CameraShake/SpringArm3D").spring_length = 5.0
	camera.get_node("PitchPivot/CameraShake/SpringArm3D").position.y = 0.5
	add_child(player)
	add_child(camera)
	if interactive:
		var adapter := player.get_node("CombatHitAdapter") as CombatHitAdapter
		adapter.shot_resolved.connect(_show_revolver_shot)

func _show_revolver_shot(origin: Vector3, endpoint: Vector3, _target: Object, _hit: HitData) -> void:
	# Temporary lab feedback consumes the resolved contact; it never queries or
	# applies damage again. Authored benchmarks don't connect this presentation.
	var trace := MeshInstance3D.new()
	trace.name = "RevolverTrace"
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([origin, endpoint])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	trace.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.YELLOW
	trace.material_override = material
	add_child(trace)
	trace.top_level = true
	trace.global_transform = Transform3D.IDENTITY
	var lifetime := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	lifetime.tween_interval(0.1)
	lifetime.tween_callback(trace.queue_free)

func _build_sweeping_hitbox() -> void:
	sweep = $BenchmarkSweep as HitboxProxy
	sweep.profile_shape = StringName(benchmark_profile)
	match benchmark_profile:
		"sphere": sweep.profile_size = Vector3.ONE * 1.25
		"capsule": sweep.profile_size = Vector3(1.25, 0.0, 2.5)
		"box": sweep.profile_size = Vector3.ONE * 2.5
		"cone": sweep.profile_size = Vector3(30.0, 0.0, 2.5)
		"ring": sweep.profile_size = Vector3(1.25, 0.2, 0.2)
	sweep.linger_ticks = 8
	sweep.hit_spec = HitSpec.new()
	sweep.hit_spec.damage = 1.0
	sweep.owner_combatant = self
	sweep.manager_path = NodePath("../HitManager")
	sweep.refresh()
	sweep.set_active(true)

func _on_native_step(elapsed_usec: int, contact_count: int) -> void:
	last_native_usec = elapsed_usec
	if benchmark_weapon != &"":
		return
	if interactive:
		contacts_total += contact_count
		return
	if ticks >= benchmark_ticks:
		return
	native_usec_total += elapsed_usec
	maximum_native_usec = maxi(maximum_native_usec, elapsed_usec)
	contacts_total += contact_count
	ticks += 1
	if ticks == benchmark_ticks:
		var mean_usec := float(native_usec_total) / float(benchmark_ticks)
		print("Synthetic HitManager benchmark (%d ticks, %d dummies, %s): mean %.3f ms, max %.3f ms, contacts %d, sweep_exhaustions %d" % [benchmark_ticks, dummy_count, benchmark_profile, mean_usec / 1000.0, float(maximum_native_usec) / 1000.0, contacts_total, hit_manager.native_manager.get_sweep_exhaustions()])
