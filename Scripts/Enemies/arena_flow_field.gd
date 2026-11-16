class_name ArenaFlowField
extends RefCounted

## Ground pathing over the generated tile grid. Arenas are assembled from square
## tiles on a lattice, so "is there floor here" is a set lookup, and a breadth-first
## fill from Lace's tile gives every tile its distance to her. Enemies chase in a
## straight line while the way is clear and follow the fill around gaps otherwise,
## instead of walking off the arena edge in Balcony, Coliseum and funnel shapes.

const NO_GOAL := Vector2i(2147483647, 2147483647)
const NEIGHBOURS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
## Metres between floor checks along a straight line; below half a tile so no gap is skipped.
const LINE_STEP := 1.0

var unit: float = 4.0
var origin: Vector3 = Vector3.ZERO
var _walkable: Dictionary = {}
var _distance: Dictionary = {}
var _goal: Vector2i = NO_GOAL

## placements: ArenaModulePlacement list (each tile's transform is its centre).
func setup(placements: Array, unit_size: float, arena_origin: Vector3) -> void:
	unit = maxf(unit_size, 0.1)
	origin = arena_origin
	_walkable.clear()
	_distance.clear()
	_goal = NO_GOAL
	for placement in placements:
		if placement != null:
			_walkable[cell_of(placement.transform.origin + arena_origin)] = true

func cell_of(point: Vector3) -> Vector2i:
	return Vector2i(roundi((point.x - origin.x) / unit), roundi((point.z - origin.z) / unit))

func cell_center(cell: Vector2i, height: float = 0.0) -> Vector3:
	return Vector3(origin.x + cell.x * unit, height, origin.z + cell.y * unit)

func is_walkable(point: Vector3) -> bool:
	return _walkable.has(cell_of(point))

func walkable_cell_count() -> int:
	return _walkable.size()

## Re-fills only when Lace changes tile; ignored while she is not over floor.
func update_goal(point: Vector3) -> void:
	var cell := cell_of(point)
	if cell == _goal or not _walkable.has(cell):
		return
	_goal = cell
	_distance.clear()
	_distance[cell] = 0
	var frontier: Array[Vector2i] = [cell]
	var head := 0
	while head < frontier.size():
		var current := frontier[head]
		head += 1
		for step in NEIGHBOURS:
			var next := current + step
			if _walkable.has(next) and not _distance.has(next):
				_distance[next] = int(_distance[current]) + 1
				frontier.append(next)

## Flat unit vector a ground enemy at `from` should walk to reach `goal_point`;
## Vector3.ZERO means "no opinion" (off the grid or no route), so callers fall back to straight.
func direction_to_goal(from: Vector3, goal_point: Vector3) -> Vector3:
	if _line_is_clear(from, goal_point):
		return _flat_direction(from, goal_point)
	var cell := cell_of(from)
	if not _distance.has(cell):
		return Vector3.ZERO
	var best := cell
	var best_distance := int(_distance[cell])
	for step in NEIGHBOURS:
		var next := cell + step
		if _distance.has(next) and int(_distance[next]) < best_distance:
			best = next
			best_distance = int(_distance[next])
	if best == cell:
		return Vector3.ZERO
	return _flat_direction(from, cell_center(best, from.y))

func _line_is_clear(from: Vector3, to: Vector3) -> bool:
	var length := Vector2(to.x - from.x, to.z - from.z).length()
	var steps := maxi(1, ceili(length / LINE_STEP))
	for index in range(1, steps + 1):
		if not is_walkable(from.lerp(to, float(index) / float(steps))):
			return false
	return true

func _flat_direction(from: Vector3, to: Vector3) -> Vector3:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	return flat.normalized() if flat.length_squared() > 0.0001 else Vector3.ZERO
