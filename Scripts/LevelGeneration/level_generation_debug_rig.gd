extends Node3D
class_name LevelGenerationDebugRig

var panel: Control
var walk_mode: bool = false
var _spawn_transform := Transform3D.IDENTITY
var _orbit_yaw: float = 0.0
var _orbit_pitch: float = -0.75
var _orbit_distance: float = 44.0
var _look_pitch: float = 0.0
var _orbit_dragging: bool = false
var _jump_requested: bool = false

@onready var walker: CharacterBody3D = $Walker
@onready var _head: Node3D = $Walker/Head
@onready var _walk_camera: Camera3D = $Walker/Head/WalkCamera
@onready var _overview: Camera3D = $OverviewCamera

func _ready() -> void:
	_update_overview()
	set_walk_mode(false)

func reset_to_start(start: Transform3D) -> void:
	_spawn_transform = start
	_reset_walker()

func _reset_walker() -> void:
	walker.global_transform = Transform3D(Basis.IDENTITY, _spawn_transform.origin + Vector3.UP * 0.08)
	walker.velocity = Vector3.ZERO
	_look_pitch = 0.0
	_head.rotation = Vector3.ZERO
	_jump_requested = false

func set_walk_mode(enabled: bool) -> void:
	walk_mode = enabled
	_orbit_dragging = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if enabled:
		_reset_walker()
		_walk_camera.make_current()
	else:
		_overview.make_current()

func reset_overview() -> void:
	_orbit_yaw = 0.0
	_orbit_pitch = -0.75
	_orbit_distance = 44.0
	_update_overview()

func recover_if_fallen() -> bool:
	if walker.global_position.y < -8.0:
		_reset_walker()
		return true
	return false

func can_interact_at(screen_position: Vector2) -> bool:
	return panel == null or not panel.get_global_rect().has_point(screen_position)

func _physics_process(delta: float) -> void:
	if not walk_mode:
		return
	recover_if_fallen()
	if not walker.is_on_floor():
		walker.velocity.y -= 9.8 * delta
	var direction := Vector2.ZERO
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		direction = Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))).normalized()
	var motion := walker.basis * Vector3(direction.x, 0.0, direction.y)
	walker.velocity.x = motion.x * 6.0
	walker.velocity.z = motion.z * 6.0
	if _jump_requested and walker.is_on_floor():
		walker.velocity.y = 4.5
	_jump_requested = false
	walker.move_and_slide()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
		elif walk_mode and event.physical_keycode == KEY_SPACE and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_jump_requested = true
			get_viewport().set_input_as_handled()
	if event is InputEventMouseButton:
		if not event.pressed:
			if event.button_index == MOUSE_BUTTON_RIGHT:
				_orbit_dragging = false
			return
		if not can_interact_at(event.position):
			return
		if walk_mode and event.button_index == MOUSE_BUTTON_LEFT:
			var focused := get_viewport().gui_get_focus_owner()
			if focused != null:
				focused.release_focus()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif not walk_mode:
			if event.button_index == MOUSE_BUTTON_RIGHT:
				_orbit_dragging = true
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_orbit_distance = clampf(_orbit_distance * 0.9, 8.0, 90.0)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_orbit_distance = clampf(_orbit_distance / 0.9, 8.0, 90.0)
			_update_overview()
	if event is InputEventMouseMotion:
		if walk_mode and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			walker.rotate_y(-event.relative.x * 0.003)
			_look_pitch = clampf(_look_pitch - event.relative.y * 0.003, -1.4, 1.4)
			_head.rotation.x = _look_pitch
		elif not walk_mode and _orbit_dragging:
			if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
				_orbit_dragging = false
			elif can_interact_at(event.position):
				_orbit_yaw -= event.relative.x * 0.005
				_orbit_pitch = clampf(_orbit_pitch + event.relative.y * 0.005, -1.5, -0.12)
				_update_overview()

func _update_overview() -> void:
	_overview.position = Vector3(sin(_orbit_yaw) * cos(_orbit_pitch), -sin(_orbit_pitch), cos(_orbit_yaw) * cos(_orbit_pitch)) * _orbit_distance
	_overview.look_at(Vector3.ZERO, Vector3.UP)

func _exit_tree() -> void:
	if walk_mode:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
