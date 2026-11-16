class_name CombatProjectilePool
extends Node

@export_range(1, 1024) var capacity: int = 32
var manager: HitManagerNode:
	set(value):
		if manager == value:
			return
		manager = value
		if is_inside_tree():
			_bind_manager()
var _bound_manager: HitManagerNode
var _step_callback: Callable
var _flights: Array[CombatProjectile] = []

func _ready() -> void:
	_bind_manager()

func spawn(data: CombatProjectileData, pose: Transform3D, source: Node, weapon_id: StringName) -> CombatProjectile:
	_bind_manager()
	if not is_instance_valid(manager) or manager.native_manager == null or not manager.native_manager.is_ready():
		push_warning("Projectile pool has no live native HitManager")
		return null
	if data == null or not data.is_valid() or not is_instance_valid(source) or not pose.origin.is_finite() or not pose.basis.is_finite() or absf(pose.basis.determinant()) < 0.000001:
		push_warning("Rejected unconfigured or invalid combat projectile")
		return null
	if active_count() >= clampi(capacity, 0, 1024):
		push_warning("Combat projectile pool is full")
		return null
	var flight: CombatProjectile
	for cached in _flights:
		if not cached.is_active:
			flight = cached
			break
	if flight == null:
		flight = CombatProjectile.new()
		flight.name = "CombatProjectile"
		add_child(flight)
		_flights.append(flight)
	if not flight.launch(manager, data, pose, source, weapon_id):
		return null
	return flight

func allocated_count() -> int:
	return _flights.size()

func active_count() -> int:
	var count := 0
	for flight in _flights:
		if flight.is_active:
			count += 1
	return count

func _bind_manager() -> void:
	if _bound_manager == manager:
		return
	for flight in _flights:
		flight.recycle()
	if is_instance_valid(_bound_manager) and _bound_manager.contact_step_finished.is_connected(_step_callback):
		_bound_manager.contact_step_finished.disconnect(_step_callback)
	_bound_manager = manager
	if is_instance_valid(_bound_manager):
		_step_callback = _on_contact_step_finished.bind(_bound_manager)
		_bound_manager.contact_step_finished.connect(_step_callback)

func _on_contact_step_finished(_native_usec: int, _total_usec: int, _contacts: int, stepped_manager: HitManagerNode) -> void:
	if not is_instance_valid(manager) or stepped_manager != manager:
		return
	for flight in _flights:
		# Spawns during resolution weren't present in that native batch. Their
		# lifetime begins with the next completed native step.
		if not flight.is_active or flight.born_after_step >= manager.completed_steps:
			continue
		flight.ticks_left -= manager.local_tick_delta_for(flight.time_domain_actor)
		if flight.ticks_left <= 0:
			flight.recycle()

func _exit_tree() -> void:
	for flight in _flights:
		flight.recycle()
