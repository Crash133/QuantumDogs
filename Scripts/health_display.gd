extends Node

@onready var gauge := $MeshInstance3D
@onready var material: ShaderMaterial = gauge.get_active_material(0)

var idle_time := INF
var _alpha := -1.0

func _ready() -> void:
	var base_mat = gauge.get_active_material(0)
	if base_mat:
		material = base_mat.duplicate() as ShaderMaterial
		gauge.set_surface_override_material(0, material)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var _probe := ScriptCostProbe.start()
	_process_body(delta)
	ScriptCostProbe.stop(&"enemy.health_display", _probe)

func _process_body(delta: float) -> void:
	idle_time += delta
	var target := 0.0 if idle_time > 10.0 else 1.0
	if target != _alpha: # Only touch the shader when the fade state changes.
		_alpha = target
		material.set_shader_parameter("alp", target)
	

func _on_health_component_health_changed(amount: float, curr_health: float, percentage: float) -> void:
	material.set_shader_parameter("height", percentage)
	if(amount != curr_health):
		idle_time = 0
