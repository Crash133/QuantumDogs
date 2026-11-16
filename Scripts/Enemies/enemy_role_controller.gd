class_name EnemyRoleController
extends Node3D

signal cue(cue_id: StringName)
signal attack_started(attack_id: StringName)
## Emitted once when a windup or active attack is cancelled by a reaction or
## parry (presentation releases its warning). Not emitted for recovery resets.
signal attack_interrupted

var enemy: Enemy
var definition: EnemyDefinition
var player_node: Node3D
var state: StringName = &"pursue"
var ticks_left: int = 0
var hitbox: HitboxProxy
var _local_tick_accumulator: float = 0.0
var _action_leases: Node
## Native hit layer of Lace's hurtbox (CombatHitAdapter); layer 1 holds enemies.
const PLAYER_HURTBOX_LAYER := 2
const AUTHORED_TICK_RATE := 60.0
## Waiting enemies hold this many engagement ranges from Lace and circle there.
const HOLD_RING_FACTOR := 2.5
## Attack slots shared by every non-elite enemy (instance id -> true).
static var _attackers: Dictionary = {}
var _holding: bool = false
const NAV_REFRESH_TICKS := 8
## A waiting enemy only steps where there is floor this far ahead of it.
const FLOOR_PROBE_METERS := 1.2
var _nav_ticks: int = 0
var _nav_direction: Vector3 = Vector3.ZERO
const TELEGRAPH_COLOR := Color(1.0, 0.22, 0.08)
## Debug/profiling switch: false skips the windup warning visuals (the windup itself is unchanged).
static var telegraphs_enabled: bool = true
static var _telegraph_outline_material: StandardMaterial3D
static var _telegraph_fill_material: StandardMaterial3D
var _telegraph_root: Node3D
var _telegraph_fill: Node3D
var _telegraph_light: OmniLight3D
var _telegraph_ranged: bool = false

func _ready() -> void:
	_action_leases = get_tree().get_first_node_in_group("combat_action_leases") as Node

func setup(new_enemy: Enemy, new_definition: EnemyDefinition, new_player: Node3D) -> void:
	enemy = new_enemy
	definition = new_definition
	player_node = new_player
	if hitbox == null and is_inside_tree():
		var manager := get_tree().get_first_node_in_group("combat_hit_managers") as HitManagerNode
		if manager != null and definition != null and definition.attack != null:
			hitbox = HitboxProxy.new()
			hitbox.manager = manager
			hitbox.owner_combatant = enemy
			hitbox.hit_spec = definition.attack.hit_spec
			hitbox.track_only_when_active = true
			hitbox.profile_shape = definition.attack.shape
			hitbox.profile_size = definition.attack.shape_size
			hitbox.position = Vector3(0.0, 0.9, -definition.attack.range_meters * 0.5)
			hitbox.collision_mask = PLAYER_HURTBOX_LAYER
			add_child(hitbox)

func request_attack() -> void:
	if _attacks_suppressed() or state != &"pursue" or definition == null or definition.attack == null:
		return
	if not _acquire_token():
		_holding = true # No free slot: wait on the ring instead of crowding Lace.
		return
	_holding = false
	state = &"windup"
	ticks_left = definition.attack.windup_ticks
	_show_telegraph()
	cue.emit(definition.attack.telegraph_cue)

func step_physics(delta: float) -> void:
	var _probe := ScriptCostProbe.start()
	step_physics_body(delta)
	ScriptCostProbe.stop(&"enemy.role", _probe)

func step_physics_body(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	_local_tick_accumulator += delta * AUTHORED_TICK_RATE
	while _local_tick_accumulator >= 1.0 - 0.000001:
		_local_tick_accumulator -= 1.0
		_step_authored_tick()

func _step_authored_tick() -> void:
	if enemy == null or not enemy.is_alive(): return
	if (enemy.reactions != null and enemy.reactions.blocks_actions()) or enemy.is_staggered():
		cancel_attack()
		return
	if _attacks_suppressed():
		cancel_attack()
		_step_movement(false)
		return
	if state == &"pursue":
		_step_movement()
		return
	enemy.direction = Vector3.ZERO
	ticks_left -= 1
	if ticks_left > 0:
		_update_telegraph()
		return
	if state == &"windup":
		_hide_telegraph()
		state = &"attack"
		ticks_left = definition.attack.active_ticks
		attack_started.emit(definition.attack.attack_id)
		if hitbox != null and enemy.enemy_attacks_enabled:
			hitbox.set_active(true)
	elif state == &"attack":
		if hitbox != null: hitbox.set_active(false)
		state = &"recovery"
		ticks_left = definition.attack.recovery_ticks
		_release_token() # A recovering enemy is no threat: free its slot for the next one.
	else:
		state = &"pursue"
		ticks_left = 0

func _step_movement(allow_attack: bool = true) -> void:
	if not is_instance_valid(player_node): return
	var to_player := player_node.global_position - enemy.global_position
	to_player.y = 0.0
	if _holding:
		if allow_attack and _token_free():
			_holding = false
		else:
			enemy.direction = _keep_on_floor(_hold_direction(to_player))
			return
	if to_player.length() <= definition.engagement_range:
		if allow_attack:
			enemy.direction = Vector3.ZERO
			request_attack()
		else:
			enemy.direction = to_player.normalized()
	else:
		enemy.direction = _chase_direction(to_player)

func _attacks_suppressed() -> bool:
	if not is_instance_valid(_action_leases):
		_action_leases = get_tree().get_first_node_in_group("combat_action_leases") as Node if is_inside_tree() else null
	return is_instance_valid(_action_leases) and _action_leases.has_method("attacks_suppressed") and bool(_action_leases.call("attacks_suppressed"))

## Stops any windup/active strike immediately; recovery resumes pursuit.
func cancel_attack() -> void:
	var was_attacking := state == &"windup" or state == &"attack"
	_end_attack()
	if was_attacking:
		attack_interrupted.emit()

func _end_attack() -> void:
	_hide_telegraph()
	if hitbox != null: hitbox.set_active(false)
	state = &"pursue"
	ticks_left = 0
	_release_token()

## True from the start of the windup to the end of the strike: the enemy stops
## tracking Lace so a sidestep or dash dodges what the telegraph shows.
func is_attack_locked() -> bool:
	return state == &"windup" or state == &"attack"

## Windup warning, owned only by enemies currently winding up (so a horde costs
## at most the attack budget). Melee: a danger zone on the floor that fills as the
## windup runs out. Ranged (drone): a flare at the muzzle that charges up.
func _show_telegraph() -> void:
	_hide_telegraph()
	if not telegraphs_enabled:
		return
	if definition == null or definition.attack == null:
		return
	var length := definition.attack.range_meters
	_telegraph_ranged = definition.attack.shape == &"capsule"
	_telegraph_root = Node3D.new()
	_telegraph_root.name = "Telegraph"
	add_child(_telegraph_root)
	if _telegraph_ranged:
		_telegraph_root.position = Vector3(0.0, 0.9, 0.0) # Cannon height.
		_telegraph_fill = Node3D.new()
		_telegraph_fill.position = Vector3(0.0, 0.0, -0.5) # Just in front of the muzzle.
		_telegraph_root.add_child(_telegraph_fill)
		var flare := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.14
		sphere.height = 0.28
		flare.mesh = sphere
		flare.material_override = _flare_material()
		flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_telegraph_fill.add_child(flare)
		_telegraph_light = OmniLight3D.new()
		_telegraph_light.light_color = TELEGRAPH_COLOR
		_telegraph_light.omni_range = 4.0
		_telegraph_light.shadow_enabled = false
		_telegraph_fill.add_child(_telegraph_light)
	else:
		var width := maxf(1.5, length)
		if _telegraph_outline_material == null:
			_telegraph_outline_material = _telegraph_material(0.07)
			_telegraph_fill_material = _telegraph_material(0.6)
		_telegraph_root.position = Vector3(0.0, 0.06, 0.0)
		_telegraph_root.add_child(_telegraph_slab(width, length, _telegraph_outline_material))
		_telegraph_fill = Node3D.new()
		_telegraph_root.add_child(_telegraph_fill)
		_telegraph_fill.add_child(_telegraph_slab(width, length, _telegraph_fill_material))
	_update_telegraph()

func _update_telegraph() -> void:
	if _telegraph_fill == null or not is_instance_valid(_telegraph_fill) or definition == null or definition.attack == null:
		return
	var windup := float(maxi(1, definition.attack.windup_ticks))
	var progress := clampf(1.0 - float(ticks_left) / windup, 0.02, 1.0)
	if _telegraph_ranged:
		# Grows and brightens, then flickers fast in the last quarter before the shot.
		var flicker := 1.0 + (0.18 if progress > 0.75 and ticks_left % 4 < 2 else 0.0)
		_telegraph_fill.scale = Vector3.ONE * lerpf(0.35, 1.7, progress) * flicker
		if _telegraph_light != null and is_instance_valid(_telegraph_light):
			_telegraph_light.light_energy = lerpf(0.4, 5.0, progress) * flicker
	else:
		_telegraph_fill.scale = Vector3(1.0, 1.0, progress)

func _hide_telegraph() -> void:
	if _telegraph_root != null and is_instance_valid(_telegraph_root):
		_telegraph_root.queue_free()
	_telegraph_root = null
	_telegraph_fill = null
	_telegraph_light = null

func _telegraph_slab(width: float, length: float, material: Material) -> MeshInstance3D:
	var slab := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, 0.02, length)
	slab.mesh = mesh
	slab.position = Vector3(0.0, 0.0, -length * 0.5)
	slab.material_override = material
	slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return slab

static func _flare_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.7, 0.4)
	material.emission_enabled = true
	material.emission = TELEGRAPH_COLOR
	material.emission_energy_multiplier = 4.0
	return material

static func _telegraph_material(alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(TELEGRAPH_COLOR.r, TELEGRAPH_COLOR.g, TELEGRAPH_COLOR.b, alpha)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _exit_tree() -> void:
	_release_token()

func _token_limit() -> int:
	if enemy == null or enemy.elite or enemy.tuning == null:
		return 0
	return enemy.tuning.enemy_max_attackers

func _token_free() -> bool:
	var limit := _token_limit()
	return limit <= 0 or _attackers.has(get_instance_id()) or _attackers.size() < limit

func _acquire_token() -> bool:
	if not _token_free():
		return false
	if _token_limit() > 0:
		_attackers[get_instance_id()] = true
	return true

func _release_token() -> void:
	_attackers.erase(get_instance_id())

## Straight at Lace while the floor is continuous, around gaps otherwise. The route is
## refreshed a few times a second (spread per enemy) and reused between refreshes.
func _chase_direction(to_player: Vector3) -> Vector3:
	var field := enemy.flow_field
	if field == null or enemy.flying:
		return to_player.normalized()
	_nav_ticks -= 1
	if _nav_ticks <= 0:
		_nav_ticks = NAV_REFRESH_TICKS + int(get_instance_id() % 4)
		_nav_direction = field.direction_to_goal(enemy.global_position, player_node.global_position)
	return _nav_direction if _nav_direction != Vector3.ZERO else to_player.normalized()

## Stops an enemy from stepping off the tile grid (ring circling would otherwise
## cut across the empty corners of plus and T shaped arenas).
func _keep_on_floor(movement: Vector3) -> Vector3:
	var field := enemy.flow_field
	if field == null or enemy.flying or movement == Vector3.ZERO:
		return movement
	if field.is_walkable(enemy.global_position + movement.normalized() * FLOOR_PROBE_METERS):
		return movement
	return Vector3.ZERO

## Keeps a waiting enemy on a ring around Lace: close in if far, back off if too
## near, otherwise circle slowly (side fixed per enemy so the crowd swirls).
func _hold_direction(to_player: Vector3) -> Vector3:
	var distance := to_player.length()
	if distance < 0.001:
		return Vector3.ZERO
	var toward := to_player / distance
	var side := 1.0 if get_instance_id() % 2 == 0 else -1.0
	var tangent := Vector3(-toward.z, 0.0, toward.x) * side
	var ring := definition.engagement_range * HOLD_RING_FACTOR
	if distance > ring * 1.15:
		return toward
	if distance < ring * 0.85:
		return (-toward + tangent * 0.5).normalized()
	return tangent * 0.5
