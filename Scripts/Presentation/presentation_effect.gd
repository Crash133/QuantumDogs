class_name PresentationEffect
extends Node3D

## Low-cost authored combat effect: generated ribbon/ring geometry on additive
## unlit shaders, no lights, no particles. Every look value is an export so
## profiles and the inspector can tune width/length/lifetime/opacity per move.
## Lifetime is bounded: the effect frees itself (or, when `pooled`, hides and
## emits `finished` for its handler's pool). release() ends it immediately
## (interrupted trail, weapon switch, death, level clear).

signal finished(effect: PresentationEffect)

enum Shape { ARC, LINE, SHOCK, TRACE, WARNING, SLASH }
const MAX_SLASH_POSE_SAMPLES := 32

const RIBBON := preload("res://Shaders/Presentation/ion_ribbon.gdshader")
const GLOW := preload("res://Shaders/Presentation/warning_glow.gdshader")
const SLASH_SHADER := preload("res://Shaders/Presentation/slash_trace.gdshader")

@export var shape: Shape = Shape.ARC
@export var core_color: Color = Color(0.25, 0.9, 1.0)
@export var edge_color: Color = Color(0.25, 0.9, 1.0)
@export_range(0.0, 1.0) var edge_width: float = 0.2
@export_range(0.0, 1.0) var opacity: float = 0.85
## ARC/SHOCK: radius. LINE/TRACE: length (TRACE uses its endpoints instead).
@export var size: float = 1.4
@export var width: float = 0.25
@export var arc_degrees: float = 150.0
## Parallel copies: Mantis paired cuts use 2, crossed by `cross_degrees`.
@export var count: int = 1
@export var cross_degrees: float = 0.0
## LINE: helix rings along the thrust (Rocket Lance).
@export var rings: int = 0
@export var ring_radius: float = 0.3
@export var lifetime: float = 0.22
## Fraction of lifetime spent sweeping in before fading.
@export_range(0.05, 1.0) var reveal_fraction: float = 0.45
## Seconds before the effect appears (Greatsword's delayed shock front).
@export var delay: float = 0.0
## SHOCK: final radius multiplier reached at end of lifetime.
@export var expand: float = 2.2
## WARNING: 0 lamp (common), 1 lens ring (drone), 2 chevron crown (Elite).
@export_range(0, 2) var warning_shape: int = 0
@export var warning_intensity: float = 1.2
## Reduced motion: no sweep animation or pulsing; a steady, non-flashing look.
@export var reduced_motion: bool = false
## Hold the effect until release() (looping warnings / open trails).
@export var sustain: bool = false
## Pooled effects hide and emit `finished` instead of freeing.
@export var pooled: bool = false
## SLASH: tilt of the sweep plane around the facing axis, and mirrored direction.
@export var roll_degrees: float = 0.0
@export var mirror: bool = false

var _time: float = 0.0
var _materials: Array[ShaderMaterial] = []
var _done: bool = false
var _trace_from := Vector3.ZERO
var _trace_to := Vector3(0, 0, -6)
var _built: bool = false
var _last_sample_pose: Transform3D = Transform3D.IDENTITY
var _pose_sample_count: int = 0
var pose_sample_count: int:
	get:
		return _pose_sample_count
var _pose_samples: Array[Transform3D] = []
var _trace_finalized: bool = false

func _ready() -> void:
	_build()

## Applies FeedbackRequest.visual overrides; call before the effect enters the tree.
func configure_from_request(request: FeedbackRequest) -> void:
	if request == null or request.visual.is_empty():
		return
	var visual := request.visual
	core_color = visual.get(&"core_color", core_color)
	edge_color = visual.get(&"edge_color", edge_color)
	size = visual.get(&"size", size)
	width = visual.get(&"width", width)
	arc_degrees = visual.get(&"arc_degrees", arc_degrees)
	roll_degrees = visual.get(&"roll_degrees", roll_degrees)
	mirror = visual.get(&"mirror", mirror)
	var sweep: float = visual.get(&"sweep_seconds", 0.0)
	var fade_time: float = visual.get(&"fade_seconds", 0.0)
	if sweep > 0.0:
		lifetime = sweep + fade_time
		reveal_fraction = clampf(sweep / lifetime, 0.05, 1.0)

func set_endpoints(from: Vector3, to: Vector3) -> void:
	_trace_from = from
	_trace_to = to
	if _built:
		_rebuild()

func has_pose_trace() -> bool:
	return shape == Shape.SLASH

func begin_pose_trace(first_pose: Transform3D) -> void:
	_pose_sample_count = 0
	_pose_samples.clear()
	_trace_finalized = false
	add_pose_sample(first_pose)

## Appends one active hitbox pose and moves the layered slash with it.
func add_pose_sample(pose: Transform3D) -> void:
	if not has_pose_trace() or _trace_finalized:
		return
	if _pose_sample_count > 0 and pose.is_equal_approx(_last_sample_pose):
		return
	global_transform = pose
	_last_sample_pose = pose
	if _pose_samples.size() < MAX_SLASH_POSE_SAMPLES:
		_pose_samples.append(pose)
		_pose_sample_count += 1

## Ends sampling at the exact final hitbox pose; the slash then fades in place.
func finalize_pose_trace() -> void:
	if not has_pose_trace() or _trace_finalized:
		return
	_trace_finalized = true

func release() -> void:
	if _done:
		return
	_done = true
	hide()
	set_process(false)
	finished.emit(self)
	if not pooled:
		queue_free()

func restart() -> void:
	_done = false
	_time = 0.0
	_pose_sample_count = 0
	_pose_samples.clear()
	_trace_finalized = false
	show()
	set_process(true)

func _process(delta: float) -> void:
	_time += delta
	var t := (_time - delay) / maxf(0.001, lifetime)
	visible = t >= 0.0
	if t < 0.0:
		return
	if sustain:
		t = minf(t, reveal_fraction)
	var reveal := 1.0 if reduced_motion else clampf(t / reveal_fraction, 0.0, 1.0)
	var fade := clampf((t - reveal_fraction) / maxf(0.001, 1.0 - reveal_fraction), 0.0, 1.0)
	for material in _materials:
		if material.shader != GLOW:
			material.set_shader_parameter(&"reveal", reveal)
		material.set_shader_parameter(&"fade", fade)
	if shape == Shape.SHOCK and not reduced_motion:
		var s := lerpf(1.0, expand, clampf(t, 0.0, 1.0))
		for child in get_children():
			if child is MeshInstance3D:
				child.scale = Vector3(s, 1.0, s)
	if t >= 1.0 and not sustain:
		release()

func _rebuild() -> void:
	for child in get_children():
		if child is MeshInstance3D:
			child.queue_free()
	_materials.clear()
	_build()

func _build() -> void:
	_built = true
	match shape:
		Shape.ARC:
			for i in maxi(1, count):
				var roll := 0.0 if count <= 1 else lerpf(-cross_degrees, cross_degrees, float(i) / float(count - 1))
				_add(_arc_mesh(size, width, arc_degrees), _ribbon(), Basis(Vector3.FORWARD, deg_to_rad(roll)))
		Shape.LINE:
			_add(_strip(Vector3.ZERO, Vector3(0, 0, -size), width), _ribbon())
			for i in rings:
				var z := -size * (float(i + 1) / float(rings + 1))
				var ring := _arc_mesh(ring_radius, width * 0.35, 360.0)
				_add(ring, _ribbon(), Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.FORWARD, float(i) * 0.6), Vector3(0, 0, z))
		Shape.SHOCK:
			_add(_arc_mesh(size, width, 360.0), _ribbon())
		Shape.TRACE:
			_add(_strip(_trace_from, _trace_to, width), _ribbon())
			_add_glow(_trace_from, 0.35, 0)
			_add_glow(_trace_to, 0.45, 1)
		Shape.WARNING:
			_add_glow(Vector3.ZERO, size, warning_shape)
		Shape.SLASH:
			# Keep the original layered arc look; gameplay supplies its exact pose
			# every active tick, while profile dimensions remain combat-only data.
			var basis := Basis(Vector3.FORWARD, deg_to_rad(roll_degrees))
			if mirror:
				basis = basis * Basis.from_scale(Vector3(-1, 1, 1))
			_add(_arc_mesh(size, width * 1.6, arc_degrees), _slash(0.45, 1.0), basis)
			_add(_arc_mesh(size, width, arc_degrees), _slash(1.0, 1.8), basis)

func _ribbon() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = RIBBON
	material.set_shader_parameter(&"core_color", core_color)
	material.set_shader_parameter(&"edge_color", edge_color)
	material.set_shader_parameter(&"edge_width", edge_width)
	material.set_shader_parameter(&"opacity", opacity)
	material.set_shader_parameter(&"reveal", 1.0 if reduced_motion else 0.0)
	_materials.append(material)
	return material

func _slash(strength: float, brightness: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SLASH_SHADER
	material.set_shader_parameter(&"core_color", core_color)
	material.set_shader_parameter(&"edge_color", edge_color)
	material.set_shader_parameter(&"opacity", opacity * strength)
	material.set_shader_parameter(&"brightness", brightness)
	material.set_shader_parameter(&"reveal", 1.0 if reduced_motion else 0.0)
	material.set_shader_parameter(&"flow_speed", 0.0 if reduced_motion else 1.5)
	_materials.append(material)
	return material

func _add_glow(at: Vector3, diameter: float, glow_shape: int) -> void:
	var material := ShaderMaterial.new()
	material.shader = GLOW
	material.set_shader_parameter(&"color", core_color)
	material.set_shader_parameter(&"opacity", opacity)
	material.set_shader_parameter(&"intensity", warning_intensity)
	material.set_shader_parameter(&"shape", glow_shape)
	material.set_shader_parameter(&"pulse", 0.0 if reduced_motion else 0.35)
	_materials.append(material)
	var quad := QuadMesh.new()
	quad.size = Vector2(diameter, diameter)
	_add(quad, material, Basis.IDENTITY, at)

func _add(mesh: Mesh, material: Material, basis: Basis = Basis.IDENTITY, origin: Vector3 = Vector3.ZERO) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.transform = Transform3D(basis, origin)
	add_child(instance)

## Flat ribbon arc in the XZ plane, centred on -Z, UV.x along the sweep.
static func _arc_mesh(radius: float, ribbon_width: float, degrees: float) -> ArrayMesh:
	var segments := maxi(6, int(degrees / 8.0))
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i in segments + 1:
		var f := float(i) / float(segments)
		var a := deg_to_rad(lerpf(-degrees * 0.5, degrees * 0.5, f))
		var dir := Vector3(sin(a), 0.0, -cos(a))
		verts.append(dir * (radius - ribbon_width * 0.5))
		verts.append(dir * (radius + ribbon_width * 0.5))
		uvs.append(Vector2(f, 0.0))
		uvs.append(Vector2(f, 1.0))
	return _strip_mesh(verts, uvs)

## Straight ribbon from `from` to `to`, lying flat (normal ~ +Y).
static func _strip(from: Vector3, to: Vector3, ribbon_width: float) -> ArrayMesh:
	var along := to - from
	var side := along.cross(Vector3.UP).normalized() * ribbon_width * 0.5
	if side.is_zero_approx():
		side = Vector3.RIGHT * ribbon_width * 0.5
	return _strip_mesh(PackedVector3Array([from - side, from + side, to - side, to + side]), PackedVector2Array([Vector2(0, 0), Vector2(0, 1), Vector2(1, 0), Vector2(1, 1)]))

static func _strip_mesh(verts: PackedVector3Array, uvs: PackedVector2Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)
	return mesh
