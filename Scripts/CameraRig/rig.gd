extends Node3D
class_name CameraRig

@export var follow_speed := 10.0

@export var min_pitch := -35.0
@export var max_pitch := 45.0
@export var mouse_sensitivity := 0.003
@export var stick_radians_per_second := 2.5
@export var wall_follow_speed := 12.0
@export var wall_soft_margin := 0.4
@export var camera_collision_radius := 0.15

@export var orbit_point: Node3D
@export var targeting_service: TargetingService

@onready var pitch_pivot = $PitchPivot
@onready var shaker = $PitchPivot/CameraShake
@onready var spring_arm: SpringArm3D = $PitchPivot/CameraShake/SpringArm3D

var pitch := -15.0
var yaw := 0.0
var follow_speed_mult := 1.0
var _wall_probe: SpringArm3D
var _nominal_length: float
var _probe_started: bool = false
var _excluded_follow: CollisionObject3D

func _ready() -> void:
	_nominal_length = spring_arm.spring_length
	var volume := SphereShape3D.new()
	volume.radius = maxf(0.01, camera_collision_radius)
	spring_arm.shape = volume
	# A full-distance probe detects the soft zone independently of the smoothed
	# arm length. The camera's own arm still enforces the hard no-clip boundary.
	_wall_probe = $PitchPivot/CameraShake/CameraWallProbe as SpringArm3D
	_wall_probe.spring_length = _nominal_length
	_wall_probe.shape = volume
	_wall_probe.collision_mask = spring_arm.collision_mask
	_wall_probe.margin = spring_arm.margin + maxf(0.0, wall_soft_margin)
	_wall_probe.process_physics_priority = -3
	_exclude_follow_body()

func _physics_process(delta: float) -> void:
	var _probe := ScriptCostProbe.start()
	_physics_process_body(delta)
	ScriptCostProbe.stop(&"camera.physics", _probe)

func _physics_process_body(delta: float) -> void:
	_exclude_follow_body()
	if not _probe_started:
		_probe_started = true
		return
	var target := clampf(_wall_probe.get_hit_length(), 0.0, _nominal_length)
	var weight := 1.0 - exp(-maxf(0.0, wall_follow_speed) * maxf(0.0, delta))
	spring_arm.spring_length = lerpf(spring_arm.spring_length, target, weight)

func _exclude_follow_body() -> void:
	var body: Node = orbit_point
	while is_instance_valid(body) and not body is CollisionObject3D:
		body = body.get_parent()
	if not is_instance_valid(body) or body == _excluded_follow:
		return
	if is_instance_valid(_excluded_follow):
		spring_arm.remove_excluded_object(_excluded_follow.get_rid())
		_wall_probe.remove_excluded_object(_excluded_follow.get_rid())
	_excluded_follow = body as CollisionObject3D
	spring_arm.add_excluded_object(_excluded_follow.get_rid())
	_wall_probe.add_excluded_object(_excluded_follow.get_rid())

func _process(delta: float) -> void:
	var _probe := ScriptCostProbe.start()
	_process_body(delta)
	ScriptCostProbe.stop(&"camera.process", _probe)

func _process_body(delta: float) -> void:
	if InputMap.has_action(&"look_left"):
		var look := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
		_apply_orbit(look * stick_radians_per_second * delta)
	var weight := 1.0 - exp(-maxf(0.0, follow_speed * follow_speed_mult) * maxf(0.0, delta))
	if is_instance_valid(orbit_point):
		global_position = global_position.lerp(orbit_point.global_position, weight)
	var targeting := targeting_service
	if not is_instance_valid(targeting):
		targeting = get_tree().get_first_node_in_group("targeting_services") as TargetingService
	if targeting != null and targeting.locked_target != null and is_instance_valid(targeting.locked_target):
		var toward_target := targeting.locked_target.global_position - global_position
		var target_yaw := atan2(-toward_target.x, -toward_target.z)
		yaw = target_yaw
	rotation.y = lerp_angle(rotation.y, yaw, weight)
	pitch_pivot.rotation.x = lerp_angle(pitch_pivot.rotation.x, deg_to_rad(pitch), weight)

func reset_behind() -> void:
	if is_instance_valid(orbit_point) and orbit_point.get_parent() is Node3D:
		var body := orbit_point.get_parent() as Node3D
		if body.has_method("get_combat_facing"):
			var facing: Vector3 = body.get_combat_facing()
			yaw = atan2(-facing.x, -facing.z)
		else:
			yaw = body.global_rotation.y
	pitch = -15.0

func get_shaker() -> CameraShake:
	return shaker

# Captured mouse (gameplay): every motion orbits. Read before the GUI, because
# full-screen HUD controls would otherwise consume the motion.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_orbit(event.relative * mouse_sensitivity)

# Free mouse (debug lab): left-drag orbits.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and event.button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
		_apply_orbit(event.relative * mouse_sensitivity)

func _apply_orbit(radians: Vector2) -> void:
	yaw -= radians.x
	pitch = clampf(pitch - rad_to_deg(radians.y), min_pitch, max_pitch)
