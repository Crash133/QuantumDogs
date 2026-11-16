class_name AttackPresentationObserver
extends Node

## Watches the authoritative ComboRunner and emits presentation-only phase cues:
## start on attack entry, trail across the authored active ticks, end on
## recovery, cancel, switch, death or teardown. One cue per
## (attacker instance, attack_serial, phase). It never emits impacts: those come
## only from resolved hits through the feedback director.
##
## Delivery: `phase_cue` always fires; `sink` (when set) receives the same
## arguments. The Game Feel integration sets `sink` to a function that builds a
## FeedbackRequest and calls FeedbackDirector.request(); this node does not
## construct director types itself.

signal phase_cue(cue_id: StringName, variant_id: StringName, phase: StringName, attack_key: String, anchor: StringName, potency: float)

var controller: CombatController
var catalog: AttackPresentationCatalog
var director: Object
var sink: Callable
var _serial: int = -1
var _profile: AttackPresentationProfile
var _sent: Dictionary = {}
var _trail_open: bool = false

func bind(new_controller: CombatController, new_director: Object, new_catalog: AttackPresentationCatalog) -> void:
	clear()
	controller = new_controller
	director = new_director
	catalog = new_catalog
	if controller != null:
		# Adopt an attack already in flight so a rebind cannot re-announce it.
		_serial = controller.combo.attack_serial if controller.combo.current_node != null else -1
		if controller.combo.current_node != null:
			_profile = _resolve()
			_mark_sent(&"start")

func clear() -> void:
	_close_trail(&"end")
	controller = null
	director = null
	catalog = null
	_profile = null
	_serial = -1

func _physics_process(_delta: float) -> void:
	var _probe := ScriptCostProbe.start()
	_physics_process_body(_delta)
	ScriptCostProbe.stop(&"presentation.attack_observer", _probe)

func _physics_process_body(_delta: float) -> void:
	if controller == null or not is_instance_valid(controller):
		return
	var node := controller.combo.current_node
	var attacking := node != null and controller.state == CombatController.State.ATTACKING
	if not attacking:
		_close_trail(&"end")
		_serial = -1
		_profile = null
		return
	if controller.combo.attack_serial != _serial:
		_close_trail(&"end") # Replaced by a chained or switched attack.
		_serial = controller.combo.attack_serial
		_profile = _resolve()
		_send(&"start")
	if _profile == null:
		return
	var span := _profile.trail_ticks(node)
	var tick := controller.combo.node_tick
	if span.x >= 0 and tick >= span.x and tick <= span.y:
		if not _trail_open:
			_trail_open = _send(&"trail")
	elif _trail_open and tick > span.y:
		_close_trail(&"end")

func _resolve() -> AttackPresentationProfile:
	if catalog == null or controller.combo.weapon == null or controller.combo.current_node == null:
		return null
	return catalog.resolve(controller.combo.weapon.id, controller.combo.current_node.id)

func _close_trail(phase: StringName) -> void:
	if _trail_open:
		_trail_open = false
		_send(phase)

func _key() -> String:
	return "%d:%d" % [controller.get_instance_id() if controller != null else 0, _serial]

func _mark_sent(phase: StringName) -> void:
	_sent["%s:%s" % [_key(), phase]] = true

func _send(phase: StringName) -> bool:
	if _profile == null or controller == null:
		return false
	var dedupe := "%s:%s" % [_key(), phase]
	if _sent.has(dedupe):
		return false
	_sent[dedupe] = true
	if _sent.size() > 512:
		_sent.clear() # Bounded: serials only grow, old keys never repeat.
		_sent[dedupe] = true
	var cue: StringName = _profile.start_cue if phase == &"start" else _profile.trail_cue if phase == &"trail" else _profile.end_cue
	var variant := _profile.variant_id if not _profile.variant_id.is_empty() else _profile.weapon_id
	phase_cue.emit(cue, variant, phase, _key(), _profile.anchor, _profile.potency)
	if sink.is_valid():
		sink.call(cue, variant, phase, _key(), _profile.anchor, _profile.potency)
	return true

func _exit_tree() -> void:
	clear()
