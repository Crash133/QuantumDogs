extends Node3D

## Short expanding ring for a successful execution shockwave. It is presentation
## only: it has no collision shapes, gameplay scripts, or global time effects.

@export_range(0.05, 2.0, 0.01, "suffix:s") var lifetime_seconds: float = 0.34
@export var ring_color: Color = Color(0.72, 0.91, 1.0, 0.82)

@onready var ring: MeshInstance3D = $Ring

var _elapsed := 0.0
var _radius := 4.0
var _material: StandardMaterial3D

func configure(radius: float) -> void:
	_radius = maxf(0.0, radius)

func _ready() -> void:
	_material = (ring.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
	ring.material_override = _material
	_update_ring(0.0)

func _process(delta: float) -> void:
	_elapsed += maxf(0.0, delta)
	var progress := clampf(_elapsed / maxf(0.001, lifetime_seconds), 0.0, 1.0)
	_update_ring(progress)
	if progress >= 1.0:
		queue_free()

func _update_ring(progress: float) -> void:
	var eased := 1.0 - pow(1.0 - progress, 2.0)
	var extent := maxf(0.025, _radius * eased)
	if is_instance_valid(ring):
		ring.scale = Vector3(extent, 1.0, extent)
	if is_instance_valid(_material):
		var color := ring_color
		color.a *= 1.0 - progress
		_material.albedo_color = color
