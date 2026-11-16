class_name CombatTimeDomains
extends Node

const NORMAL_SCALE := 1.0

var _leases: Dictionary[int, Dictionary] = {}
var _next_token: int = 1

func _enter_tree() -> void:
	add_to_group("combat_time_domains")

## Apply a local slowdown to actors outside participants. Participant references
## and owner are weak; deleting the owner releases the lease automatically.
func acquire(owner: Node, participants: Array[Node], scale: float, ease_in: float, ease_out: float) -> int:
	if owner == null or not is_instance_valid(owner) or owner.is_queued_for_deletion():
		push_warning("CombatTimeDomains.acquire requires a live owner")
		return -1
	if not is_finite(scale) or scale < 0.01 or scale > NORMAL_SCALE:
		push_warning("CombatTimeDomains scale must be finite and in [0.01, 1.0]")
		return -1
	if not is_finite(ease_in) or not is_finite(ease_out) or ease_in < 0.0 or ease_out < 0.0:
		push_warning("CombatTimeDomains ease durations must be finite and nonnegative")
		return -1
	var participant_refs: Array[WeakRef] = []
	for participant in participants:
		if participant != null and is_instance_valid(participant) and not participant.is_queued_for_deletion():
			participant_refs.append(weakref(participant))
	var token := _next_token
	_next_token += 1
	_leases[token] = {
		&"owner": weakref(owner),
		&"participants": participant_refs,
		&"scale": scale,
		&"ease_in": ease_in,
		&"ease_out": ease_out,
		&"elapsed": 0.0,
		&"releasing": false,
		&"release_elapsed": 0.0,
		&"release_from": NORMAL_SCALE,
	}
	return token

## Begin easing this token back to normal. Releasing one token leaves overlaps active.
func release(token: int) -> void:
	if not _leases.has(token):
		return
	var lease: Dictionary = _leases[token]
	if bool(lease[&"releasing"]):
		return
	lease[&"release_from"] = _factor_from_lease(lease)
	lease[&"releasing"] = true
	lease[&"release_elapsed"] = 0.0
	if float(lease[&"ease_out"]) <= 0.0:
		_leases.erase(token)

## Return the strongest active local slowdown that applies to actor.
func factor_for(actor: Node) -> float:
	if actor == null or not is_instance_valid(actor) or actor.is_queued_for_deletion():
		return NORMAL_SCALE
	var result := NORMAL_SCALE
	for token in _leases.keys():
		var lease: Dictionary = _leases[token]
		if not _lease_owner_is_live(lease):
			_leases.erase(token)
			continue
		if _is_participant(lease, actor):
			continue
		result = minf(result, _factor_from_lease(lease))
	return clampf(result, 0.01, NORMAL_SCALE)

## Drop every local-time lease immediately, for run reset and scene teardown.
func reset() -> void:
	_leases.clear()

func _process(delta: float) -> void:
	var _probe := ScriptCostProbe.start()
	_process_body(delta)
	ScriptCostProbe.stop(&"combat.time_domains", _probe)

func _process_body(delta: float) -> void:
	var safe_delta := delta if is_finite(delta) and delta > 0.0 else 0.0
	for token in _leases.keys():
		var lease: Dictionary = _leases[token]
		if not _lease_owner_is_live(lease):
			_leases.erase(token)
			continue
		if bool(lease[&"releasing"]):
			lease[&"release_elapsed"] = float(lease[&"release_elapsed"]) + safe_delta
			if float(lease[&"release_elapsed"]) >= float(lease[&"ease_out"]):
				_leases.erase(token)
		else:
			lease[&"elapsed"] = float(lease[&"elapsed"]) + safe_delta

func _lease_owner_is_live(lease: Dictionary) -> bool:
	var owner_ref: WeakRef = lease.get(&"owner")
	if owner_ref == null:
		return false
	var owner: Object = owner_ref.get_ref()
	return is_instance_valid(owner) and owner is Node and not owner.is_queued_for_deletion()

func _is_participant(lease: Dictionary, actor: Node) -> bool:
	for participant_ref: WeakRef in lease[&"participants"]:
		var participant: Object = participant_ref.get_ref()
		if is_instance_valid(participant) and participant == actor:
			return true
	return false

func _factor_from_lease(lease: Dictionary) -> float:
	if bool(lease[&"releasing"]):
		var duration := float(lease[&"ease_out"])
		if duration <= 0.0:
			return NORMAL_SCALE
		var progress := clampf(float(lease[&"release_elapsed"]) / duration, 0.0, 1.0)
		return lerpf(float(lease[&"release_from"]), NORMAL_SCALE, _smoothstep(progress))
	var duration := float(lease[&"ease_in"])
	if duration <= 0.0:
		return float(lease[&"scale"])
	var progress := clampf(float(lease[&"elapsed"]) / duration, 0.0, 1.0)
	return lerpf(NORMAL_SCALE, float(lease[&"scale"]), _smoothstep(progress))

func _smoothstep(value: float) -> float:
	return value * value * (3.0 - 2.0 * value)
