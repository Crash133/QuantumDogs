extends Node3D
class_name ArenaFallbackLayout

const ProfileType = preload("res://Scripts/LevelGeneration/arena_profile.gd")
const ModuleType = preload("res://Scripts/LevelGeneration/arena_module_definition.gd")
const PlacementType = preload("res://Scripts/LevelGeneration/arena_module_placement.gd")
const SpawnAnchorType = preload("res://Scripts/LevelGeneration/arena_spawn_anchor.gd")
const GRID_SIZE: int = 9

@export var silhouette_id: StringName = &""
@export var core_scene: PackedScene
@export var tile_scene: PackedScene
var _placements: Array[PlacementType] = []
var _spawn_anchors: Array[SpawnAnchorType] = []

func build_fallback(profile: ProfileType, seed_value: int) -> Dictionary:
	_clear_layout()
	var errors := PackedStringArray()
	if profile == null:
		return {"placements": _placements, "spawn_anchors": _spawn_anchors, "errors": PackedStringArray(["Fallback profile is null."])}
	if not profile.allowed_silhouettes.has(silhouette_id):
		errors.append("Fallback silhouette '%s' is outside the profile allow-list." % silhouette_id)
	var footprint_value: Variant = profile.normalized_footprints.get(silhouette_id)
	if not footprint_value is PackedVector2Array:
		errors.append("Fallback silhouette '%s' has no normalized footprint." % silhouette_id)
	if not errors.is_empty():
		return {"placements": _placements, "spawn_anchors": _spawn_anchors, "errors": errors}
	var core_definition := _make_definition("fallback_core_%s" % silhouette_id, core_scene, silhouette_id)
	var tile_definition := _make_definition("fallback_tile_%s" % silhouette_id, tile_scene, silhouette_id)
	if core_definition == null:
		errors.append("Fallback scene has no independent core module scene.")
	if tile_definition == null:
		errors.append("Fallback scene has no independent ground tile scene.")
	if not errors.is_empty():
		return {"placements": _placements, "spawn_anchors": _spawn_anchors, "errors": errors}
	var cells := _cells_inside_footprint(footprint_value)
	if cells.size() < 4:
		errors.append("Fallback silhouette '%s' does not contain enough connected modules." % silhouette_id)
		return {"placements": _placements, "spawn_anchors": _spawn_anchors, "errors": errors}
	var center_cell := _closest_cell_to_center(cells)
	for cell in cells:
		var definition: ModuleType = core_definition if cell == center_cell else tile_definition
		var instance := definition.scene.instantiate() as Node3D
		if instance == null:
			errors.append("Fallback module '%s' has no Node3D scene root." % definition.module_id)
			continue
		instance.name = "%s_%d_%d" % [definition.module_id, cell.x, cell.y]
		if instance.has_method("configure"):
			instance.call("configure", seed_value, cell, profile.module_unit_size, definition.module_id)
		var placement_transform := Transform3D(Basis.IDENTITY, Vector3((cell.x - center_cell.x) * profile.module_unit_size, 0.0, (cell.y - center_cell.y) * profile.module_unit_size))
		instance.transform = placement_transform
		add_child(instance)
		var placement: PlacementType = PlacementType.new()
		placement.definition = definition
		placement.transform = placement_transform
		placement.instance = instance
		_placements.append(placement)
	if not errors.is_empty():
		_clear_layout()
		return {"placements": _placements, "spawn_anchors": _spawn_anchors, "errors": errors}
	_spawn_anchors = _collect_spawn_anchors()
	return {"placements": _placements.duplicate(), "spawn_anchors": _spawn_anchors.duplicate(), "errors": PackedStringArray()}

func _clear_layout() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_placements.clear()
	_spawn_anchors.clear()

func _cells_inside_footprint(footprint: PackedVector2Array) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for z in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var center := Vector2((float(x) + 0.5) / GRID_SIZE, (float(z) + 0.5) / GRID_SIZE)
			if Geometry2D.is_point_in_polygon(center, footprint):
				cells.append(Vector2i(x, z))
	return cells

func _closest_cell_to_center(cells: Array[Vector2i]) -> Vector2i:
	var best := cells[0]
	var best_distance := INF
	for cell in cells:
		var center := Vector2((float(cell.x) + 0.5) / GRID_SIZE, (float(cell.y) + 0.5) / GRID_SIZE)
		var distance := center.distance_squared_to(Vector2(0.5, 0.5))
		if distance < best_distance:
			best = cell
			best_distance = distance
	return best

func _collect_spawn_anchors() -> Array[SpawnAnchorType]:
	var anchors: Array[SpawnAnchorType] = []
	for node in find_children("*", "Marker3D", true, false):
		if node is SpawnAnchorType:
			anchors.append(node)
	return anchors

func _make_definition(module_id: StringName, scene: PackedScene, supported_silhouette: StringName) -> ModuleType:
	if scene == null:
		return null
	var definition: ModuleType = ModuleType.new()
	definition.module_id = module_id
	definition.scene = scene
	definition.supported_silhouettes = [supported_silhouette]
	definition.local_bounds = Rect2(-2.0, -2.0, 4.0, 4.0)
	return definition
