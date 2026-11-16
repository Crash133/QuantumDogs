class_name WeaponAbilityHost
extends Node

## Created by CombatHitAdapter. Builds runtimes for the equipped weapon's
## abilities, swaps them on weapon change and forwards combat signals.

var context := WeaponAbilityContext.new()
var runtimes: Array[WeaponAbilityRuntime] = []
var _events: Node

func setup(controller: CombatController, combatant: Node, manager: HitManagerNode) -> void:
	name = "WeaponAbilityHost"
	context.controller = controller
	context.combatant = combatant
	context.tuning = controller.tuning
	context.manager = manager
	context.host = self
	controller.combo.advanced.connect(_on_combo_advanced)
	controller.combo.weapon_changed.connect(_on_weapon_changed)
	controller.combo.cancelled.connect(_on_combo_cancelled)
	var tree := Engine.get_main_loop() as SceneTree
	_events = tree.root.get_node_or_null("CombatEvents") if tree != null else null
	if _events != null:
		if not _events.is_connected(&"hit_landed", _on_hit_landed):
			_events.connect(&"hit_landed", _on_hit_landed)
		if not _events.is_connected(&"revolver_fired", _on_revolver_fired):
			_events.connect(&"revolver_fired", _on_revolver_fired)
	_equip(controller.combo.weapon)

## Update shared context after a run build without resetting same-weapon state.
func refresh_build_context() -> void:
	if context.controller == null:
		return
	context.tuning = context.controller.tuning
	var equipped := context.controller.combo.weapon
	if equipped == null:
		_unequip()
		context.weapon = null
		return
	if context.weapon != null and context.weapon.id == equipped.id:
		context.weapon = equipped
		for runtime in runtimes:
			runtime.context = context
		return
	_unequip()
	_equip(equipped)

## A new level starts every weapon special from scratch (e.g. Saber plasma charge).
func reset_for_level() -> void:
	_unequip()
	_equip(context.controller.combo.weapon if context.controller != null else null)

func find_runtime(ability_script: Script) -> WeaponAbilityRuntime:
	for runtime in runtimes:
		if is_instance_of(runtime.ability, ability_script):
			return runtime
	return null

func tick(node: ComboNode, node_tick: int, hitboxes: Array[HitboxProxy]) -> void:
	for runtime in runtimes:
		runtime.tick(node, node_tick, hitboxes)

func _equip(weapon: WeaponData) -> void:
	context.weapon = weapon
	if weapon == null:
		return
	for ability in weapon.abilities:
		if ability == null:
			continue
		var runtime := ability.create_runtime(context)
		runtime.ability = ability
		runtime.context = context
		runtimes.append(runtime)
		runtime.equipped()

func _unequip() -> void:
	for runtime in runtimes:
		runtime.unequipped()
	runtimes.clear()

func _on_weapon_changed(_previous: StringName, _current: StringName) -> void:
	var weapon := context.controller.combo.weapon
	if weapon != null and context.weapon != null and weapon.id == context.weapon.id:
		context.weapon = weapon
		return # Reselecting the equipped weapon (even a copy) is not switching away.
	_unequip()
	_equip(context.controller.combo.weapon)

func _on_combo_advanced(_weapon_id: StringName, _node_id: StringName, _depth: int) -> void:
	var node := context.controller.combo.current_node
	for runtime in runtimes:
		runtime.attack_started(node)

func _on_hit_landed(hit: HitData, target: Object) -> void:
	if hit == null or hit.source != context.combatant or context.weapon == null or hit.weapon_id != context.weapon.id:
		return
	for runtime in runtimes:
		runtime.hit_landed(hit, target)

func _on_revolver_fired(target: Object, hit: HitData) -> void:
	if hit == null or hit.source != context.combatant or not is_instance_valid(target) or target.is_queued_for_deletion():
		return
	if target is Node3D and target.has_method("is_alive") and not bool(target.call("is_alive")):
		return
	for runtime in runtimes:
		runtime.revolver_hit(target)

# Gather-provider contract read by CombatGatherReaction on enemies/dummies.
func is_gathering() -> bool:
	for runtime in runtimes:
		if runtime.is_gathering():
			return true
	return false

func gather_position() -> Vector3:
	for runtime in runtimes:
		if runtime.is_gathering():
			return runtime.gather_position()
	return Vector3.ZERO

func signature_lunge_intent(actor_position: Vector3, delta: float) -> Dictionary:
	if context.controller == null:
		return {}
	if context.controller.state in [CombatController.State.BLOCKING, CombatController.State.PARRYING, CombatController.State.DASHING, CombatController.State.EXECUTING, CombatController.State.STAGGERED, CombatController.State.DEAD, CombatController.State.AERIAL_FOLLOW]:
		_on_combo_cancelled()
		return {}
	for runtime in runtimes:
		var intent := runtime.movement_intent(actor_position, delta)
		if bool(intent.get("active", false)):
			return intent
	return {}

func _on_combo_cancelled() -> void:
	for runtime in runtimes:
		runtime.cancel_movement()

func _exit_tree() -> void:
	if is_instance_valid(_events):
		if _events.is_connected(&"hit_landed", _on_hit_landed):
			_events.disconnect(&"hit_landed", _on_hit_landed)
		if _events.is_connected(&"revolver_fired", _on_revolver_fired):
			_events.disconnect(&"revolver_fired", _on_revolver_fired)
	for runtime in runtimes:
		runtime.released()
	if context.controller != null:
		if context.controller.combo.advanced.is_connected(_on_combo_advanced):
			context.controller.combo.advanced.disconnect(_on_combo_advanced)
		if context.controller.combo.weapon_changed.is_connected(_on_weapon_changed):
			context.controller.combo.weapon_changed.disconnect(_on_weapon_changed)
		if context.controller.combo.cancelled.is_connected(_on_combo_cancelled):
			context.controller.combo.cancelled.disconnect(_on_combo_cancelled)
	if context.controller != null and context.controller.weapon_ability_host == self:
		context.controller.weapon_ability_host = null
