class_name CombatHitGizmos
extends MeshInstance3D

# Visualization consumes native diagnostics; it never simulates contact/history.
var manager: HitManagerNode
var show_hits: bool = true
var show_hurtboxes: bool = false
var _profiles: Dictionary = {}
const SEGMENTS := 16
const LIVE := Color(0.2, 1.0, 0.2, 1.0)
const HURT := Color(0.2, 0.65, 1.0, 0.5)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = ArrayMesh.new()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material_override = material

func _process(_delta: float) -> void:
	if not visible or manager == null or manager.native_manager == null:
		return
	var snapshot := manager.native_manager.get_debug_snapshot()
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	if show_hurtboxes:
		for hurtbox in snapshot.hurtboxes:
			var radius := float(hurtbox.radius)
			var height := float(hurtbox.height)
			var size := Vector3(radius, 0.0, maxf(0.0, height - radius * 2.0))
			var transform := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), hurtbox.position + Vector3.UP * height * 0.5)
			_append_profile(vertices, colors, &"capsule", size, transform, HURT)
	if show_hits:
		for hitbox in snapshot.hitboxes:
			for pose in hitbox.poses:
				var transform: Transform3D = pose.transform
				# Native dimensions are world units; inherited pose scale is ignored.
				transform.basis = transform.basis.orthonormalized()
				var live: bool = hitbox.active and int(pose.age) == 0
				var color := LIVE if live else Color(1.0, 0.5, 0.05, 0.15 + 0.65 * float(pose.potency))
				_append_profile(vertices, colors, hitbox.shape, hitbox.size, transform, color)
				if pose.swept:
					var previous: Transform3D = pose.previous_transform
					vertices.append(previous.origin)
					vertices.append(transform.origin)
					colors.append(Color.MAGENTA)
					colors.append(Color.MAGENTA)
	var array_mesh := mesh as ArrayMesh
	array_mesh.clear_surfaces()
	if vertices.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)

func _append_profile(vertices: PackedVector3Array, colors: PackedColorArray, shape: StringName, size: Vector3, transform: Transform3D, color: Color) -> void:
	var key := "%s:%s" % [shape, size]
	if not _profiles.has(key):
		_profiles[key] = shape_lines(shape, size)
	for point in _profiles[key]:
		vertices.append(transform * point)
		colors.append(color)

static func shape_lines(shape: StringName, size: Vector3) -> PackedVector3Array:
	var points := PackedVector3Array()
	match shape:
		&"sphere":
			_circle(points, Vector3.ZERO, Vector3.RIGHT, Vector3.UP, size.x)
			_circle(points, Vector3.ZERO, Vector3.RIGHT, Vector3.BACK, size.x)
			_circle(points, Vector3.ZERO, Vector3.UP, Vector3.BACK, size.x)
		&"capsule":
			var half := size.z * 0.5
			_circle(points, Vector3.BACK * half, Vector3.RIGHT, Vector3.UP, size.x)
			_circle(points, Vector3.FORWARD * half, Vector3.RIGHT, Vector3.UP, size.x)
			for axis: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN]:
				points.append(axis * size.x + Vector3.BACK * half)
				points.append(axis * size.x + Vector3.FORWARD * half)
				for index in range(SEGMENTS / 4):
					var a := float(index) * TAU / SEGMENTS
					var b := float(index + 1) * TAU / SEGMENTS
					for end: float in [-1.0, 1.0]:
						points.append(axis * cos(a) * size.x + Vector3.BACK * end * (half + sin(a) * size.x))
						points.append(axis * cos(b) * size.x + Vector3.BACK * end * (half + sin(b) * size.x))
		&"box":
			for corner in range(8):
				var start := Vector3(1 if corner & 1 else -1, 1 if corner & 2 else -1, 1 if corner & 4 else -1) * size * 0.5
				for axis in range(3):
					if corner & (1 << axis):
						continue
					var end := start
					end[axis] += size[axis]
					points.append(start)
					points.append(end)
		&"cone":
			var radius := tan(deg_to_rad(clampf(size.x, 0.0, 89.0))) * size.z
			var base := Vector3.FORWARD * size.z
			_circle(points, base, Vector3.RIGHT, Vector3.UP, radius)
			for index in range(8):
				var angle := float(index) * TAU / 8.0
				points.append(Vector3.ZERO)
				points.append(base + Vector3(cos(angle), sin(angle), 0.0) * radius)
		&"ring":
			for radius: float in [maxf(0.0, size.x - size.y), size.x + size.y]:
				for height: float in [-size.z * 0.5, size.z * 0.5]:
					_circle(points, Vector3.UP * height, Vector3.RIGHT, Vector3.BACK, radius)
				for index in range(8):
					var angle := float(index) * TAU / 8.0
					var at := Vector3(cos(angle), 0.0, sin(angle)) * radius
					points.append(at + Vector3.UP * size.z * 0.5)
					points.append(at - Vector3.UP * size.z * 0.5)
	return points

static func _circle(points: PackedVector3Array, center: Vector3, u: Vector3, v: Vector3, radius: float) -> void:
	for index in range(SEGMENTS):
		var a := float(index) * TAU / SEGMENTS
		var b := float(index + 1) * TAU / SEGMENTS
		points.append(center + (u * cos(a) + v * sin(a)) * radius)
		points.append(center + (u * cos(b) + v * sin(b)) * radius)
