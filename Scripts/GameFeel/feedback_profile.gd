class_name FeedbackProfile
extends Resource

## Editable response for one semantic cue (and optional variant). All numbers are
## initial playtest values, not accepted balance. A handler with nothing authored
## here (no scene, no stream, zero trauma) simply does nothing.

@export_group("Identity")
## Semantic cue this profile answers, for example heavy_hit.
@export var cue_id: StringName
## Optional weapon/move/role variant. Empty means the cue's default.
@export var variant_id: StringName

@export_group("Admission")
## Higher wins when budgets are full. 0 routine, 1 accent, 2 warning and player damage, 3 strongest.
@export_range(0, 3) var priority: int = 0
## Minimum seconds between two plays of this profile (per handler).
@export_range(0.0, 5.0, 0.01, "suffix:s") var cooldown_seconds: float = 0.0
## Most simultaneous effects or voices this profile may own.
@export_range(1, 32) var max_active: int = 4

@export_group("Visual")
## Effect scenes spawned together (a PresentationEffect or any Node3D). Empty means no effect.
@export var vfx_scenes: Array[PackedScene] = []
## Uniform scale applied to the spawned effect root.
@export_range(0.1, 5.0, 0.05) var vfx_scale: float = 1.0
## Hard lifetime cap; an effect that has not released by then is freed.
@export_range(0.05, 10.0, 0.05, "suffix:s") var vfx_lifetime_cap: float = 1.0
## Effects that stay until released by their owner (enemy warnings, attack trails).
@export var vfx_sustained: bool = false

@export_group("Audio")
## One stream is picked at random per play. Empty means silent.
@export var audio_streams: Array[AudioStream] = []
## Audio bus name; falls back to Master if the bus does not exist.
@export var audio_bus: StringName = &"Master"
## True plays positionally at the request position, false plays as UI/non-spatial.
@export var audio_spatial: bool = true
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var audio_volume_db: float = 0.0
## Random pitch scale range for repeated cues.
@export var audio_pitch_range: Vector2 = Vector2(0.95, 1.05)

@export_group("Camera and time")
## Camera trauma 0..1 added through CameraShake. Zero for routine hits.
@export_range(0.0, 1.0, 0.01) var camera_trauma: float = 0.0
## Whole-game stop length in unscaled seconds. Zero never stops time.
@export_range(0.0, 0.5, 0.005, "suffix:s") var stop_duration: float = 0.0
## Time scale during the stop.
@export_range(0.0, 1.0, 0.01) var stop_scale: float = 0.05

func is_major() -> bool:
	return stop_duration > 0.0 or camera_trauma > 0.0
