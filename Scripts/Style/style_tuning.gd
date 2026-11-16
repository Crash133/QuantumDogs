extends Resource
class_name StyleTuning

@export var max_rating: float = 100.0
@export var rank_thresholds: PackedFloat32Array = PackedFloat32Array()
@export var rank_multipliers: PackedFloat32Array = PackedFloat32Array()
@export var idle_payout_ticks: int = 180
@export var rating_decay_per_tick: float = 0.0
@export_range(0.01, 0.99, 0.01) var damage_retention_ratio: float = 0.5
