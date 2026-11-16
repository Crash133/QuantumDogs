class_name OptionsStore
extends RefCounted

var path := "user://ui_settings.cfg"
const DEFAULTS := {
	"master_volume": 1.0,
	"music_volume": 0.8,
	"sfx_volume": 1.0,
	"display_mode": &"windowed",
	"resolution": Vector2i(1600, 900),
	"vsync": true,
	"battery_drain_enabled": true,
	"reduce_motion": false,
}

func default_settings() -> Dictionary:
	return DEFAULTS.duplicate(true)

func load_settings() -> Dictionary:
	var settings := default_settings()
	var config := ConfigFile.new()
	if config.load(path) != OK: return settings
	for key in DEFAULTS:
		if config.has_section_key("settings", key): settings[key] = config.get_value("settings", key)
	return _validated(settings)

func save_settings(settings: Dictionary) -> Error:
	var values := _validated(settings)
	var config := ConfigFile.new()
	for key in DEFAULTS: config.set_value("settings", key, values[key])
	return config.save(path)

func _validated(values: Dictionary) -> Dictionary:
	var result := default_settings()
	for key in result:
		if values.has(key): result[key] = values[key]
	result.master_volume = clampf(float(result.master_volume), 0.0, 1.0)
	result.music_volume = clampf(float(result.music_volume), 0.0, 1.0)
	result.sfx_volume = clampf(float(result.sfx_volume), 0.0, 1.0)
	if not result.display_mode in [&"windowed", &"fullscreen", &"borderless"]: result.display_mode = &"windowed"
	if not result.resolution is Vector2i: result.resolution = Vector2i(1600, 900)
	if not [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)].has(result.resolution): result.resolution = Vector2i(1600, 900)
	result.vsync = bool(result.vsync)
	result.battery_drain_enabled = bool(result.battery_drain_enabled)
	result.reduce_motion = bool(result.reduce_motion)
	return result
