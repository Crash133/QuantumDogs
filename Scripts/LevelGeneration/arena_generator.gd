extends RefCounted
class_name ArenaGenerator

const RequestType = preload("res://Scripts/LevelGeneration/arena_generation_request.gd")
const ResultType = preload("res://Scripts/LevelGeneration/arena_generation_result.gd")
const PlacementType = preload("res://Scripts/LevelGeneration/arena_module_placement.gd")
const ModuleType = preload("res://Scripts/LevelGeneration/arena_module_definition.gd")
const SocketType = preload("res://Scripts/LevelGeneration/arena_socket_definition.gd")
const SpawnAnchorType = preload("res://Scripts/LevelGeneration/arena_spawn_anchor.gd")
const ValidatorType = preload("res://Scripts/LevelGeneration/arena_layout_validator.gd")
const GRID_SIZE: int = 9
const DIRECTIONS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const SOCKET_IDS: Array[StringName] = [&"north", &"east", &"south", &"west"]

## Optional, set only by generate_sliced(): awaited after each module placement
## so the caller can spread work across frames. Invalid = fully synchronous.
var slicer: Callable

func generate(request: RequestType) -> ResultType:
	# Dynamic call: _generate never suspends without a slicer, so this stays synchronous.
	return call("_generate", request)

## Same result as generate() for the same request; yields via frame_slicer
## between module placements. One call at a time per generator instance.
func generate_sliced(request: RequestType, frame_slicer: Callable) -> ResultType:
	slicer = frame_slicer
	var result: ResultType = await _generate(request)
	slicer = Callable()
	return result

func _generate(request: RequestType) -> ResultType:
	if request == null:
		return _failure(0, &"", "Arena generation request is null.")
	var request_errors: PackedStringArray = request.validate()
	if not request_errors.is_empty():
		return _failure(request.run_seed, &"", "; ".join(request_errors))
	var last_error := "No generation attempt was made."
	var last_silhouette: StringName = &""
	for attempt in range(request.profile.max_attempts):
		var attempt_seed := _derive_seed(request.run_seed, request.ascent_depth, attempt)
		var rng := RandomNumberGenerator.new()
		rng.seed = attempt_seed
		var silhouette_id: StringName = request.profile.choose_silhouette(rng)
		last_silhouette = silhouette_id
		var assembly: Dictionary = await _assemble(request, silhouette_id, rng, attempt_seed)
		if assembly.get("success", false):
			var result: ResultType = assembly["result"]
			var validation_errors: Array[String] = ValidatorType.new().validate(request, result.placements, result.spawn_anchors)
			if not validation_errors.is_empty():
				last_error = "; ".join(validation_errors)
				if result.root != null:
					result.root.free()
				continue
			result.seed = request.run_seed
			result.diagnostics["attempt"] = attempt + 1
			result.diagnostics["attempts"] = attempt + 1
			result.diagnostics["attempt_seed"] = attempt_seed
			result.diagnostics["fallback_used"] = false
			return result
		last_error = String(assembly.get("error", "Assembly failed."))
	return _build_fallback(request, last_silhouette, last_error)

func _build_fallback(request: RequestType, silhouette_id: StringName, generation_error: String) -> ResultType:
	var fallback_scene: Variant = request.profile.fallback_scenes.get(silhouette_id)
	if not fallback_scene is PackedScene:
		return _failure(request.run_seed, silhouette_id, "Generation failed after %d attempts: %s Fallback scene is missing for '%s'." % [request.profile.max_attempts, generation_error, silhouette_id])
	var fallback_layout = fallback_scene.instantiate()
	if fallback_layout == null or not fallback_layout.has_method("build_fallback"):
		if fallback_layout != null:
			fallback_layout.free()
		return _failure(request.run_seed, silhouette_id, "Generation failed after %d attempts: %s Fallback scene is invalid." % [request.profile.max_attempts, generation_error])
	var layout_root := Node3D.new()
	layout_root.name = "GeneratedArenaFallback"
	layout_root.add_child(fallback_layout)
	var fallback_data: Dictionary = fallback_layout.call("build_fallback", request.profile, _derive_seed(request.run_seed, request.ascent_depth, request.profile.max_attempts))
	var placements: Array[PlacementType] = []
	var anchors: Array[SpawnAnchorType] = []
	for placement in fallback_data.get("placements", []):
		if placement is PlacementType:
			placements.append(placement)
	for anchor in fallback_data.get("spawn_anchors", []):
		if anchor is SpawnAnchorType:
			anchors.append(anchor)
	var fallback_errors: PackedStringArray = fallback_data.get("errors", PackedStringArray())
	if fallback_errors.is_empty():
		var validator_errors: Array[String] = ValidatorType.new().validate(request, placements, anchors)
		fallback_errors.append_array(PackedStringArray(validator_errors))
	if not fallback_errors.is_empty():
		layout_root.free()
		return _failure(request.run_seed, silhouette_id, "Generation failed after %d attempts: %s Fallback validation failed: %s" % [request.profile.max_attempts, generation_error, "; ".join(fallback_errors)])
	var result: ResultType = ResultType.new()
	result.success = true
	result.seed = request.run_seed
	result.silhouette_id = silhouette_id
	result.root = layout_root
	for placement in placements:
		result.placements.append(placement)
	for anchor in anchors:
		result.spawn_anchors.append(anchor)
	result.diagnostics = {
		"module_ids": _module_ids(result.placements),
		"module_count": result.placements.size(),
		"anchor_count": result.spawn_anchors.size(),
		"layout_signature": _layout_signature(silhouette_id, result.placements),
		"attempts": request.profile.max_attempts,
		"fallback_used": true,
		"generation_error": generation_error,
		"fallback_seed": _derive_seed(request.run_seed, request.ascent_depth, request.profile.max_attempts),
	}
	return result

func _assemble(request: RequestType, silhouette_id: StringName, rng: RandomNumberGenerator, attempt_seed: int) -> Dictionary:
	var profile = request.profile
	var footprint: Variant = profile.normalized_footprints.get(silhouette_id)
	if not footprint is PackedVector2Array:
		return {"success": false, "error": "No normalized footprint for '%s'." % silhouette_id}
	var target_cells := _cells_inside_footprint(footprint)
	if target_cells.is_empty():
		return {"success": false, "error": "Footprint for '%s' contains no module cells." % silhouette_id}
	var core_cell := _closest_cell_to_center(target_cells)
	var core_definition: Variant = profile.core_modules.get(silhouette_id)
	if not core_definition is ModuleType:
		return {"success": false, "error": "Profile has no core module for '%s'." % silhouette_id}
	var core_errors: PackedStringArray = core_definition.validate()
	if not core_errors.is_empty():
		return {"success": false, "error": "; ".join(core_errors)}
	_ensure_sockets(core_definition)
	var available_modules := _compatible_modules(profile.module_catalogue, silhouette_id)
	if available_modules.is_empty():
		return {"success": false, "error": "Profile has no compatible modules for '%s'." % silhouette_id}
	var result: ResultType = ResultType.new()
	result.success = true
	result.seed = request.run_seed
	result.silhouette_id = silhouette_id
	result.root = Node3D.new()
	result.root.name = "GeneratedArena"
	var placements_by_cell := {}
	var core_transform := Transform3D(Basis.IDENTITY, Vector3.ZERO)
	var core_placement: PlacementType = _make_placement(core_definition, core_transform, attempt_seed, core_cell, profile.module_unit_size)
	if core_placement == null:
		return _assembly_failure(result.root, "Core module scene must have a Node3D root.")
	result.root.add_child(core_placement.instance)
	result.placements.append(core_placement)
	placements_by_cell[_cell_key(core_cell)] = core_placement
	var pending: Array[Vector2i] = []
	for cell in target_cells:
		if cell != core_cell:
			pending.append(cell)
	while not pending.is_empty():
		var frontier := _frontier(pending, placements_by_cell)
		if frontier.is_empty():
			return _assembly_failure(result.root, "Footprint for '%s' is disconnected." % silhouette_id)
		var edge: Dictionary = frontier[rng.randi_range(0, frontier.size() - 1)]
		var child_cell: Vector2i = edge["cell"]
		var parent_cell: Vector2i = edge["parent"]
		var direction_index: int = edge["direction"]
		var parent_placement: PlacementType = placements_by_cell[_cell_key(parent_cell)]
		var child_definition: ModuleType = available_modules[rng.randi_range(0, available_modules.size() - 1)]
		var parent_socket: SocketType = _get_socket(parent_placement.definition, SOCKET_IDS[direction_index])
		var child_socket: SocketType = _get_socket(child_definition, SOCKET_IDS[(direction_index + 2) % 4])
		if parent_socket == null or child_socket == null or parent_socket.compatibility_tag != child_socket.compatibility_tag:
			return _assembly_failure(result.root, "Module connector compatibility failed at %s." % _cell_key(child_cell))
		var socket_world: Transform3D = parent_placement.transform * parent_socket.local_transform
		var child_socket_target := Transform3D(socket_world.basis.rotated(Vector3.UP, PI), socket_world.origin)
		var child_transform: Transform3D = child_socket_target * child_socket.local_transform.affine_inverse()
		if _overlaps_existing(child_definition, child_transform, result.placements):
			return _assembly_failure(result.root, "Module overlap at %s." % _cell_key(child_cell))
		var child_placement := _make_placement(child_definition, child_transform, attempt_seed, child_cell, profile.module_unit_size)
		if child_placement == null:
			return _assembly_failure(result.root, "Module '%s' scene must have a Node3D root." % child_definition.module_id)
		result.root.add_child(child_placement.instance)
		result.placements.append(child_placement)
		placements_by_cell[_cell_key(child_cell)] = child_placement
		pending.erase(child_cell)
		if slicer.is_valid():
			await slicer.call()
	result.spawn_anchors = _collect_spawn_anchors(result.root)
	result.diagnostics = {
		"module_ids": _module_ids(result.placements),
		"module_count": result.placements.size(),
		"anchor_count": result.spawn_anchors.size(),
		"layout_signature": _layout_signature(silhouette_id, result.placements),
		"fallback_used": false,
	}
	return {"success": true, "result": result}

func _cells_inside_footprint(footprint: PackedVector2Array) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for z in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var normalized_center := Vector2((float(x) + 0.5) / GRID_SIZE, (float(z) + 0.5) / GRID_SIZE)
			if Geometry2D.is_point_in_polygon(normalized_center, footprint):
				cells.append(Vector2i(x, z))
	return cells

func _closest_cell_to_center(cells: Array[Vector2i]) -> Vector2i:
	var best := cells[0]
	var best_distance := INF
	for cell in cells:
		var normalized_center := Vector2((float(cell.x) + 0.5) / GRID_SIZE, (float(cell.y) + 0.5) / GRID_SIZE)
		var distance := normalized_center.distance_squared_to(Vector2(0.5, 0.5))
		if distance < best_distance:
			best = cell
			best_distance = distance
	return best

func _frontier(pending: Array[Vector2i], placements_by_cell: Dictionary) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for cell in pending:
		for direction_index in range(DIRECTIONS.size()):
			var neighbor: Vector2i = cell + DIRECTIONS[direction_index]
			if placements_by_cell.has(_cell_key(neighbor)):
				candidates.append({"cell": cell, "parent": neighbor, "direction": (direction_index + 2) % 4})
	return candidates

func _compatible_modules(catalogue: Array, silhouette_id: StringName) -> Array[ModuleType]:
	var compatible: Array[ModuleType] = []
	for module_value in catalogue:
		if not module_value is ModuleType:
			continue
		var module: ModuleType = module_value
		if module.supported_silhouettes.has(silhouette_id) and module.scene != null:
			_ensure_sockets(module)
			if not module.validate().is_empty():
				continue
			compatible.append(module)
	return compatible

func _ensure_sockets(definition: ModuleType) -> void:
	if not definition.sockets.is_empty() or definition.scene == null:
		return
	var preview := definition.scene.instantiate()
	if preview == null:
		return
	for socket_id in SOCKET_IDS:
		var marker_name := "Socket%s" % String(socket_id).capitalize()
		var marker := preview.find_child(marker_name, true, false) as Node3D
		if marker == null:
			continue
		var socket: SocketType = SocketType.new()
		socket.socket_id = socket_id
		socket.local_transform = marker.transform
		socket.compatibility_tag = &"walkable_floor"
		socket.is_walkable = true
		definition.sockets.append(socket)
	preview.free()

func _get_socket(definition: ModuleType, socket_id: StringName) -> SocketType:
	for socket in definition.sockets:
		if socket.socket_id == socket_id and socket.is_walkable:
			return socket
	return null

func _make_placement(definition: ModuleType, placement_transform: Transform3D, seed_value: int, grid_cell: Vector2i, unit_size: float) -> PlacementType:
	var instance := definition.scene.instantiate() as Node3D
	if instance == null:
		return null
	instance.name = "%s_%d_%d" % [definition.module_id, grid_cell.x, grid_cell.y]
	if instance.has_method("configure"):
		instance.call("configure", seed_value, grid_cell, unit_size, definition.module_id)
	instance.transform = placement_transform
	var placement: PlacementType = PlacementType.new()
	placement.definition = definition
	placement.transform = placement_transform
	placement.instance = instance
	return placement

func _overlaps_existing(definition: ModuleType, placement_transform: Transform3D, existing: Array[PlacementType]) -> bool:
	var candidate := _world_bounds(definition, placement_transform)
	for placement in existing:
		var other := _world_bounds(placement.definition, placement.transform)
		if candidate.position.x < other.end.x - 0.001 and candidate.end.x > other.position.x + 0.001 and candidate.position.y < other.end.y - 0.001 and candidate.end.y > other.position.y + 0.001:
			return true
	return false

func _world_bounds(definition: ModuleType, placement_transform: Transform3D) -> Rect2:
	var bounds: Rect2 = definition.local_bounds
	var corners := [
		Vector3(bounds.position.x, 0.0, bounds.position.y),
		Vector3(bounds.end.x, 0.0, bounds.position.y),
		Vector3(bounds.end.x, 0.0, bounds.end.y),
		Vector3(bounds.position.x, 0.0, bounds.end.y),
	]
	var min_x := INF
	var min_z := INF
	var max_x := -INF
	var max_z := -INF
	for corner in corners:
		var world_corner: Vector3 = placement_transform * corner
		min_x = minf(min_x, world_corner.x)
		min_z = minf(min_z, world_corner.z)
		max_x = maxf(max_x, world_corner.x)
		max_z = maxf(max_z, world_corner.z)
	return Rect2(Vector2(min_x, min_z), Vector2(max_x - min_x, max_z - min_z))

func _collect_spawn_anchors(root: Node3D) -> Array[SpawnAnchorType]:
	var anchors: Array[SpawnAnchorType] = []
	for node in root.find_children("*", "Marker3D", true, false):
		if node is SpawnAnchorType:
			anchors.append(node)
	return anchors

func _module_ids(placements: Array[PlacementType]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for placement in placements:
		ids.append(placement.definition.module_id)
	return ids

func _layout_signature(silhouette_id: StringName, placements: Array[PlacementType]) -> String:
	var parts: Array[String] = []
	for placement in placements:
		parts.append("%s@%.3f,%.3f" % [placement.definition.module_id, placement.transform.origin.x, placement.transform.origin.z])
	return "%s|%s" % [silhouette_id, ",".join(parts)]

func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

func _derive_seed(run_seed: int, ascent_depth: int, attempt: int) -> int:
	return run_seed ^ (ascent_depth * 73856093) ^ (attempt * 19349663)

func _failure(seed_value: int, silhouette_id: StringName, message: String) -> ResultType:
	var result: ResultType = ResultType.new()
	result.success = false
	result.seed = seed_value
	result.silhouette_id = silhouette_id
	result.error = message
	result.diagnostics = {"validation_errors": PackedStringArray([message]), "fallback_used": false}
	return result

func _assembly_failure(root: Node3D, message: String) -> Dictionary:
	if root != null and is_instance_valid(root):
		root.free()
	return {"success": false, "error": message}
