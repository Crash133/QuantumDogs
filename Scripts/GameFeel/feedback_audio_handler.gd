class_name FeedbackAudioHandler
extends Node

## Godot AudioStream backend for semantic cues. Its input is a FeedbackRequest
## plus a FeedbackProfile, so a future FMOD SFX handler can replace it without
## touching any event producer. Voices are bounded; warnings (priority 2+) keep
## reserved capacity and displace the oldest routine voice.

## Most routine (priority 0-1) voices at once.
@export_range(1, 32) var routine_voices: int = 10
## Most voices of any priority at once.
@export_range(1, 64) var total_voices: int = 16
## Spatial cues fall to silence at this distance in metres.
@export_range(5.0, 200.0, 1.0, "suffix:m") var max_distance: float = 45.0
## Distance in metres where a spatial cue is still at full volume.
@export_range(1.0, 50.0, 0.5, "suffix:m") var unit_size: float = 6.0

## Millisecond clock; replaced in tests.
var clock: Callable = Time.get_ticks_msec

var _world: Node
var _voices: Array[Dictionary] = []
var _last_played: Dictionary = {}
var _played: int = 0
var _suppressed: int = 0
var _peak_active: int = 0

func bind(world: Node) -> void:
	clear_level()
	_world = world

func active_count() -> int:
	return _voices.size()

func count_with_priority(priority: int) -> int:
	var count := 0
	for voice in _voices:
		if int(voice[&"priority"]) == priority:
			count += 1
	return count

func voice_nodes() -> Array:
	return _voices.map(func(voice: Dictionary) -> Variant: return voice[&"node"])

func stats() -> Dictionary:
	return {&"played": _played, &"suppressed": _suppressed, &"peak_active": _peak_active, &"active": _voices.size()}

## Returns true when a voice started.
func play(request: FeedbackRequest, profile: FeedbackProfile) -> bool:
	if request == null or profile == null or not request.is_valid() or not is_instance_valid(_world):
		return false
	var stream := _pick_stream(profile)
	if stream == null:
		return false
	var now: int = clock.call()
	var key := "%s/%s" % [profile.cue_id, profile.variant_id]
	if profile.cooldown_seconds > 0.0 and now - int(_last_played.get(key, -1000000)) < int(profile.cooldown_seconds * 1000.0):
		_suppressed += 1
		return false
	if _active_for(key) >= profile.max_active or not _admit(profile.priority):
		_suppressed += 1
		return false
	var player: Node
	if profile.audio_spatial:
		var spatial := AudioStreamPlayer3D.new()
		spatial.max_distance = max_distance
		spatial.unit_size = unit_size
		_configure(spatial, stream, profile)
		_world.add_child(spatial)
		spatial.global_position = request.resolve_position()
		player = spatial
	else:
		var flat := AudioStreamPlayer.new()
		_configure(flat, stream, profile)
		add_child(flat)
		player = flat
	player.call(&"play")
	var length_ms := int(clampf(stream.get_length(), 0.1, 4.0) * 1000.0) + 200
	_voices.append({&"node": player, &"expires": now + length_ms, &"priority": profile.priority, &"profile": key})
	_last_played[key] = now
	_played += 1
	_peak_active = maxi(_peak_active, _voices.size())
	return true

func clear_level() -> void:
	for index in range(_voices.size() - 1, -1, -1):
		_end(index)
	_last_played.clear()

func _process(_delta: float) -> void:
	var now: int = clock.call()
	for index in range(_voices.size() - 1, -1, -1):
		if not is_instance_valid(_voices[index][&"node"]) or now >= int(_voices[index][&"expires"]):
			_end(index)

func _exit_tree() -> void:
	clear_level()

func _configure(player: Node, stream: AudioStream, profile: FeedbackProfile) -> void:
	player.set(&"stream", stream)
	player.set(&"volume_db", profile.audio_volume_db)
	player.set(&"pitch_scale", randf_range(minf(profile.audio_pitch_range.x, profile.audio_pitch_range.y), maxf(profile.audio_pitch_range.x, profile.audio_pitch_range.y)))
	player.set(&"bus", profile.audio_bus if AudioServer.get_bus_index(profile.audio_bus) >= 0 else &"Master")

func _pick_stream(profile: FeedbackProfile) -> AudioStream:
	var usable: Array[AudioStream] = []
	for stream in profile.audio_streams:
		if stream != null:
			usable.append(stream)
	if usable.is_empty():
		return null
	return usable[randi() % usable.size()]

func _admit(priority: int) -> bool:
	if priority < 2:
		return _routine_count() < routine_voices and _voices.size() < total_voices
	if _voices.size() < total_voices:
		return true
	var oldest := _oldest_routine()
	if oldest < 0:
		return false
	_end(oldest)
	return true

func _routine_count() -> int:
	var count := 0
	for voice in _voices:
		if int(voice[&"priority"]) < 2:
			count += 1
	return count

func _oldest_routine() -> int:
	for index in _voices.size():
		if int(_voices[index][&"priority"]) < 2:
			return index
	return -1

func _active_for(key: String) -> int:
	var count := 0
	for voice in _voices:
		if voice[&"profile"] == key:
			count += 1
	return count

func _end(index: int) -> void:
	var node: Variant = _voices[index][&"node"]
	_voices.remove_at(index)
	if is_instance_valid(node):
		(node as Node).call(&"stop")
		(node as Node).queue_free()
