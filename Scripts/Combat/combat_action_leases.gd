class_name CombatActionLeases
extends Node

@export_group("Execution Slowdown")
## Local speed for actors outside the executing player and victim.
@export_range(0.05, 1.0, 0.01, "suffix:scale") var background_scale: float = 0.2
## Wall time to ease the local slowdown in.
@export_range(0.0, 0.3, 0.01, "suffix:s") var ease_in_seconds: float = 0.04
## Wall time to restore normal local speed after release.
@export_range(0.0, 0.3, 0.01, "suffix:s") var ease_out_seconds: float = 0.12
@export var hit_manager_path: NodePath = NodePath("../../HitManager")

var time_domains: Node
var _hit_manager: HitManagerNode
var _leases: Dictionary[int, Dictionary] = {}
var _next_token: int = 1

func _enter_tree() -> void:
	add_to_group("combat_action_leases")

func _ready() -> void:
	time_domains = get_tree().get_first_node_in_group("combat_time_domains") as Node
	_hit_manager = get_node_or_null(hit_manager_path) as HitManagerNode

## Protect execution participants, suppress enemy attacks, and slow background actors.
func acquire_execution(owner: Node, player: Node, victim: Node) -> int:
	if not _live_node(owner) or not _live_node(player) or not _live_node(victim) or player == victim:
		push_warning("CombatActionLeases.acquire_execution requires distinct live owner, player and victim nodes")
		return -1
	if not is_instance_valid(time_domains) or not time_domains.has_method("acquire"):
		push_error("CombatActionLeases requires CombatTimeDomains before execution can begin")
		return -1
	if not is_instance_valid(_hit_manager) or not _hit_manager.has_method("clear_enemy_melee_attacks"):
		push_error("CombatActionLeases requires HitManagerNode to clear enemy melee hazards")
		return -1
	var token := _next_token
	_next_token += 1
	var participants: Array[Node] = [player, victim]
	var time_token := int(time_domains.call("acquire", owner, participants, background_scale, ease_in_seconds, ease_out_seconds))
	if time_token < 0:
		return -1
	_leases[token] = {
		&"owner": weakref(owner),
		&"player": weakref(player),
		&"victim": weakref(victim),
		&"time_token": time_token,
	}
	_suppress_current_enemy_attacks()
	return token

## Release only this action token; any overlapping action still owns its protections.
func release(token: int) -> void:
	if not _leases.has(token):
		return
	var lease: Dictionary = _leases[token]
	_leases.erase(token)
	var time_token := int(lease[&"time_token"])
	if time_token > 0 and is_instance_valid(time_domains):
		time_domains.call("release", time_token)

func attacks_suppressed() -> bool:
	_prune_invalid_owners()
	return not _leases.is_empty()

func is_protected(actor: Node) -> bool:
	if not _live_node(actor):
		return false
	_prune_invalid_owners()
	for lease: Dictionary in _leases.values():
		if _weak_node_is(lease[&"player"], actor) or _weak_node_is(lease[&"victim"], actor):
			return true
	return false

## The reserved victim is held in place and its stagger/eligibility clocks pause
## until execution recovery releases this exact action lease.
func is_execution_victim(actor: Node) -> bool:
	if not _live_node(actor):
		return false
	_prune_invalid_owners()
	for lease: Dictionary in _leases.values():
		if _weak_node_is(lease[&"victim"], actor):
			return true
	return false

func gravity_held(actor: Node) -> bool:
	return is_protected(actor)

## Release all protections held by this service when the run resets.
func reset() -> void:
	for token in _leases.keys():
		release(int(token))

func _physics_process(_delta: float) -> void:
	var _probe := ScriptCostProbe.start()
	_physics_process_body(_delta)
	ScriptCostProbe.stop(&"combat.action_leases", _probe)

func _physics_process_body(_delta: float) -> void:
	_prune_invalid_owners()

func _exit_tree() -> void:
	for token in _leases.keys():
		release(int(token))

func _suppress_current_enemy_attacks() -> void:
	if not is_inside_tree():
		return
	for enemy in get_tree().get_nodes_in_group("enemy_combatants"):
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		var role := enemy.get_node_or_null("RoleController")
		if role != null and role.has_method("cancel_attack"):
			role.cancel_attack()
	if is_instance_valid(_hit_manager):
		_hit_manager.clear_enemy_melee_attacks()

func _prune_invalid_owners() -> void:
	for token in _leases.keys():
		var lease: Dictionary = _leases[token]
		if _weak_node_is_live(lease[&"owner"]) and _weak_node_is_live(lease[&"player"]) and _weak_node_is_live(lease[&"victim"]):
			continue
		release(int(token))

func _live_node(node: Node) -> bool:
	return node != null and is_instance_valid(node) and not node.is_queued_for_deletion()

func _weak_node_is(reference: WeakRef, node: Node) -> bool:
	if reference == null or not _live_node(node):
		return false
	var value: Object = reference.get_ref()
	return is_instance_valid(value) and value == node

func _weak_node_is_live(reference: WeakRef) -> bool:
	if reference == null:
		return false
	var value: Object = reference.get_ref()
	return is_instance_valid(value) and value is Node and not (value as Node).is_queued_for_deletion()
