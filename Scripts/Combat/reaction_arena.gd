class_name ReactionArena
extends Node3D

## Authored acceptance arena for combat reactions (Saber slice). Floor, walls,
## player, camera, HitManager, FeedbackDirector, lighting and anchors are scene
## nodes; only enemies spawn dynamically under the Enemies container. Open
## Scenes/CombatReactionArena.tscn and press F6. Evidence helpers only: nothing
## here changes production combat values.

const MAX_ENEMIES := 32
const SCENARIOS: Array[StringName] = [&"common_chain", &"crowd_sweep", &"elite_openings", &"air_finish", &"wall", &"lifecycle"]

@export_group("Scene References")
@export var hit_manager: HitManagerNode
@export var player: Player
@export var camera_rig: CameraRig
@export var feedback: FeedbackDirector
@export var enemies_root: Node3D
@export var anchors_root: Node3D

@export_group("Enemy roles")
@export var common_scene: PackedScene
@export var elite_scene: PackedScene
@export var drone_scene: PackedScene

@export_group("Test settings (arena only)")
## TEST ONLY: zero uses production catalog health. A positive value keeps long
## chains alive while measuring reactions; it never applies outside this arena.
@export_range(0.0, 5000.0, 1.0) var test_health_override: float = 0.0
@export_range(1, 32) var spawn_count: int = 8
@export var scenario: StringName = &"common_chain"

var _catalog := EnemyCatalog.new()
var _contacts: Array[Dictionary] = []

func _ready() -> void:
	if hit_manager == null or player == null or camera_rig == null:
		push_error("ReactionArena: assign hit_manager, player and camera_rig in the Inspector.")
		return
	if hit_manager.native_manager == null or not hit_manager.native_manager.is_ready():
		return
	player.combat_controller.battery_drain_enabled = false
	if feedback != null:
		feedback.bind_world(self)
		feedback.bind_camera(camera_rig)
		feedback.bind_combat(get_node_or_null("/root/CombatEvents"))
		feedback.bind_hit_adapter(player.get_node_or_null("CombatHitAdapter"))
		feedback.bind_player(player)
	var events := get_node_or_null("/root/CombatEvents")
	if events != null:
		events.hit_landed.connect(_on_hit_landed)
	reset_scenario(scenario)

func _exit_tree() -> void:
	var events := get_node_or_null("/root/CombatEvents")
	if events != null and events.hit_landed.is_connected(_on_hit_landed):
		events.hit_landed.disconnect(_on_hit_landed)

## Clears the enemies and lays out `name`; unknown names warn and change nothing.
func reset_scenario(name: StringName) -> void:
	if name not in SCENARIOS:
		push_warning("Unknown reaction scenario '%s'; expected one of %s" % [name, SCENARIOS])
		return
	scenario = name
	_contacts.clear()
	for child in enemies_root.get_children():
		child.queue_free()
	player.global_position = _anchor(&"PlayerStart", Vector3.ZERO)
	match name:
		&"common_chain", &"lifecycle", &"wall", &"air_finish":
			_spawn(common_scene, &"common", _anchor(&"ChainAnchor", Vector3(0, 0, -1.3)))
		&"crowd_sweep":
			var count := clampi(spawn_count, 1, MAX_ENEMIES)
			var centre := _anchor(&"CrowdAnchor", Vector3(0, 0, -1.0))
			for i in count:
				var angle := PI * (0.2 + 0.6 * float(i) / float(maxi(1, count - 1)))
				_spawn(common_scene, &"common", centre + Vector3(cos(angle), 0.0, -sin(angle)) * (1.8 + 0.5 * float(i % 3)))
		&"elite_openings":
			_spawn(elite_scene, &"elite", _anchor(&"EliteAnchor", Vector3(0, 0, -2.2)))

## Evidence only: what the last scenario produced so far.
func get_observations() -> Dictionary:
	var alive := 0
	var states: Dictionary = {}
	for enemy in enemies_root.get_children():
		if enemy is Enemy and enemy.is_alive() and not enemy.is_queued_for_deletion():
			alive += 1
			var state := String((enemy as Enemy).reactions.presentation_state())
			states[state] = int(states.get(state, 0)) + 1
	return {
		&"scenario": scenario,
		&"enemies_alive": alive,
		&"reaction_states": states,
		&"contacts": _contacts.duplicate(true),
		&"test_health_override": test_health_override,
		&"time_scale": Engine.time_scale,
	}

func _anchor(anchor_name: StringName, fallback: Vector3) -> Vector3:
	var node := anchors_root.get_node_or_null(NodePath(String(anchor_name))) as Node3D if anchors_root != null else null
	return node.global_position if node != null else fallback

func _spawn(scene: PackedScene, role: StringName, at: Vector3) -> Enemy:
	if scene == null or enemies_root.get_child_count() >= MAX_ENEMIES:
		return null
	var enemy := scene.instantiate() as Enemy
	enemies_root.add_child(enemy)
	enemy.setup(_catalog.get_definition(role), player)
	enemy.enemy_attacks_enabled = false # Reaction evidence, not survival.
	if test_health_override > 0.0:
		var health := enemy.get_node("HealthComponent")
		health.max_health = test_health_override
		health.heal_health(test_health_override)
	enemy.global_position = at
	return enemy

func _on_hit_landed(hit: HitData, target: Object) -> void:
	if target is Enemy and enemies_root.is_ancestor_of(target) and _contacts.size() < 512:
		_contacts.append({&"tick": Engine.get_physics_frames(), &"outcome": hit.reaction_outcome, &"weapon": hit.weapon_id, &"reaction": hit.reaction_kind})
