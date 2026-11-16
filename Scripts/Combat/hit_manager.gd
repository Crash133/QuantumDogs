class_name NativeHitManager
extends RefCounted

var _native: Object

func _init(native_manager: Object = null) -> void:
	_native = native_manager
	if _native == null:
		var extension_path := "res://native/hit/hit_manager.gdextension"
		if not GDExtensionManager.is_extension_loaded(extension_path):
			GDExtensionManager.load_extension(extension_path)
	if _native == null and ClassDB.class_exists("HitManager"):
		_native = ClassDB.instantiate("HitManager")
	if _native == null:
		push_error("HitManager GDExtension is unavailable; combat hit detection cannot start")

func is_ready() -> bool:
	return _native != null

func register_hurtbox(position: Vector3, radius: float, height: float, layer: int = 1) -> int:
	return _native.register_hurtbox(position, radius, height, layer) if is_ready() else -1

func update_hurtboxes(ids: PackedInt32Array, positions: PackedVector3Array) -> void:
	if is_ready():
		_native.update_hurtboxes(ids, positions)

func unregister_hurtbox(id: int) -> void:
	if is_ready():
		_native.unregister_hurtbox(id)

func configure_hitbox(id: int, shape: StringName, size: Vector3, linger_ticks: int, decay_curve: PackedFloat32Array = PackedFloat32Array()) -> void:
	if is_ready():
		_native.configure_hitbox(id, shape, size, linger_ticks, decay_curve)

func unregister_hitbox(id: int) -> void:
	if is_ready():
		_native.unregister_hitbox(id)

func set_hitbox_mask(id: int, mask: int) -> void:
	if is_ready():
		_native.set_hitbox_mask(id, mask)

func activate_hitbox(id: int, active: bool) -> void:
	if is_ready():
		_native.activate_hitbox(id, active)

func set_hitbox_transform(id: int, transform: Transform3D) -> void:
	if is_ready():
		_native.set_hitbox_transform(id, transform)

func refresh(id: int) -> void:
	if is_ready():
		_native.refresh(id)

## Remove every lingering pose without clearing this hitbox's hit-once set.
func discard_hitbox_trails(id: int) -> void:
	if is_ready():
		_native.discard_hitbox_trails(id)

func step() -> Array:
	return _native.step() if is_ready() else []

## Advance one global collision query with local authored-tick ages per hitbox.
func step_with_ages(hitbox_ids: PackedInt32Array, age_tick_deltas: PackedFloat32Array) -> Array:
	return _native.step_with_ages(hitbox_ids, age_tick_deltas) if is_ready() else []

func get_sweep_exhaustions() -> int:
	return _native.get_sweep_exhaustions() if is_ready() else 0

func get_debug_snapshot() -> Dictionary:
	return _native.get_debug_snapshot() if is_ready() else {&"hurtboxes": [], &"hitboxes": []}

func raycast(origin: Vector3, direction: Vector3, distance: float, cone_degrees: float = 0.0, mask: int = 0xFFFFFFFF, preferred_id: int = -1) -> Dictionary:
	return _native.raycast(origin, direction, distance, cone_degrees, mask, preferred_id) if is_ready() else {}
