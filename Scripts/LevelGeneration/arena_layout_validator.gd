extends RefCounted
class_name ArenaLayoutValidator

const GRID_SIZE: int = 9
const RequestType = preload("res://Scripts/LevelGeneration/arena_generation_request.gd")
const PlacementType = preload("res://Scripts/LevelGeneration/arena_module_placement.gd")
const AnchorType = preload("res://Scripts/LevelGeneration/arena_spawn_anchor.gd")
const SocketType = preload("res://Scripts/LevelGeneration/arena_socket_definition.gd")

func validate(request: RequestType, placements: Array[PlacementType], anchors: Array[AnchorType]) -> Array[String]:
	var errors: Array[String] = []
	if request == null or request.profile == null or request.encounter == null:
		errors.append("Layout validation requires a complete generation request.")
		return errors
	var profile = request.profile
	var silhouette_id: StringName = _silhouette_for_placements(placements, profile)
	var footprint: Variant = profile.normalized_footprints.get(silhouette_id)
	if not footprint is PackedVector2Array:
		errors.append("Layout has no normalized silhouette footprint.")
	else:
		_validate_footprint(placements, footprint, profile.module_unit_size, errors)
	_validate_overlaps(placements, errors)
	_validate_connectivity(placements, errors)
	_validate_player_start(placements, errors)
	_validate_anchors(request.encounter, anchors, errors, request.max_concurrent)
	return errors

func _silhouette_for_placements(placements: Array, profile) -> StringName:
	for silhouette_id in profile.allowed_silhouettes:
		var core = profile.core_modules.get(silhouette_id)
		if core == null:
			continue
		for placement in placements:
			if placement is PlacementType and placement.definition.module_id == core.module_id:
				return silhouette_id
	# Fallback layouts retain their selected silhouette on their module definitions.
	for silhouette_id in profile.allowed_silhouettes:
		var footprint: Variant = profile.normalized_footprints.get(silhouette_id)
		for placement in placements:
			if placement is PlacementType and placement.definition.supported_silhouettes.has(silhouette_id):
				return silhouette_id
	return &""

func _validate_footprint(placements: Array, footprint: PackedVector2Array, unit_size: float, errors: Array[String]) -> void:
	var world_span := GRID_SIZE * unit_size
	var tolerance := 0.5 / GRID_SIZE
	for placement in placements:
		if not placement is PlacementType or placement.definition == null:
			errors.append("Layout contains an invalid module placement.")
			continue
		var bounds: Rect2 = _world_bounds(placement.definition.local_bounds, placement.transform)
		var corners := [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]
		for corner in corners:
			var normalized := Vector2(corner.x / world_span + 0.5, corner.y / world_span + 0.5)
			if not Geometry2D.is_point_in_polygon(normalized, footprint) and _distance_to_polygon(normalized, footprint) > tolerance:
				errors.append("Module '%s' extends outside the silhouette footprint." % placement.definition.module_id)
				break

func _validate_overlaps(placements: Array, errors: Array[String]) -> void:
	for i in range(placements.size()):
		var first = placements[i]
		if not first is PlacementType or first.definition == null:
			continue
		var first_bounds := _world_bounds(first.definition.local_bounds, first.transform)
		for j in range(i + 1, placements.size()):
			var second = placements[j]
			if not second is PlacementType or second.definition == null:
				continue
			var second_bounds := _world_bounds(second.definition.local_bounds, second.transform)
			if first_bounds.position.x < second_bounds.end.x - 0.001 and first_bounds.end.x > second_bounds.position.x + 0.001 and first_bounds.position.y < second_bounds.end.y - 0.001 and first_bounds.end.y > second_bounds.position.y + 0.001:
				errors.append("Module overlap between '%s' and '%s'." % [first.definition.module_id, second.definition.module_id])
				return

func _validate_connectivity(placements: Array, errors: Array[String]) -> void:
	if placements.size() <= 1:
		return
	var reached := {0: true}
	var pending: Array[int] = [0]
	while not pending.is_empty():
		var current_index: int = pending.pop_front()
		for other_index in range(placements.size()):
			if reached.has(other_index) or other_index == current_index:
				continue
			if _placements_have_matching_socket(placements[current_index], placements[other_index]):
				reached[other_index] = true
				pending.append(other_index)
	if reached.size() != placements.size():
		errors.append("Walkable module graph is not connected through compatible sockets.")

func _placements_have_matching_socket(first, second) -> bool:
	if not first is PlacementType or not second is PlacementType or first.instance == null or second.instance == null:
		return false
	var first_sockets := _socket_transforms(first)
	var second_sockets := _socket_transforms(second)
	for first_socket in first_sockets:
		for second_socket in second_sockets:
			if first_socket.tag == second_socket.tag and first_socket.transform.origin.distance_to(second_socket.transform.origin) <= 0.05 and first_socket.transform.basis.z.dot(second_socket.transform.basis.z) < -0.9:
				return true
	return false

func _socket_transforms(placement) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for socket_id in [&"north", &"east", &"south", &"west"]:
		var socket: SocketType = null
		for candidate in placement.definition.sockets:
			if candidate != null and candidate.socket_id == socket_id and candidate.is_walkable:
				socket = candidate
				break
		if socket == null:
			var marker_name := "Socket%s" % String(socket_id).capitalize()
			var marker := placement.instance.find_child(marker_name, true, false) as Node3D
			if marker == null:
				continue
			var world_transform: Transform3D = placement.transform * marker.transform
			found.append({"tag": &"walkable_floor", "transform": world_transform})
		else:
			found.append({"tag": socket.compatibility_tag, "transform": placement.transform * socket.local_transform})
	return found

func _validate_player_start(placements: Array, errors: Array[String]) -> void:
	var starts := 0
	for placement in placements:
		if not placement is PlacementType or placement.instance == null:
			continue
		for node in placement.instance.find_children("PlayerStart", "Marker3D", true, false):
			starts += 1
	if starts != 1:
		errors.append("Layout must contain exactly one PlayerStart marker; found %d." % starts)

func _validate_anchors(encounter, anchors: Array, errors: Array[String], max_concurrent: int = 0) -> void:
	var total_capacity := 0
	var valid_tags := {}
	for anchor in anchors:
		if not anchor is AnchorType:
			errors.append("Layout contains an invalid spawn anchor.")
			continue
		if anchor.tags.is_empty():
			errors.append("Spawn anchor has no valid tags.")
		for tag in anchor.tags:
			if tag.is_empty():
				errors.append("Spawn anchor has an empty tag.")
			else:
				valid_tags[tag] = true
		total_capacity += maxi(anchor.capacity, 0)
	var required_capacity := 0
	for entry in encounter.entries:
		if entry == null or entry.count <= 0:
			continue
		required_capacity += entry.count
		if not entry.spawn_tags.is_empty():
			var has_compatible_tag := false
			for tag in entry.spawn_tags:
				if valid_tags.has(tag):
					has_compatible_tag = true
				else:
					errors.append("Encounter spawn tag '%s' has no matching anchor." % tag)
			if not has_compatible_tag:
				errors.append("Encounter entry has no compatible spawn anchor tags.")
	if max_concurrent > 0:
		required_capacity = mini(required_capacity, max_concurrent)
	if total_capacity < required_capacity:
		errors.append("Spawn anchor capacity %d is below encounter count %d." % [total_capacity, required_capacity])

func _world_bounds(local_bounds: Rect2, placement_transform: Transform3D) -> Rect2:
	var corners := [Vector3(local_bounds.position.x, 0, local_bounds.position.y), Vector3(local_bounds.end.x, 0, local_bounds.position.y), Vector3(local_bounds.end.x, 0, local_bounds.end.y), Vector3(local_bounds.position.x, 0, local_bounds.end.y)]
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

func _distance_to_polygon(point: Vector2, polygon: PackedVector2Array) -> float:
	var minimum := INF
	for index in range(polygon.size()):
		var a: Vector2 = polygon[index]
		var b: Vector2 = polygon[(index + 1) % polygon.size()]
		var segment := b - a
		var t := clampf((point - a).dot(segment) / maxf(segment.length_squared(), 0.000001), 0.0, 1.0)
		minimum = minf(minimum, point.distance_to(a + segment * t))
	return minimum
