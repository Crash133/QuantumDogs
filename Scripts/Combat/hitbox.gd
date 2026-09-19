class_name AttackHitbox extends Area3D

@export var hit_data: HitData

@export var is_active: bool = false:
	set(value):
		if value == is_active:
			return
			
		is_active = value
		
		if is_active:
			_hit_entities.clear() # Reset targets when the swing starts

signal attacked(hit: HitData, target: Hurtbox, hit_position: Vector3)

var _hit_entities: Dictionary = {}

func _ready() -> void:
	area_entered.connect(_on_area_entered)

# Continuously check while active (catches enemies moving into the hitbox)
func _physics_process(_delta: float) -> void:
	if not is_active: 
		return
		
	for area in get_overlapping_areas():
		_try_hit(area)

# Catch enemies if the hitbox moves into them
func _on_area_entered(area: Area3D) -> void:
	if is_active:
		_try_hit(area)

func _try_hit(area: Area3D) -> void:
	if not area is Hurtbox:
		return

	var hurtbox := area as Hurtbox

	if not _can_hit(hurtbox):
		return

	_register_hit(hurtbox)
	
	var hit_position := hurtbox.global_position
	
	hurtbox.apply_hit(hit_data)
	
	attacked.emit(hit_data, hurtbox, hit_position)


func _can_hit(hurtbox: Hurtbox) -> bool:
	var entity := hurtbox.owner_entity

	if entity == null:
		return false

	match hit_data.hit_policy:
		HitData.HitPolicy.ONCE:
			return not _hit_entities.has(entity)

		HitData.HitPolicy.MULTI_HIT:
			return true

		HitData.HitPolicy.COOLDOWN:
			if not _hit_entities.has(entity):
				return true

			var last_hit_time: int = _hit_entities[entity]

			return Time.get_ticks_msec() - last_hit_time \
				>= hit_data.hit_cooldown * 1000.0

	return false
	
func _register_hit(hurtbox: Hurtbox) -> void:
	var entity := hurtbox.owner_entity

	if entity == null:
		return

	_hit_entities[entity] = Time.get_ticks_msec()
	
func _get_hit_entity(hurtbox: Hurtbox) -> Node:
	return hurtbox.owner_entity
