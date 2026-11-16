class_name CombatWeaponBenchmark
extends Node

signal finished(result: Dictionary)

var arena: Node3D
var report: Dictionary = {}
var _player: Player
var _controller: CombatController
var _manager: HitManagerNode
var _completed: int = 0
var _warmup: int
var _sample_ticks: int
var _contacts: int = 0
var _attacks: int = 0
var _nodes: Array[StringName] = []
var _profiles: Array[StringName] = []
var _native: Array[float] = []
var _callback: Array[float] = []
var _frame_wall: Array[float] = []
var _frame_cpu: Array[float] = []
var _physics_cpu: Array[float] = []
var _native_by_node: Dictionary = {}
var _previous_frame: int = 0
var _previous_position: Vector3
var _distance: float = 0.0
var _circle_loops: int = 0
const MOVE_ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_forward", &"move_backwards"]

func _ready() -> void:
	process_physics_priority = -2
	_player = arena.get("player") as Player
	_controller = _player.combat_controller
	_manager = arena.get("hit_manager") as HitManagerNode
	_warmup = maxi(0, int(arena.get("benchmark_warmup_ticks")))
	_sample_ticks = maxi(1, int(arena.get("benchmark_ticks")))
	_controller.set_physics_process(false)
	_controller.battery_drain_enabled = false
	for weapon in _controller.weapons:
		if weapon.id == arena.get("benchmark_weapon"):
			_controller.combo.set_weapon(weapon)
	_controller.combo.advanced.connect(_on_attack)
	_manager.contact_step_finished.connect(_on_contact_step)
	var index := 0
	for child in arena.get_children():
		if not child is Combatant:
			continue
		# Dense, deterministic load fixture. Dummies remain alive and registered;
		# real weapon HitSpecs, damage resolution and CombatEvents still run.
		var angle := float(index % 40) * TAU / 40.0 + float(index / 40) * 0.07
		var radius := 2.0 + float(index / 40)
		child.position = Vector3(cos(angle) * radius, 0.9, sin(angle) * radius)
		child.maximum_health = 1000000.0
		child.health = child.maximum_health
		index += 1
	_previous_position = _player.global_position
	print("Authored combat benchmark ready: %s, %d dummies, %d warmup + %d measured ticks" % [_controller.combo.weapon.id, index, _warmup, _sample_ticks])

func _physics_process(_delta: float) -> void:
	if not report.is_empty():
		return
	var angle := float(_completed) / 60.0 * 1.3
	var waypoint := Vector3(cos(angle) * 3.0, 0.0, sin(angle) * 3.0)
	var desired := waypoint - _player.global_position
	desired.y = 0.0
	desired = desired.normalized()
	var basis := _player.camera_rig.global_basis
	var right := basis.x
	var forward := -basis.z
	right.y = 0.0
	forward.y = 0.0
	var horizontal := desired.dot(right.normalized())
	var vertical := desired.dot(forward.normalized())
	_move(&"move_left", maxf(0.0, -horizontal))
	_move(&"move_right", maxf(0.0, horizontal))
	_move(&"move_forward", maxf(0.0, vertical))
	_move(&"move_backwards", maxf(0.0, -vertical))
	_player.sample_combat_movement()
	var actions: Array[StringName] = []
	var node := _controller.combo.current_node
	if node == null:
		actions.append(&"light")
		_circle_loops = 0
	elif _controller.combo.node_tick >= node.input_window.y:
		var loop: ComboEdge
		var exit: ComboEdge
		for edge in node.edges:
			if edge.target == node.id:
				loop = edge
			elif exit == null:
				exit = edge
		# Self-looping nodes would repeat forever: leave by their other edge,
		# or take a lone loop once.
		if loop != null and exit != null:
			actions.append(exit.input)
		elif loop != null:
			if _circle_loops == 0:
				actions.append(loop.input)
				_circle_loops += 1
		elif not node.edges.is_empty():
			actions.append(&"light")
	_controller.step(actions)

func _move(action: StringName, strength: float) -> void:
	if strength > 0.001:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)

func _on_attack(_weapon: StringName, node: StringName, _depth: int) -> void:
	if _completed < _warmup:
		return
	_attacks += 1
	if node not in _nodes:
		_nodes.append(node)

func _on_contact_step(native_usec: int, total_usec: int, contacts: int) -> void:
	if not report.is_empty():
		return
	_completed += 1
	var position := _player.global_position
	if _completed > _warmup:
		_native.append(float(native_usec) / 1000.0)
		_callback.append(float(total_usec) / 1000.0)
		var node := _controller.combo.current_node
		var key := node.id if node != null else &"Rest"
		if not _native_by_node.has(key):
			_native_by_node[key] = [] as Array[float]
		_native_by_node[key].append(float(native_usec) / 1000.0)
		_contacts += contacts
		_distance += position.distance_to(_previous_position)
		for proxy: HitboxProxy in _manager.hitboxes.values():
			if proxy.is_active and proxy.profile_shape not in _profiles:
				_profiles.append(proxy.profile_shape)
	_previous_position = position
	if _completed == _warmup + _sample_ticks:
		_finish()

func _process(_delta: float) -> void:
	if _completed <= _warmup or not report.is_empty():
		return
	var now := Time.get_ticks_usec()
	if _previous_frame > 0:
		_frame_wall.append(float(now - _previous_frame) / 1000.0)
	_previous_frame = now
	# Engine monitors describe the previous completed engine frame. They are CPU
	# timings, not GPU timings or the fixed simulation delta.
	_frame_cpu.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_physics_cpu.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)

static func summarize(samples: Array[float]) -> Dictionary:
	if samples.is_empty():
		return {&"samples": 0, &"mean": 0.0, &"max": 0.0, &"p95": 0.0}
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for sample in samples:
		total += sample
	return {&"samples": samples.size(), &"mean": total / samples.size(), &"max": sorted[-1], &"p95": sorted[maxi(0, ceili(float(sorted.size()) * 0.95) - 1)]}

func _finish() -> void:
	_release_movement()
	set_physics_process(false)
	var node_timings := {}
	for key in _native_by_node:
		node_timings[key] = summarize(_native_by_node[key])
	report = {
		&"weapon_id": _controller.combo.weapon.id,
		&"dummy_count": int(arena.get("dummy_count")),
		&"registered_hurtboxes": _manager.hurtboxes.size(),
		&"warmup_ticks": _warmup, &"measured_ticks": _native.size(),
		&"contacts": _contacts, &"attacks_started": _attacks,
		&"visited_nodes": _nodes, &"profiles_seen": _profiles,
		&"movement_distance": _distance,
		&"native_ms": summarize(_native), &"contact_callback_ms": summarize(_callback),
		&"frame_wall_ms": summarize(_frame_wall), &"frame_cpu_ms": summarize(_frame_cpu),
		&"physics_cpu_ms": summarize(_physics_cpu),
		&"native_by_node_ms": node_timings,
		&"engine_cpu_monitors_are_coarse": true,
		&"sweep_exhaustions": _manager.native_manager.get_sweep_exhaustions(),
		&"native_max_within_1ms": _native.max() <= 1.0,
		&"target_hardware_verified": false,
		&"engine": Engine.get_version_info().string,
		&"platform": OS.get_name(), &"cpu": OS.get_processor_name(),
		&"display": DisplayServer.get_name(),
		&"gpu": RenderingServer.get_video_adapter_name(),
		&"debug_build": OS.is_debug_build(),
		&"fixed_fps": "--fixed-fps" in OS.get_cmdline_args(),
	}
	var path := String(arena.get("benchmark_report_path"))
	if not path.is_empty():
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "\t"))
		else:
			push_error("Could not write combat benchmark report: %s" % path)
	print("AUTHORED_COMBAT_BENCHMARK " + JSON.stringify(report))
	_controller.combo.cancel()
	finished.emit(report)
	if bool(arena.get("benchmark_quit")):
		get_tree().quit()

func _release_movement() -> void:
	for action in MOVE_ACTIONS:
		Input.action_release(action)

func _exit_tree() -> void:
	_release_movement()
