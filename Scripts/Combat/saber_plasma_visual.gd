class_name SaberPlasmaVisual
extends RefCounted

## Presentation-only plasma blast: a layered, tapered crescent (soft glow body
## under a hot rim) in the Saber's colours, a counter-rotating outer ghost and a
## trailing spark wake. No collision or gameplay ownership.

const SLASH := preload("res://Shaders/Presentation/slash_trace.gdshader")
const CORE := Color(0.969, 0.78, 1.0)
const EDGE := Color(0.874, 0.1, 1.0)

static func attach(flight: CombatProjectile, radius: float) -> void:
	var root := flight.get_node_or_null("PlasmaSlash") as Node3D
	if root == null:
		root = Node3D.new()
		root.name = "PlasmaSlash"
		root.add_child(_layer(1.0, 1.0, 0.55, 2.0, 1.0))
		root.add_child(_layer(1.0, 1.0, 1.0, 1.6, 1.0))
		root.add_child(_layer(1.45, 1.0, 0.3, 1.0, 1.4)) # Wider, fainter ghost shell.
		root.add_child(_wake())
		flight.add_child(root)
	root.scale = Vector3.ONE * radius

static func _layer(scale: float, thickness: float, opacity: float, brightness: float, streaks: float) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.mesh = _crescent(scale, thickness)
	var material := ShaderMaterial.new()
	material.shader = SLASH
	material.set_shader_parameter(&"core_color", CORE)
	material.set_shader_parameter(&"edge_color", EDGE)
	material.set_shader_parameter(&"opacity", opacity)
	material.set_shader_parameter(&"brightness", brightness)
	material.set_shader_parameter(&"symmetric", true)
	material.set_shader_parameter(&"streaks", 5.0 * streaks)
	material.set_shader_parameter(&"flow_speed", 2.5)
	visual.material_override = material
	return visual

## Upward crescent in the XY plane (flight travels along -Z), thinning to points at both tips.
static func _crescent(scale: float, thickness: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var segments := 28
	for i in segments + 1:
		var f := float(i) / float(segments)
		var a := PI * f
		var outer := Vector3(cos(a), sin(a) - 0.4, 0.0) * scale
		var inner := outer - Vector3(0.0, 0.55 * sin(a) * thickness * scale, 0.0)
		verts.append(inner)
		verts.append(outer)
		uvs.append(Vector2(f, 0.0))
		uvs.append(Vector2(f, 1.0))
	return PresentationEffect._strip_mesh(verts, uvs)

static func _wake() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Wake"
	particles.amount = 36
	particles.lifetime = 0.35
	particles.local_coords = false # Sparks stay behind as the crescent flies on.
	particles.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.8
	process.direction = Vector3(0, 0, 1)
	process.spread = 25.0
	process.initial_velocity_min = 1.0
	process.initial_velocity_max = 3.0
	process.gravity = Vector3.ZERO
	process.scale_min = 0.5
	process.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(CORE, 1.0))
	fade.set_color(1, Color(EDGE, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	particles.process_material = process
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.09, 0.09)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	mesh.material = material
	particles.draw_pass_1 = mesh
	particles.emitting = true
	return particles
