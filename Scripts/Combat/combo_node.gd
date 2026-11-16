class_name ComboNode
extends Resource

@export var id: StringName
@export var display_name: String
@export var animation: StringName
@export_range(1, 3600, 1, "suffix:ticks @60Hz") var duration_ticks: int = 30
## Clip time span mapped over duration_ticks. A negative end uses the clip end.
@export_range(0.0, 600.0, 0.01, "suffix:s") var clip_start_seconds: float = 0.0
@export var clip_end_seconds: float = -1.0
## Deprecated legacy link window. New graphs author each ComboEdge.input_window.
@export_custom(PROPERTY_HINT_RANGE, "0,3600,1,suffix:ticks @60Hz") var input_window: Vector2i = Vector2i(0, 30)
## Deprecated legacy switch window; migration converts it into cancel windows.
@export_custom(PROPERTY_HINT_RANGE, "0,3600,1,suffix:ticks @60Hz") var switch_window: Vector2i = Vector2i(0, 30)
@export var cancel_windows: Array[ComboCancelWindow] = []
@export var edges: Array[ComboEdge] = []
@export var hit_specs: Array[HitSpec] = []
@export_range(0.0, 1.0) var magnetism: float = 0.0
@export var lunge_distance: float = 0.0
@export var airborne_ok: bool = true
@export var suspends_gravity: bool = false
## Free-form markers WeaponAbility resources match on (e.g. ghost_drill).
@export var tags: Array[StringName] = []
