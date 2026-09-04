extends Node3D

@export var enemy: PackedScene
@export var capacity := 10
@export var max := 5
@export var spawn_cooldown := 2.5
@export var player_target: Player

var spawned = 0
var elap = INF

func _process(delta: float) -> void:
	elap += delta
	if capacity > 0 and spawned < max and elap > spawn_cooldown:
		_spawn()

func _spawn():
	var enemy_instance = enemy.instantiate()

	enemy_instance.SPEED = 2.0
	enemy_instance.KNOCKBACK_DECELERATION = 4.0
	enemy_instance.player = player_target
	
	add_child(enemy_instance)
	enemy_instance.tree_exited.connect(_on_enemy_killed)
	
	spawned += 1
	elap = 0.0

func _on_enemy_killed():
	spawned -= 1
	capacity -= 1
	
	if capacity <= 0 and spawned == 0:
		queue_free()
