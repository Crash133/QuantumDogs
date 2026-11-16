extends Node3D
class_name ArenaGroundTile

## One arena module: an irregular patchwork of rectangular slabs (parallelepipeds)
## of different sizes and slightly different heights, separated by dark crevices,
## with a few glowing edges. Walking uses a separate smooth collision field.
##
## The height field is defined on a global lattice (hashed from the run seed and
## absolute lattice index), so heights are identical where neighbouring tiles
## meet. Each slab's top sits at or just below that field so feet never sink into
## a slab. Slab layout inside a tile depends only on (seed, grid cell).

const SpawnAnchorType = preload("res://Scripts/LevelGeneration/arena_spawn_anchor.gd")
const SLAB_SHADER = preload("res://Shaders/ArenaSlab.gdshader")
## Height lattice points per tile edge (spacing = tile_size / LATTICE_PER_TILE).
const LATTICE_PER_TILE: int = 2
const COLLISION_CELLS: int = 16
## Field amplitude and slab height quantum, as a fraction of the tile size.
const RELIEF_RATIO: float = 0.015
const HEIGHT_STEP_RATIO: float = 0.004
const GAP_RATIO: float = 0.02
const SLAB_DEPTH_RATIO: float = 0.14
const MIN_SLAB_RATIO: float = 0.2
## Chance a slab carries edge lights, and per-edge chance on such a slab.
const LIT_SLAB_CHANCE: float = 0.5
const LIT_EDGE_CHANCE: float = 0.4

const LIGHT_PALETTE: Array[Color] = [
	Color(0.28, 0.46, 1.0),
	Color(0.28, 0.46, 1.0),
	Color(0.2, 0.55, 1.0),
	Color(0.55, 0.32, 1.0),
	Color(1.0, 0.62, 0.26),
]

var _configured: bool = false
var _tile_size: float = 4.0
var _seed: int = 0
var _cell: Vector2i = Vector2i.ZERO

func _ready() -> void:
	if not _configured:
		configure(0, Vector2i.ZERO, _tile_size, &"fallback")

func configure(seed_value: int, grid_cell: Vector2i, tile_size: float, module_id: StringName) -> void:
	_tile_size = maxf(tile_size, 0.1)
	_seed = seed_value
	_cell = grid_cell
	_configured = true
	for node_name in ["GroundBlocks", "GroundBody", "SpawnAnchors"]:
		var old_node := get_node_or_null(node_name)
		if old_node != null:
			remove_child(old_node)
			old_node.free()
	var slabs := _make_slabs()
	_build_blocks(slabs)
	_build_collision()
	_build_spawn_anchors()

# --- Height field ------------------------------------------------------------

func _lattice_height(index_x: int, index_z: int) -> float:
	var lattice_rng := RandomNumberGenerator.new()
	lattice_rng.seed = hash("%d:%d:%d" % [_seed, index_x, index_z])
	var amplitude := _tile_size * RELIEF_RATIO
	return lattice_rng.randf_range(-amplitude, amplitude)

## Continuous field in tile-local metres; shared by neighbouring tiles.
func _field(local_x: float, local_z: float) -> float:
	var gx := (local_x + _tile_size * 0.5) / _tile_size * float(LATTICE_PER_TILE)
	var gz := (local_z + _tile_size * 0.5) / _tile_size * float(LATTICE_PER_TILE)
	var x0 := int(floor(gx))
	var z0 := int(floor(gz))
	var fx := gx - float(x0)
	var fz := gz - float(z0)
	var base_x := _cell.x * LATTICE_PER_TILE
	var base_z := _cell.y * LATTICE_PER_TILE
	var top := lerpf(_lattice_height(base_x + x0, base_z + z0), _lattice_height(base_x + x0 + 1, base_z + z0), fx)
	var bottom := lerpf(_lattice_height(base_x + x0, base_z + z0 + 1), _lattice_height(base_x + x0 + 1, base_z + z0 + 1), fx)
	return lerpf(top, bottom, fz)

# --- Slabs -------------------------------------------------------------------

## Splits the tile into irregular rectangles (random binary space partition).
func _make_slabs() -> Array[Rect2]:
	var layout_rng := RandomNumberGenerator.new()
	layout_rng.seed = hash("slabs:%d:%d:%d" % [_seed, _cell.x, _cell.y])
	var half := _tile_size * 0.5
	var minimum := _tile_size * MIN_SLAB_RATIO
	var rects: Array[Rect2] = [Rect2(-half, -half, _tile_size, _tile_size)]
	var target := layout_rng.randi_range(5, 9)
	var guard := 0
	while rects.size() < target and guard < 64:
		guard += 1
		# Larger rectangles are split first.
		var total_area := 0.0
		for rect in rects:
			if maxf(rect.size.x, rect.size.y) >= minimum * 2.0:
				total_area += rect.size.x * rect.size.y
		if total_area <= 0.0:
			break
		var pick := layout_rng.randf() * total_area
		var chosen := -1
		for index in rects.size():
			var rect := rects[index]
			if maxf(rect.size.x, rect.size.y) < minimum * 2.0:
				continue
			pick -= rect.size.x * rect.size.y
			chosen = index
			if pick <= 0.0:
				break
		if chosen < 0:
			break
		var source := rects[chosen]
		var split_x := source.size.x >= source.size.y
		if source.size.x < minimum * 2.0:
			split_x = false
		elif source.size.y < minimum * 2.0:
			split_x = true
		var length := source.size.x if split_x else source.size.y
		var cut := clampf(length * layout_rng.randf_range(0.3, 0.7), minimum, length - minimum)
		rects.remove_at(chosen)
		if split_x:
			rects.append(Rect2(source.position, Vector2(cut, source.size.y)))
			rects.append(Rect2(source.position + Vector2(cut, 0.0), Vector2(source.size.x - cut, source.size.y)))
		else:
			rects.append(Rect2(source.position, Vector2(source.size.x, cut)))
			rects.append(Rect2(source.position + Vector2(0.0, cut), Vector2(source.size.x, source.size.y - cut)))
	return rects

func _slab_top(rect: Rect2) -> float:
	# Lowest field value over the slab, floored to a step: the slab never rises
	# above the walkable surface, so feet never sink into it.
	var lowest := INF
	for fx in [0.0, 0.5, 1.0]:
		for fz in [0.0, 0.5, 1.0]:
			lowest = minf(lowest, _field(rect.position.x + rect.size.x * fx, rect.position.y + rect.size.y * fz))
	var step := _tile_size * HEIGHT_STEP_RATIO
	return floorf(lowest / step) * step

func _build_blocks(slabs: Array[Rect2]) -> void:
	var look_rng := RandomNumberGenerator.new()
	look_rng.seed = hash("look:%d:%d:%d" % [_seed, _cell.x, _cell.y])
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	builder.set_smooth_group(-1)
	builder.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	builder.set_custom_format(1, SurfaceTool.CUSTOM_RGBA_FLOAT)
	var gap := _tile_size * GAP_RATIO
	var depth := _tile_size * SLAB_DEPTH_RATIO
	for slab in slabs:
		var rect := slab.grow(-gap * 0.5)
		if rect.size.x <= 0.05 or rect.size.y <= 0.05:
			continue
		var top := _slab_top(rect)
		var variation := look_rng.randf()
		var tint := Color(0.06 + variation * 0.05, 0.085 + variation * 0.06, 0.15 + variation * 0.08)
		var lit := look_rng.randf() < LIT_SLAB_CHANCE
		var mask := Color(0.0, 0.0, 0.0, 0.0)
		var light := LIGHT_PALETTE[look_rng.randi_range(0, LIGHT_PALETTE.size() - 1)]
		if lit:
			mask = Color(float(look_rng.randf() < LIT_EDGE_CHANCE), float(look_rng.randf() < LIT_EDGE_CHANCE), float(look_rng.randf() < LIT_EDGE_CHANCE), float(look_rng.randf() < LIT_EDGE_CHANCE))
			if mask.r + mask.g + mask.b + mask.a == 0.0:
				mask.r = 1.0
		var light_data := Color(light.r, light.g, light.b, 0.55 + look_rng.randf() * 0.7 if lit else 0.0)
		_add_slab(builder, rect, top, depth, tint, mask, light_data)
	builder.generate_normals()
	var material := ShaderMaterial.new()
	material.shader = SLAB_SHADER
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "GroundBlocks"
	mesh_instance.mesh = builder.commit()
	mesh_instance.material_override = material
	add_child(mesh_instance)

func _add_slab(builder: SurfaceTool, rect: Rect2, top: float, depth: float, tint: Color, mask: Color, light_data: Color) -> void:
	var x0 := rect.position.x
	var x1 := rect.end.x
	var z0 := rect.position.y
	var z1 := rect.end.y
	var bottom := top - depth
	var size_uv := Vector2(rect.size.x, rect.size.y)
	var p00 := Vector3(x0, top, z0)
	var p01 := Vector3(x0, top, z1)
	var p11 := Vector3(x1, top, z1)
	var p10 := Vector3(x1, top, z0)
	var top_uvs := [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
	_add_quad(builder, [p00, p01, p11, p10], top_uvs, tint, mask, light_data, size_uv)
	var side_tint := tint.darkened(0.4)
	var zero_uvs := [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	var no_mask := Color(0, 0, 0, 0)
	var no_light := Color(0, 0, 0, 0)
	_add_quad(builder, [Vector3(x0, bottom, z0), Vector3(x0, bottom, z1), p01, p00], zero_uvs, side_tint, no_mask, no_light, size_uv)
	_add_quad(builder, [Vector3(x0, bottom, z1), Vector3(x1, bottom, z1), p11, p01], zero_uvs, side_tint, no_mask, no_light, size_uv)
	_add_quad(builder, [Vector3(x1, bottom, z1), Vector3(x1, bottom, z0), p10, p11], zero_uvs, side_tint, no_mask, no_light, size_uv)
	_add_quad(builder, [Vector3(x1, bottom, z0), Vector3(x0, bottom, z0), p00, p10], zero_uvs, side_tint, no_mask, no_light, size_uv)

func _add_quad(builder: SurfaceTool, corners: Array, uvs: Array, tint: Color, mask: Color, light_data: Color, slab_size: Vector2) -> void:
	for index in [0, 2, 1, 0, 3, 2]:
		builder.set_color(tint)
		builder.set_uv(uvs[index])
		builder.set_uv2(slab_size)
		builder.set_custom(0, mask)
		builder.set_custom(1, light_data)
		builder.add_vertex(corners[index])

# --- Walking surface -----------------------------------------------------------

func _build_collision() -> void:
	var faces := PackedVector3Array()
	var cell_size := _tile_size / float(COLLISION_CELLS)
	var heights: Array = []
	for z in range(COLLISION_CELLS + 1):
		var row: Array[float] = []
		for x in range(COLLISION_CELLS + 1):
			row.append(_field(-_tile_size * 0.5 + float(x) * cell_size, -_tile_size * 0.5 + float(z) * cell_size))
		heights.append(row)
	for z in range(COLLISION_CELLS):
		for x in range(COLLISION_CELLS):
			var x0 := -_tile_size * 0.5 + float(x) * cell_size
			var x1 := x0 + cell_size
			var z0 := -_tile_size * 0.5 + float(z) * cell_size
			var z1 := z0 + cell_size
			var p00 := Vector3(x0, heights[z][x], z0)
			var p01 := Vector3(x0, heights[z + 1][x], z1)
			var p11 := Vector3(x1, heights[z + 1][x + 1], z1)
			var p10 := Vector3(x1, heights[z][x + 1], z0)
			# Godot concave collision fronts use clockwise winding viewed from above.
			faces.append_array(PackedVector3Array([p00, p11, p01, p00, p10, p11]))
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	var collision := CollisionShape3D.new()
	collision.name = "GroundCollision"
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

func _build_spawn_anchors() -> void:
	var anchors_root := Node3D.new()
	anchors_root.name = "SpawnAnchors"
	var offsets := [
		Vector2(-_tile_size * 0.25, -_tile_size * 0.25),
		Vector2(_tile_size * 0.25, -_tile_size * 0.25),
		Vector2(-_tile_size * 0.25, _tile_size * 0.25),
		Vector2(_tile_size * 0.25, _tile_size * 0.25),
	]
	for index in range(offsets.size()):
		var anchor: Marker3D = SpawnAnchorType.new()
		anchor.name = "GroundAnchor%d" % index
		anchor.tags.append(&"ground")
		anchor.capacity = 1
		anchor.position = Vector3(offsets[index].x, _field(offsets[index].x, offsets[index].y) + 0.03, offsets[index].y)
		anchors_root.add_child(anchor)
	add_child(anchors_root)
