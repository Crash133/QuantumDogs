extends Node

@onready var gauge := $MeshInstance3D
@onready var material: ShaderMaterial = gauge.get_active_material(0)

var idle_time := INF

func _ready() -> void:
	var base_mat = gauge.get_active_material(0)
	if base_mat:
		material = base_mat.duplicate() as ShaderMaterial
		gauge.set_surface_override_material(0, material)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	idle_time += delta
	if idle_time > 10.0:
		material.set_shader_parameter("alp", 0.0)
	else:
		material.set_shader_parameter("alp", 1.0)
	

func _on_health_component_health_changed(amount: float, curr_health: float, percentage: float) -> void:
	material.set_shader_parameter("height", percentage)
	if(amount != curr_health):
		idle_time = 0
