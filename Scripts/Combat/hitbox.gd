class_name AttackHitbox extends Area3D

@export var damage: int = 10

# The AnimationPlayer will keyframe this property!
@export var is_active: bool = false:
	set(value):
		is_active = value
		if is_active:
			_hit_objects.clear() # Reset targets when the swing starts

var _hit_objects: Array[Hurtbox] = []

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
	if area is Hurtbox and area not in _hit_objects:
		_hit_objects.append(area)
		area.apply_hit(damage)
