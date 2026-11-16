class_name CombatController
extends Node

const EXECUTION_SHOCKWAVE := preload("res://Scripts/Combat/execution_shockwave.gd")

## Player combat rules at a fixed 60 Hz tick. Owns: the State machine and its
## legal transitions; input buffering and polling; combo stepping (ComboRunner);
## defense resolution against incoming hits; meters (HeatMeter, BatteryMeter,
## DashCharges, RevolverAmmo); aerial follow (AerialFollow), gravity suspension
## (AirControl) and Elite execution (ExecutionDriver); CombatEvents emission.
## Hit detection lives in CombatHitAdapter/native HitManager; weapon specials in
## WeaponAbility resources driven by WeaponAbilityHost.

enum State { IDLE, MOVING, ATTACKING, BLOCKING, PARRYING, DASHING, EXECUTING, STAGGERED, DEAD, AERIAL_FOLLOW }

signal revolver_shot_requested(origin: Vector3, direction: Vector3)
signal aerial_follow_ended
signal loadout_changed

@export var tuning: CombatTuning
@export var ranged_weapon: RangedWeaponData
@export var weapons: Array[WeaponData] = []
@export var active_weapon_index: int = 0
var revolver_available: bool = true
@export var battery_drain_enabled: bool = true
@export var targeting_service: TargetingService
@export var targeting_service_path: NodePath
## Each switch action always selects the same weapon, whatever the loadout order.
## The keys/buttons behind these actions are rebindable in Options.
@export var weapon_switch_actions: Dictionary[StringName, StringName] = {&"switch_1": &"mantis_blades", &"switch_2": &"saber", &"switch_3": &"rocket_lance", &"switch_4": &"greatsword"}

var combo: ComboRunner = ComboRunner.new()
var input_buffer: InputBuffer = InputBuffer.new()
var defense: DefenseResolver = DefenseResolver.new()
var heat: HeatMeter = HeatMeter.new()
var battery: BatteryMeter = BatteryMeter.new()
var dash: DashCharges = DashCharges.new()
var revolver: RevolverAmmo = RevolverAmmo.new()
var aerial_follow: AerialFollow = AerialFollow.new()
var air: AirControl = AirControl.new()
var execution: ExecutionDriver = ExecutionDriver.new()
var weapon_ability_host: WeaponAbilityHost
var state: State = State.IDLE:
	set(next):
		if not _is_legal_transition(next):
			push_warning("Illegal Combat state transition %s -> %s; ignored" % [_state_label(state), _state_label(next)])
			return
		state = next
var tick: int = 0
var input_sampling_enabled: bool = true
var parry_pressed_tick: int = -100000
var is_airborne: bool = false
var is_moving: bool = false
var input_direction: Vector3 = Vector3.ZERO
var attack_direction: Vector3 = Vector3.FORWARD
var dash_direction: Vector3 = Vector3.FORWARD
var _dash_ticks_left: int = 0
var _dash_started_this_tick: bool = false
var _run_hit_multipliers: Dictionary[StringName, Vector2] = {}
var _local_tick_accumulator: float = 0.0
var _pending_pressed_actions: Array[StringName] = []
var _pending_block_held: bool = false
var _time_domains: Node
var _action_leases: Node
var _execution_action_lease_token: int = -1
var _seen_parry_contacts: Dictionary[StringName, bool] = {}

const COMBAT_ACTIONS: Array[StringName] = [&"light", &"heavy", &"dash", &"block", &"jump", &"execute", &"shoot", &"switch_1", &"switch_2", &"switch_3", &"switch_4", &"cam_lock", &"cam_reset"]

func _state_label(value: int) -> String:
	return String(State.keys()[value]) if State.values().has(value) else str(value)

func _is_legal_transition(next: int) -> bool:
	if not State.values().has(next):
		return false
	if next == state:
		return true
	# Death is terminal for this controller instance. Revives are consumed by
	# Battery before death; resetting the arena creates a new controller.
	if state == State.DEAD:
		return false
	if next in [State.DEAD, State.STAGGERED]:
		return true
	match state:
		State.STAGGERED:
			return next == State.IDLE and not heat.is_staggered()
		State.EXECUTING:
			return next == State.IDLE and not _execution_target_valid()
		State.DASHING:
			return next == State.IDLE and _dash_ticks_left <= 0
		State.AERIAL_FOLLOW:
			return next == State.IDLE and not is_instance_valid(aerial_follow.target)
	return true

func _ready() -> void:
	process_physics_priority = -1
	execution.ended.connect(_on_execution_ended)
	_time_domains = get_tree().get_first_node_in_group("combat_time_domains") as Node
	_action_leases = get_tree().get_first_node_in_group("combat_action_leases") as Node
	if not targeting_service_path.is_empty():
		targeting_service = get_node_or_null(targeting_service_path) as TargetingService
	if tuning == null:
		tuning = CombatTuning.new()
	else:
		# Debug overlays and run builds tune this resource at runtime. PackedScene
		# instances can share the authored .tres, so each controller owns a copy.
		tuning = tuning.duplicate(true) as CombatTuning
	assert(tuning.validate().is_empty(), "Invalid CombatTuning cancel_action_priority: %s" % "; ".join(tuning.validate()))
	if targeting_service != null:
		targeting_service.tuning = tuning
	var rebinder := InputRebinder.new()
	rebinder.ensure_actions()
	rebinder.load_bindings()
	if weapons.is_empty():
		weapons = WeaponCatalog.create_default_weapons()
	_validate_weapon_graphs()
	input_buffer.configure(tuning.input_buffer_ticks)
	aerial_follow.tuning = tuning
	air.tuning = tuning
	execution.tuning = tuning
	heat.configure(tuning)
	battery.configure(tuning, battery_drain_enabled)
	dash.configure(tuning)
	if ranged_weapon == null:
		ranged_weapon = RangedWeaponData.new()
		ranged_weapon.capacity = tuning.revolver_capacity
		ranged_weapon.shot_interval_ticks = tuning.revolver_shot_interval_ticks
		ranged_weapon.regen_ticks_per_shot = tuning.revolver_regen_ticks_per_shot
	var ammo_tuning := tuning.duplicate() as CombatTuning
	ammo_tuning.revolver_capacity = ranged_weapon.capacity
	ammo_tuning.revolver_shot_interval_ticks = ranged_weapon.shot_interval_ticks
	ammo_tuning.revolver_regen_ticks_per_shot = ranged_weapon.regen_ticks_per_shot
	revolver.configure(ammo_tuning)
	if not weapons.is_empty():
		active_weapon_index = clampi(active_weapon_index, 0, weapons.size() - 1)
		combo.set_weapon(weapons[active_weapon_index])
	combo.advanced.connect(_on_combo_advanced)
	combo.weapon_changed.connect(_on_weapon_changed)
	heat.value_changed.connect(_on_heat_changed)
	heat.staggered.connect(_on_staggered)
	heat.stagger_ended.connect(_on_stagger_ended)
	battery.value_changed.connect(_on_battery_changed)
	battery.died.connect(_on_player_died)

func _validate_weapon_graphs() -> void:
	var invalid_graphs := PackedStringArray()
	for index in range(weapons.size()):
		var weapon := weapons[index]
		var errors: Array[String] = []
		if weapon == null:
			errors.append("Weapon entry is null")
		else:
			errors = weapon.validate()
		if errors.is_empty():
			continue
		var message := "Invalid combo graph at weapon slot %d: %s" % [index, "; ".join(errors)]
		invalid_graphs.append(message)
		if not OS.is_debug_build():
			push_warning(message)
		var fallback := WeaponData.new() if weapon == null else weapon.duplicate() as WeaponData
		fallback.graph = null
		weapons[index] = fallback
	# Prepare every safe fallback before the debug assertion interrupts this
	# function. Release builds omit assert and keep combat recoverable at Rest.
	assert(invalid_graphs.is_empty(), "\n".join(invalid_graphs))

func _physics_process(_delta: float) -> void:
	var _probe := ScriptCostProbe.start()
	_physics_process_body(_delta)
	ScriptCostProbe.stop(&"combat.controller", _probe)

func _physics_process_body(_delta: float) -> void:
	var body := get_parent()
	if body != null and body.has_method("sample_combat_movement"):
		body.sample_combat_movement()
	var pressed: Array[StringName] = []
	for action in COMBAT_ACTIONS:
		var exact_modifiers := action in [&"light", &"heavy", &"cam_lock", &"cam_reset"]
		if input_sampling_enabled and InputMap.has_action(action) and Input.is_action_just_pressed(action, exact_modifiers) and action not in _pending_pressed_actions:
			pressed.append(action)
	_pending_pressed_actions.append_array(pressed)
	_pending_block_held = input_sampling_enabled and InputMap.has_action(&"block") and Input.is_action_pressed(&"block")
	var body_factor := 1.0
	if not is_instance_valid(_time_domains):
		_time_domains = get_tree().get_first_node_in_group("combat_time_domains") as Node if is_inside_tree() else null
	if is_instance_valid(_time_domains) and _time_domains.has_method("factor_for") and body is Node:
		body_factor = clampf(float(_time_domains.call("factor_for", body)), 0.01, 1.0)
	var tick_rate := float(tuning.tick_rate) if tuning != null else 60.0
	if execution.is_active():
		execution.advance(maxf(0.0, _delta * body_factor))
	_local_tick_accumulator += maxf(0.0, _delta * body_factor) * tick_rate
	while _local_tick_accumulator >= 1.0 - 0.000001:
		_local_tick_accumulator -= 1.0
		step(_pending_pressed_actions, _pending_block_held)
		_pending_pressed_actions.clear()

func step(pressed_actions: Array[StringName] = [], block_held: bool = false) -> void:
	tick += 1
	_dash_started_this_tick = false
	air.begin_tick()
	if state == State.DEAD:
		return
	var was_following := state == State.AERIAL_FOLLOW
	var follow_active := aerial_follow.step(tick)
	if was_following and not follow_active:
		_end_aerial_follow()
	if state == State.EXECUTING and not execution.committed() and not _execution_target_valid():
		_abort_execution(&"target_invalid")
	for action in pressed_actions:
		if was_following:
			continue
		input_buffer.push(action, tick)
		if action == &"block":
			parry_pressed_tick = tick
	var priority_cancel_handled := _process_priority_cancel()
	if not priority_cancel_handled and input_buffer.has_valid(&"dash", tick) and _try_dash():
		input_buffer.consume(&"dash", tick)
	if priority_cancel_handled and block_held and state not in [State.STAGGERED, State.EXECUTING, State.DASHING, State.DEAD]:
		state = State.BLOCKING
	if state == State.DEAD:
		return
	if not priority_cancel_handled and state not in [State.STAGGERED, State.EXECUTING, State.DASHING, State.AERIAL_FOLLOW]:
		_process_weapon_switches()
		if state not in [State.STAGGERED, State.EXECUTING, State.DASHING, State.AERIAL_FOLLOW]:
			if block_held:
				state = State.BLOCKING
			else:
				if state == State.BLOCKING:
					state = State.IDLE
				_process_combat_inputs()
		if state != State.AERIAL_FOLLOW and input_buffer.has_valid(&"execute", tick) and _try_execute_target():
			input_buffer.consume(&"execute", tick)
	if _dash_ticks_left > 0 and not _dash_started_this_tick:
		_dash_ticks_left -= 1
		if _dash_ticks_left == 0 and state == State.DASHING:
			state = State.IDLE
	air.step()
	combo.step()
	dash.step()
	revolver.step()
	heat.step(_is_heat_active())
	battery.step(_is_battery_active(), battery_drain_enabled and tuning.battery_drain_enabled)
	input_buffer.expire(tick)
	if state not in [State.DEAD, State.STAGGERED, State.DASHING, State.BLOCKING, State.EXECUTING, State.AERIAL_FOLLOW]:
		state = State.ATTACKING if combo.current_node != null else (State.MOVING if is_moving else State.IDLE)

func receive_hit(hit: HitData, attacker: Object = null) -> DefenseResolver.Result:
	if hit == null or state == State.DEAD:
		return DefenseResolver.Result.IGNORED
	if state == State.EXECUTING:
		return DefenseResolver.Result.IGNORED
	var fully_vulnerable := state == State.STAGGERED
	var parry_active := not fully_vulnerable and tick - parry_pressed_tick >= 0 and tick - parry_pressed_tick <= tuning.parry_window_ticks
	var iframe_active := state == State.DASHING and dash.is_invulnerable()
	var result := defense.resolve(hit.damage, iframe_active, parry_active, state == State.BLOCKING, tuning)
	var unique_parry_contact := result != DefenseResolver.Result.PARRIED or _claim_parry_contact(hit, attacker)
	if unique_parry_contact:
		var from_drone := attacker is Enemy and (attacker as Enemy).definition != null and (attacker as Enemy).definition.role == &"drone"
		defense.apply_to_meters(result, hit.damage, heat, battery, tuning, not from_drone)
	match result:
		DefenseResolver.Result.PARRIED:
			var confirmed_contact: HitContactContext = hit.contact_context
			if state not in [State.EXECUTING, State.DASHING, State.AERIAL_FOLLOW]:
				state = State.PARRYING
			if not unique_parry_contact:
				return result
			# The attacker learns once that its swing was parried (opens elite armor).
			if typeof(attacker) == TYPE_OBJECT and is_instance_valid(attacker) and attacker.has_method("on_attack_parried") and attacker != self:
				attacker.on_attack_parried()
			_emit_event(&"parried", [self, attacker])
			if attacker != null and attacker.has_method("on_parried"):
				attacker.on_parried(self)
			var presentation := get_parent().get_node_or_null("ParryPresentationController") if get_parent() != null else null
			if is_instance_valid(presentation) and presentation.has_method("on_confirmed_parry"):
				presentation.call("on_confirmed_parry", confirmed_contact)
		DefenseResolver.Result.BLOCKED:
			_emit_event(&"blocked", [attacker])
		DefenseResolver.Result.DAMAGED:
			_emit_event(&"damage_taken", [hit.damage, attacker])
	return result

## Claim one confirmed melee attack contact for armor opening and feedback.
## Duplicate native callbacks still return PARRIED but cannot replay side effects.
func _claim_parry_contact(hit: HitData, attacker: Object) -> bool:
	if hit == null or hit.contact_context == null:
		return true # Legacy/manual contacts have no stable collision identity.
	var context := hit.contact_context
	if context.attack_id == &"" and context.hitbox_id < 0:
		return true
	var physics_tick := context.physics_tick if context.physics_tick > 0 else Engine.get_physics_frames()
	var attacker_id := attacker.get_instance_id() if typeof(attacker) == TYPE_OBJECT and is_instance_valid(attacker) else 0
	var attack_key := context.attack_id if context.attack_id != &"" else StringName("hitbox:%d" % context.hitbox_id)
	var key := StringName("%d:%d:%s" % [physics_tick, attacker_id, attack_key])
	if _seen_parry_contacts.has(key):
		return false
	_seen_parry_contacts[key] = true
	if _seen_parry_contacts.size() > 512:
		_seen_parry_contacts.clear()
		_seen_parry_contacts[key] = true
	return true

func start_dash() -> bool:
	return _try_dash()

func _try_dash() -> bool:
	if state in [State.STAGGERED, State.EXECUTING, State.DEAD, State.AERIAL_FOLLOW]:
		return false
	if combo.current_node != null and not combo.can_cancel(&"dodge"):
		return false
	if not dash.spend():
		return false
	var body := get_parent() as Node3D
	var facing := _body_facing(body)
	dash_direction = input_direction.normalized() if input_direction.length_squared() > 0.001 else facing.normalized()
	combo.cancel()
	state = State.DASHING
	_dash_ticks_left = tuning.dash_iframe_ticks
	_dash_started_this_tick = true
	_emit_event(&"dash_used", [dash.current])
	return true

func _process_combat_inputs() -> void:
	if input_buffer.consume(&"cam_lock", tick) and targeting_service != null:
		var origin := Vector3.ZERO
		var facing := Vector3.FORWARD
		var body := get_parent() as Node3D
		if body != null:
			origin = body.global_position
			facing = _body_facing(body)
		targeting_service.toggle_lock(origin, facing)
	for action: StringName in [&"light", &"heavy"]:
		if input_buffer.has_valid(action, tick) and _try_aerial_follow(action):
			return
	if input_buffer.has_valid(&"light", tick):
		if combo.press(&"light", is_airborne):
			input_buffer.consume(&"light", tick)
			_update_attack_direction()
	elif input_buffer.has_valid(&"heavy", tick):
		if combo.press(&"heavy", is_airborne):
			input_buffer.consume(&"heavy", tick)
			_update_attack_direction()
	if not revolver_available:
		input_buffer.consume(&"shoot", tick)
	elif input_buffer.has_valid(&"shoot", tick) and revolver.fire():
		input_buffer.consume(&"shoot", tick)
		_fire_revolver()

## Resolve simultaneous attack-cancel actions using the authored CombatTuning order.
## Only the winning accepted cancel runs this tick; rejected cancels remain buffered.
func _process_priority_cancel() -> bool:
	if combo.current_node == null:
		return false
	var candidates: Array[Dictionary] = []
	if input_buffer.has_valid(&"block", tick) and combo.can_cancel(&"block_parry"):
		candidates.append({"action": &"block_parry", "input": &"block"})
	if input_buffer.has_valid(&"dash", tick) and combo.can_cancel(&"dodge"):
		candidates.append({"action": &"dodge", "input": &"dash"})
	if input_buffer.has_valid(&"execute", tick) and combo.can_cancel(&"execute"):
		candidates.append({"action": &"execute", "input": &"execute"})
	if input_buffer.has_valid(&"jump", tick) and combo.can_cancel(&"jump"):
		candidates.append({"action": &"jump", "input": &"jump"})
	for switch_action in weapon_switch_actions:
		if input_buffer.has_valid(switch_action, tick) and combo.can_cancel(&"switch"):
			candidates.append({"action": &"switch", "input": switch_action})
	if candidates.is_empty():
		return false
	for attack_action: StringName in [&"light", &"heavy"]:
		if input_buffer.has_valid(attack_action, tick) and combo.can_press(attack_action, is_airborne):
			candidates.append({"action": attack_action, "input": attack_action})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _cancel_priority_rank(a.action) < _cancel_priority_rank(b.action)
	)
	for candidate: Dictionary in candidates:
		match StringName(candidate.action):
			&"block_parry":
				combo.cancel()
				input_buffer.consume(candidate.input, tick)
				return true
			&"dodge":
				if _try_dash():
					input_buffer.consume(candidate.input, tick)
					return true
			&"execute":
				if _try_execute_target():
					input_buffer.consume(candidate.input, tick)
					return true
			&"jump":
				combo.cancel()
				return true
			&"switch":
				var weapon_id: StringName = weapon_switch_actions.get(candidate.input, &"")
				var index := weapons.find_custom(func(item: WeaponData) -> bool: return item != null and item.id == weapon_id)
				if index >= 0 and switch_weapon(index):
					input_buffer.consume(candidate.input, tick)
					return true
			&"light", &"heavy":
				if combo.press(candidate.action, is_airborne):
					input_buffer.consume(candidate.input, tick)
					_update_attack_direction()
					return true
	return false

func _cancel_priority_rank(action: StringName) -> int:
	if tuning != null:
		var rank := tuning.cancel_action_priority.find(action)
		if rank >= 0:
			return rank
	return 2147483647

func _process_weapon_switches() -> void:
	for action: StringName in weapon_switch_actions:
		if not input_buffer.has_valid(action, tick):
			continue
		var weapon_id: StringName = weapon_switch_actions[action]
		var index := weapons.find_custom(func(weapon: WeaponData) -> bool: return weapon != null and weapon.id == weapon_id)
		if index < 0:
			input_buffer.consume(action, tick) # Weapon not in the loadout: nothing to switch to.
			continue
		if switch_weapon(index):
			input_buffer.consume(action, tick)
			return

func switch_weapon(index: int) -> bool:
	if state in [State.DEAD, State.STAGGERED, State.EXECUTING, State.DASHING, State.AERIAL_FOLLOW]:
		return false
	if index < 0 or index >= weapons.size():
		return false
	if not combo.switch_weapon(weapons[index]):
		return false
	active_weapon_index = index
	return true

## Replace run-owned melee availability at run/level setup, outside attacks.
## Empty/invalid arrays are rejected without mutating the current combat state.
func apply_run_loadout(available: Array[WeaponData], revolver_enabled: bool) -> Error:
	if state != State.IDLE or combo.current_node != null:
		return ERR_BUSY
	if available.is_empty():
		return ERR_INVALID_PARAMETER
	var seen: Dictionary = {}
	var validated: Array[WeaponData] = []
	for weapon in available:
		if weapon == null or weapon.id == &"" or seen.has(weapon.id) or not weapon.validate().is_empty():
			return ERR_INVALID_DATA
		seen[weapon.id] = true
		validated.append(weapon)

	var previous_weapons := weapons.duplicate()
	var previous_revolver := revolver_available
	var previous_id := combo.weapon.id if combo.weapon != null else &""
	var selected_index := 0
	for index in range(validated.size()):
		if validated[index].id == previous_id:
			selected_index = index
			break

	var changed := previous_revolver != revolver_enabled or previous_weapons.size() != validated.size()
	if not changed:
		for index in range(validated.size()):
			if previous_weapons[index] != validated[index]:
				changed = true
				break
	weapons = validated
	revolver_available = revolver_enabled
	active_weapon_index = selected_index
	var selected_weapon := weapons[selected_index]
	if combo.weapon != selected_weapon:
		combo.set_weapon(selected_weapon)
	if not revolver_available:
		input_buffer.consume(&"shoot", tick)
	if changed:
		loadout_changed.emit()
	return OK

## Apply a derived run build only at a safe boundary. Meter configure methods
## refill/reset state, so application updates their tuning references directly.
func apply_run_build(build: CombatRunBuild) -> Error:
	if state != State.IDLE or combo.current_node != null:
		return ERR_BUSY
	if build == null or not build.validate().is_empty():
		return ERR_INVALID_DATA
	var next_tuning := build.tuning
	if next_tuning == null:
		return ERR_INVALID_DATA
	# Preflight loadout checks before changing any live state.
	if build.weapons.is_empty():
		return ERR_INVALID_DATA
	for weapon in build.weapons:
		if weapon == null or weapon.id == &"" or not weapon.validate().is_empty():
			return ERR_INVALID_DATA
	for weapon_id in build.hit_multipliers:
		var value: Vector2 = build.hit_multipliers[weapon_id]
		if weapon_id == &"" or not value.is_finite() or value.x < 0.0 or value.y < 0.0:
			return ERR_INVALID_DATA

	tuning = next_tuning
	_run_hit_multipliers = build.hit_multipliers.duplicate()
	if targeting_service != null:
		targeting_service.tuning = tuning
	input_buffer.configure(tuning.input_buffer_ticks)
	heat.tuning = tuning
	heat.maximum = tuning.heat_max
	heat.stagger_duration = tuning.stagger_ticks
	if heat.value > heat.maximum:
		heat.value = heat.maximum
		heat.value_changed.emit(heat.value, heat.maximum)
	battery.tuning = tuning
	dash.tuning = tuning
	aerial_follow.tuning = tuning
	air.tuning = tuning
	execution.tuning = tuning
	var loadout_error := apply_run_loadout(build.weapons, build.revolver_available)
	if loadout_error != OK:
		return loadout_error
	_refresh_weapon_ability_context()
	return OK

func get_outgoing_hit_multipliers(weapon_id: StringName) -> Vector2:
	return _run_hit_multipliers.get(weapon_id, Vector2.ONE)

func _refresh_weapon_ability_context() -> void:
	var actor := get_parent()
	if actor == null:
		return
	for child in actor.get_children():
		if child is CombatHitAdapter and child.abilities != null:
			child.abilities.refresh_build_context()

func on_enemy_launched(enemy: Node3D) -> void:
	if state not in [State.DEAD, State.STAGGERED, State.EXECUTING, State.AERIAL_FOLLOW]:
		aerial_follow.record_launch(enemy, tick)

func _try_aerial_follow(action: StringName) -> bool:
	var body := get_parent() as Node3D
	if body == null:
		return false
	var locked := targeting_service.locked_target if targeting_service != null else null
	var center: Vector3 = body.get_combat_center() if body.has_method("get_combat_center") else body.global_position
	if not aerial_follow.try_start(body.global_position, _body_facing(body), input_buffer.pressed_tick(action), tick, locked, center - body.global_position):
		return false
	combo.cancel()
	input_buffer.clear()
	air.clear()
	state = State.AERIAL_FOLLOW
	return true

func get_aerial_follow_target() -> Node3D:
	return aerial_follow.target if is_instance_valid(aerial_follow.target) else null

func get_aerial_follow_destination() -> Vector3:
	return aerial_follow.destination()

func get_aerial_follow_velocity() -> Vector3:
	var body := get_parent() as Node3D
	if body == null or get_aerial_follow_target() == null:
		return Vector3.ZERO
	var offset := get_aerial_follow_destination() - body.global_position
	# A launcher can open its window before the enemy's first upward physics
	# step. Do not finish the follow on the floor before Lace has actually jumped.
	var on_floor: bool = body is CharacterBody3D and body.is_on_floor()
	if offset.length() <= 0.12 and not on_floor:
		_end_aerial_follow()
		return Vector3.ZERO
	return offset.normalized() * minf(tuning.aerial_follow_speed, offset.length() * float(tuning.tick_rate))

func _end_aerial_follow() -> void:
	var was_following := state == State.AERIAL_FOLLOW
	aerial_follow.cancel()
	input_buffer.clear()
	if was_following:
		state = State.IDLE
		aerial_follow_ended.emit()

func _try_execute_target() -> bool:
	if combo.current_node != null and not combo.can_cancel(&"execute"):
		return false
	var body := get_parent() as CharacterBody3D
	if body != null:
		execution.select(targeting_service, body.global_position, _body_facing(body))
	else:
		execution.select(targeting_service, Vector3.ZERO, Vector3.FORWARD)
	if not _execution_target_valid():
		execution.target = null
		return false
	var victim := execution.target_node()
	if not tuning.execution_animation_enabled:
		return _execute_instantly(victim)
	var presentation := body.get_node_or_null("WeaponRigPresentation") as WeaponRigPresentation if body != null else null
	var weapon := combo.weapon
	var profile: WeaponContactProfile = weapon.contact_profile if weapon != null else null
	if presentation == null or profile == null or profile.execution_tip_id == &"":
		return false
	var unit := presentation.get_weapon_unit(profile.execution_tip_id)
	var motion := presentation.get_contact_motion()
	var center := _execution_center_for(victim)
	if unit == null or center == null or motion == null:
		return false
	var begin_error := execution.begin(body, victim, unit, center, profile, motion)
	if begin_error != OK:
		return false
	var contact_handler := Callable(self, "_on_execution_contact_reached")
	var motion_handler := Callable(self, "_on_execution_motion_ended")
	if not motion.contact_reached.is_connected(contact_handler):
		motion.contact_reached.connect(contact_handler)
	if not motion.ended.is_connected(motion_handler):
		motion.ended.connect(motion_handler)
	if not is_instance_valid(_action_leases) or not _action_leases.has_method("acquire_execution"):
		push_error("CombatController execution requires CombatActionLeases in the active combat scene")
		execution.abort(&"missing_action_leases")
		return false
	var body_node := get_parent() as Node
	_execution_action_lease_token = int(_action_leases.call("acquire_execution", self, body_node, victim))
	if _execution_action_lease_token < 0:
		execution.abort(&"lease_rejected")
		return false
	combo.cancel()
	state = State.EXECUTING
	return true

## Animation-free execution (tuning.execution_animation_enabled off): kill now, then shockwave.
func _execute_instantly(victim: Node3D) -> bool:
	var center := _execution_center_for(victim)
	var center_position := center.global_position if center != null else victim.global_position
	execution.target = null
	if not victim.execute(): # May free the victim; its position was read first.
		return false
	combo.cancel()
	EXECUTION_SHOCKWAVE.apply(get_tree(), center_position, get_parent(), victim, tuning)
	_emit_event(&"executed", [victim])
	return true

func get_execution_target() -> Node3D:
	return execution.target_node()

func get_signature_lunge_intent(actor_position: Vector3, delta: float) -> Dictionary:
	return weapon_ability_host.signature_lunge_intent(actor_position, delta) if is_instance_valid(weapon_ability_host) else {}

func finish_execution() -> bool:
	# Kept as a compatibility shim for old callers. Root proximity never commits;
	# only the SkeletonModifier's action-id/contact callback may supply evidence.
	return false

func _on_execution_contact_reached(action_id: int, actual_tip: Vector3) -> void:
	if state != State.EXECUTING or execution.phase != ExecutionDriver.Phase.CONTACT:
		return
	var victim := execution.target_node()
	if not execution.commit_contact(action_id, actual_tip):
		return
	EXECUTION_SHOCKWAVE.apply(get_tree(), execution.center_snapshot, get_parent(), victim, tuning)
	_emit_event(&"executed", [victim])

func _on_execution_motion_ended(action_id: int, reason: StringName) -> void:
	execution.motion_ended(action_id, reason)

func _on_execution_ended(reason: StringName) -> void:
	if state != State.EXECUTING:
		return
	_release_execution_action_lease()
	if reason != &"completed":
		execution.target = null
	state = State.IDLE

func execution_body_velocity() -> Vector3:
	return execution.body_velocity if state == State.EXECUTING else Vector3.ZERO

func after_execution_move() -> void:
	if state == State.EXECUTING:
		execution.after_body_move()

func _execution_center_for(victim: Node3D) -> Node3D:
	if not is_instance_valid(victim):
		return null
	if victim.has_method("get_execution_center"):
		return victim.get_execution_center() as Node3D
	for property in victim.get_property_list():
		if StringName(property.get("name", "")) == &"execution_center":
			return victim.get("execution_center") as Node3D
	return victim.get_node_or_null("ExecutionCenter") as Node3D

func _abort_execution(reason: StringName) -> void:
	if execution.is_active():
		execution.abort(reason)
	_release_execution_action_lease()
	execution.target = null
	if state == State.EXECUTING:
		state = State.IDLE

func _execution_target_valid() -> bool:
	return execution.is_valid(get_parent() as Node3D)

func set_execution_target(target: Object) -> void:
	execution.target = target

func _release_execution_action_lease() -> void:
	if _execution_action_lease_token < 0:
		return
	if is_instance_valid(_action_leases) and _action_leases.has_method("release"):
		_action_leases.call("release", _execution_action_lease_token)
	_execution_action_lease_token = -1

func should_suspend_gravity() -> bool:
	return air.suspends_gravity(is_airborne)

func reset_air_hover() -> void:
	air.reset()

func hold_airborne(ticks: int) -> void:
	air.hold(ticks)

func on_attack_parried() -> void:
	heat.add_heat(tuning.heat_when_parried)

func _fire_revolver() -> void:
	var origin := Vector3.ZERO
	var direction := Vector3.FORWARD
	var body := get_parent() as Node3D
	if body != null:
		origin = body.get_combat_center() if body.has_method("get_combat_center") else body.global_position
		direction = body.get_revolver_aim(origin) if body.has_method("get_revolver_aim") else _body_facing(body)
	if is_airborne:
		hold_airborne(ranged_weapon.airborne_hold_ticks)
	revolver_shot_requested.emit(origin, direction)

func _update_attack_direction() -> void:
	var facing := Vector3.FORWARD
	var origin := Vector3.ZERO
	var body := get_parent() as Node3D
	if body != null:
		facing = _body_facing(body)
		origin = body.global_position
	var magnetism := combo.current_node.magnetism if combo.current_node != null else 0.0
	if targeting_service != null:
		attack_direction = targeting_service.get_attack_direction(origin, facing, input_direction, magnetism)
	else:
		attack_direction = input_direction.normalized() if input_direction.length_squared() > 0.001 else facing.normalized()

func _is_heat_active() -> bool:
	return combo.current_node != null or state in [State.BLOCKING, State.PARRYING] or state == State.STAGGERED

func _body_facing(body: Node3D) -> Vector3:
	if body == null:
		return Vector3.FORWARD
	if body.has_method("get_combat_facing"):
		return body.get_combat_facing()
	return -body.global_basis.z.normalized()

func _is_battery_active() -> bool:
	return combo.current_node != null or state in [State.BLOCKING, State.PARRYING]

func _emit_event(event_name: StringName, arguments: Array) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var events := tree.root.get_node_or_null("CombatEvents")
	if events == null:
		return
	if not events.has_signal(event_name):
		return
	Callable(events, "emit_signal").callv([event_name] + arguments)

func _on_combo_advanced(weapon_id: StringName, node_id: StringName, depth: int) -> void:
	air.try_hover(combo.current_node, is_airborne)
	_emit_event(&"combo_advanced", [weapon_id, node_id, depth])

func _on_weapon_changed(previous: StringName, current: StringName) -> void:
	_emit_event(&"weapon_switched", [previous, current])

func _on_heat_changed(value: float, maximum: float) -> void:
	_emit_event(&"heat_changed", [self, value, maximum])

func _on_battery_changed(value: float, maximum: float) -> void:
	_emit_event(&"battery_changed", [value, maximum])

func _on_staggered(duration_ticks: int) -> void:
	if state == State.DEAD:
		return
	_abort_execution(&"staggered")
	combo.cancel()
	_end_aerial_follow()
	_dash_ticks_left = 0
	parry_pressed_tick = -100000
	air.clear()
	state = State.STAGGERED
	_emit_event(&"staggered", [self, duration_ticks])

func _on_stagger_ended() -> void:
	if state == State.STAGGERED:
		state = State.IDLE

func _on_player_died() -> void:
	_abort_execution(&"player_died")
	combo.cancel()
	_end_aerial_follow()
	input_buffer.clear()
	_dash_ticks_left = 0
	execution.target = null
	air.clear()
	state = State.DEAD
	_emit_event(&"player_died", [])

func _exit_tree() -> void:
	_abort_execution(&"scene_teardown")
	if execution.ended.is_connected(_on_execution_ended):
		execution.ended.disconnect(_on_execution_ended)
