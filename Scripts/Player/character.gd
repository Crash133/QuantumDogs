class_name Player
extends CharacterBody3D

@export var SPEED = 5.0
@export var JUMP_VELOCITY = 4.5
@export var GRAVITY = 10

@export var camera_rig: CameraRig
## Lace's size relative to her imported model: scales the model, body collider,
## hurtbox, chest (aim/attack) height and camera orbit point. Weapon reach is
## gameplay tuning in world units and does not scale.
@export var body_scale: float = 0.7
@export_group("Combat Hurtbox")
## Combat capsule radius as a multiple of body_scale. 0.5 matches the default
## CharacterBody capsule radius; adjust only for combat feel, not movement.
@export_range(0.25, 0.75, 0.01) var combat_hurtbox_radius_scale: float = 0.5
## Combat capsule total height as a multiple of body_scale. The center remains
## at the character's combat center.
@export_range(1.0, 2.5, 0.05) var combat_hurtbox_height_scale: float = 2.0
@export var health: HealthComponent

@onready var model_pivot: Node3D = $ModelPivot
@onready var combat_controller: CombatController = get_node_or_null("CombatController")

signal dealt_damage(hit: HitData)

var combat_facing: Vector3 = Vector3.FORWARD
var _time_domains: Node
var _action_leases: Node

func _process(_delta: float) -> void:
	var _probe := ScriptCostProbe.start()
	_process_body(_delta)
	ScriptCostProbe.stop(&"player.process", _probe)

func _process_body(_delta: float) -> void:
	if Input.is_action_just_pressed("cam_reset", true) and camera_rig != null and (combat_controller == null or combat_controller.input_sampling_enabled):
		camera_rig.reset_behind()


func _ready() -> void:
	_apply_body_scale()
	_time_domains = get_tree().get_first_node_in_group("combat_time_domains") as Node
	_action_leases = get_tree().get_first_node_in_group("combat_action_leases") as Node
	combat_facing = -global_basis.z.normalized()
	if health != null:
		health.decay = null
		health.decay_holdup = null
	if combat_controller != null:
		combat_controller.aerial_follow_ended.connect(_on_aerial_follow_ended)
		var animation_bridge := get_node_or_null("CombatAnimationBridge") as CombatAnimationBridge
		if animation_bridge == null:
			animation_bridge = CombatAnimationBridge.new()
			animation_bridge.name = "CombatAnimationBridge"
			animation_bridge.controller = combat_controller
			add_child(animation_bridge) # Bare Player test fixtures only.
		animation_bridge.controller = combat_controller
		var rig_presentation := get_node_or_null("WeaponRigPresentation") as WeaponRigPresentation
		if rig_presentation == null:
			rig_presentation = WeaponRigPresentation.new()
			rig_presentation.name = "WeaponRigPresentation"
			rig_presentation.player = self
			add_child(rig_presentation) # Bare Player test fixtures only.
		rig_presentation.player = self
		if camera_rig != null:
			camera_rig.targeting_service = combat_controller.targeting_service
		combat_controller.battery.value_changed.connect(_on_combat_battery_changed)
		_on_combat_battery_changed(combat_controller.battery.value, combat_controller.battery.maximum)
	var combat_events := get_node_or_null("/root/CombatEvents")
	if combat_events != null:
		var hit_landed_handler := Callable(self, "_on_combat_hit_landed")
		if not combat_events.is_connected(&"hit_landed", hit_landed_handler):
			combat_events.connect(&"hit_landed", hit_landed_handler)
	print(SPEED)

func _on_combat_battery_changed(value: float, _maximum: float) -> void:
	if health == null:
		return
	var difference := value - health.get_health()
	if difference < 0.0:
		health.reduce_health(-difference)
	elif difference > 0.0:
		health.heal_health(difference)

func _on_combat_hit_landed(hit: HitData, _target: Object) -> void:
	if hit == null or (hit.source != self and hit.source != combat_controller):
		return
	# Combat-impact camera response is owned by Game Feel's FeedbackDirector.
	dealt_damage.emit(hit)

func take_hit(hit: HitData) -> int:
	if combat_controller == null:
		return DefenseResolver.Result.IGNORED
	var result := combat_controller.receive_hit(hit, hit.source if hit != null else null)
	var presentation := get_node_or_null("WeaponRigPresentation")
	if result == DefenseResolver.Result.DAMAGED and presentation != null:
		presentation.on_damage_received()
	return result

func get_faction() -> StringName:
	return &"player"

func get_battery_meter() -> BatteryMeter:
	return combat_controller.battery if combat_controller != null else null

func get_outgoing_hit_multipliers(weapon_id: StringName) -> Vector2:
	return combat_controller.get_outgoing_hit_multipliers(weapon_id) if combat_controller != null else Vector2.ONE

func get_heat_meter() -> HeatMeter:
	return combat_controller.heat if combat_controller != null else null

func try_parry(_hit: HitData) -> bool:
	return false

func on_attack_parried() -> void:
	if combat_controller != null:
		combat_controller.on_attack_parried()

func on_enemy_launched(enemy: Node3D) -> void:
	if combat_controller != null:
		combat_controller.on_enemy_launched(enemy)

func _on_aerial_follow_ended() -> void:
	velocity = Vector3.ZERO

func is_staggered() -> bool:
	return combat_controller != null and combat_controller.state == CombatController.State.STAGGERED

func is_alive() -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and (combat_controller == null or not combat_controller.battery.is_dead)

func execute() -> bool:
	return false

func _physics_process(delta: float) -> void:
	var _probe := ScriptCostProbe.start()
	_physics_process_body(delta)
	ScriptCostProbe.stop(&"player.physics", _probe)

func _physics_process_body(delta: float) -> void:
	var time_scale := 1.0
	if is_instance_valid(_time_domains) and _time_domains.has_method("factor_for"):
		time_scale = clampf(float(_time_domains.call("factor_for", self)), 0.01, 1.0)
	var local_delta := delta * time_scale
	var lease_gravity_hold := is_instance_valid(_action_leases) and _action_leases.has_method("gravity_held") and bool(_action_leases.call("gravity_held", self))
	sample_combat_movement()
	if combat_controller != null:
		combat_controller.is_airborne = not is_on_floor()
	
	if not is_on_floor():
		if lease_gravity_hold or (combat_controller != null and combat_controller.should_suspend_gravity()):
			velocity.y = 0.0
		else:
			velocity += Vector3.DOWN * GRAVITY * local_delta
	elif combat_controller != null:
		combat_controller.reset_air_hover()

	var movement_allowed := combat_controller == null or (combat_controller.input_sampling_enabled and combat_controller.state not in [CombatController.State.DEAD, CombatController.State.STAGGERED, CombatController.State.EXECUTING, CombatController.State.AERIAL_FOLLOW])
	if movement_allowed and is_on_floor():
		var jump_pressed := false
		if combat_controller != null:
			if combat_controller.input_buffer.has_valid(&"jump", combat_controller.tick) and combat_controller.combo.can_cancel(&"jump"):
				combat_controller.input_buffer.consume(&"jump", combat_controller.tick)
				if combat_controller.combo.current_node != null:
					combat_controller.combo.cancel()
				jump_pressed = true
		else:
			jump_pressed = Input.is_action_just_pressed(&"jump")
		if jump_pressed:
			velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backwards")
	if not movement_allowed:
		input_dir = Vector2.ZERO
	if combat_controller != null:
		combat_controller.is_moving = input_dir.length_squared() > 0.01
	var direction := Vector3.ZERO
	if input_dir.length_squared() > 0.001:
		var camera_basis := camera_rig.global_basis if camera_rig != null else global_basis
		var forward := -camera_basis.z
		var right := camera_basis.x
		direction = (right * input_dir.x + forward * -input_dir.y).normalized()
		if combat_controller != null:
			combat_controller.input_direction = direction
	else:
		if combat_controller != null:
			combat_controller.input_direction = Vector3.ZERO

	var is_dashing := combat_controller != null and combat_controller.state == CombatController.State.DASHING
	var signature_intent: Dictionary = {}
	if is_dashing:
		var dash_speed := combat_controller.tuning.dash_distance * float(combat_controller.tuning.tick_rate) / float(maxi(1, combat_controller.tuning.dash_iframe_ticks))
		velocity.x = combat_controller.dash_direction.x * dash_speed
		velocity.z = combat_controller.dash_direction.z * dash_speed
	else:
		velocity.x = direction.x * SPEED if direction.length_squared() > 0.001 else move_toward(velocity.x, 0.0, SPEED * time_scale)
		velocity.z = direction.z * SPEED if direction.length_squared() > 0.001 else move_toward(velocity.z, 0.0, SPEED * time_scale)
	if combat_controller != null and combat_controller.state in [CombatController.State.DEAD, CombatController.State.STAGGERED]:
		velocity.x = 0.0
		velocity.z = 0.0

	var signature_lunge_active := false
	if not is_dashing and combat_controller != null:
		signature_intent = combat_controller.get_signature_lunge_intent(global_position, local_delta)
		signature_lunge_active = bool(signature_intent.get("active", false))
		if signature_lunge_active:
			var signature_velocity: Vector3 = signature_intent.get("velocity", Vector3.ZERO)
			velocity.x = signature_velocity.x
			velocity.z = signature_velocity.z
	if not is_dashing and not signature_lunge_active and combat_controller != null and combat_controller.combo.current_node != null:
		var attack_node := combat_controller.combo.current_node
		if attack_node.lunge_distance > 0.0 and direction.length_squared() <= 0.001:
			var lunge_speed := attack_node.lunge_distance * float(combat_controller.tuning.tick_rate) / float(attack_node.duration_ticks)
			velocity.x = combat_controller.attack_direction.x * lunge_speed
			velocity.z = combat_controller.attack_direction.z * lunge_speed
	if combat_controller != null and combat_controller.state == CombatController.State.EXECUTING:
		velocity = combat_controller.execution_body_velocity()
	if combat_controller != null and combat_controller.state == CombatController.State.AERIAL_FOLLOW:
		velocity = combat_controller.get_aerial_follow_velocity()
	var facing := combat_controller.dash_direction if is_dashing else direction
	if signature_lunge_active:
		var target := signature_intent.get("target") as Node3D
		if is_instance_valid(target):
			facing = target.global_position - global_position
			facing.y = 0.0
	if combat_controller != null and combat_controller.state == CombatController.State.AERIAL_FOLLOW:
		var follow_target := combat_controller.get_aerial_follow_target()
		if follow_target != null:
			facing = follow_target.global_position - global_position
			facing.y = 0.0
	if not is_dashing and not signature_lunge_active and combat_controller != null and combat_controller.state == CombatController.State.ATTACKING:
		facing = combat_controller.attack_direction
	if combat_controller != null and combat_controller.state == CombatController.State.EXECUTING:
		facing = combat_controller.execution.facing_direction
	if facing.length_squared() > 0.001:
		combat_facing = facing.normalized()
	if model_pivot != null:
		# This imported model faces local +Z; gameplay facing is world space.
		model_pivot.global_basis = Basis.looking_at(-combat_facing, Vector3.UP).scaled(model_pivot.global_basis.get_scale())

	velocity *= time_scale
	move_and_slide()
	velocity /= time_scale
	if combat_controller != null and combat_controller.state == CombatController.State.EXECUTING:
		combat_controller.after_execution_move()
	
func get_combat_facing() -> Vector3:
	return combat_facing

## Predict the authored Tip pose for an execution approach candidate without
## moving the marker or changing the live rig. The final solver still measures
## the actual mounted Tip after body movement and animation evaluation.
func get_execution_tip_world_at(root_position: Vector3, facing: Vector3, tip: Node3D) -> Vector3:
	if model_pivot == null or tip == null or not is_instance_valid(tip):
		return root_position
	var flat_facing := Vector3(facing.x, 0.0, facing.z).normalized()
	if flat_facing.is_zero_approx():
		return root_position
	var pivot_inverse := model_pivot.global_transform.affine_inverse()
	var tip_in_pivot := pivot_inverse * tip.global_transform
	var desired_basis := Basis.looking_at(-flat_facing, Vector3.UP).scaled(model_pivot.global_basis.get_scale())
	var pivot_offset := global_basis * model_pivot.position
	var desired_pivot := Transform3D(desired_basis, root_position + pivot_offset)
	return (desired_pivot * tip_in_pivot).origin

## Revolver aim: the locked target, else the enemy nearest the camera's screen
## centre, else straight ahead. Lace turns to face the shot.
func get_revolver_aim(origin: Vector3) -> Vector3:
	var service := combat_controller.targeting_service if combat_controller != null else null
	var target: Node3D = service.locked_target if service != null and is_instance_valid(service.locked_target) else null
	if target == null and service != null and is_inside_tree():
		target = service.find_nearest_to_screen_center(get_viewport().get_camera_3d(), origin)
	if target == null:
		return combat_facing
	var aim_point: Vector3 = target.get_combat_center() if target.has_method("get_combat_center") else target.global_position
	var direction := (aim_point - origin).normalized()
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() > 0.001:
		combat_facing = flat.normalized()
		if model_pivot != null:
			model_pivot.global_basis = Basis.looking_at(-combat_facing, Vector3.UP).scaled(model_pivot.global_basis.get_scale())
	return direction

func get_combat_center() -> Vector3:
	return global_position + Vector3.UP * body_scale

func _apply_body_scale() -> void:
	if model_pivot != null:
		model_pivot.scale = Vector3.ONE * body_scale
	var body_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if body_shape != null and body_shape.shape is CapsuleShape3D:
		var capsule := body_shape.shape.duplicate() as CapsuleShape3D # The scene's shape is shared.
		capsule.radius *= body_scale
		capsule.height *= body_scale
		body_shape.shape = capsule
		body_shape.position *= body_scale
	var orbit := get_node_or_null("OrbitPoint") as Node3D
	if orbit != null:
		orbit.position *= body_scale

func sample_combat_movement() -> void:
	if combat_controller == null:
		return
	combat_controller.is_airborne = not is_on_floor()
	var input_dir := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_backwards")
	if not combat_controller.input_sampling_enabled:
		input_dir = Vector2.ZERO
	var camera_basis := camera_rig.global_basis if camera_rig != null else global_basis
	var direction := camera_basis.x * input_dir.x - camera_basis.z * -input_dir.y
	direction.y = 0.0
	combat_controller.input_direction = direction.normalized()
	combat_controller.is_moving = input_dir.length_squared() > 0.01
