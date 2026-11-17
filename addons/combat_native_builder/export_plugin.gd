@tool
class_name CombatNativeExportPlugin
extends EditorExportPlugin

const PLATFORM_FEATURES := {"windows": "Windows", "linux": "Linux"}

func _get_name() -> String:
	return "CombatNativeExport"

# Runs before Godot copies the .gdextension libraries, so the release library is fresh when packaged.
func _export_begin(features: PackedStringArray, is_debug: bool, _path: String, _flags: int) -> void:
	var target := NativeBuildConfig.GODOT_CPP_TARGET if is_debug else NativeBuildConfig.GODOT_CPP_RELEASE_TARGET
	var export_platform := ""
	for feature in PLATFORM_FEATURES:
		if features.has(feature):
			export_platform = PLATFORM_FEATURES[feature]
	if export_platform.is_empty():
		return
	var project_root := ProjectSettings.globalize_path("res://")
	if export_platform == OS.get_name():
		if not load("res://addons/combat_native_builder/plugin.gd").build_native_extension(target):
			push_error("Combat HitManager %s build failed; the export will not contain a working native library." % target)
		return
	# shortcut: no cross-compiling, build the other OS's library on that OS (or WSL) and drop it in bin/.
	var library_path := NativeBuildConfig.expected_library_path(project_root, export_platform, target)
	if not FileAccess.file_exists(library_path):
		push_error("Combat HitManager: exporting %s needs %s. Build it on %s first (open the editor there, or run CMake with -DGODOTCPP_TARGET=%s)." % [export_platform, library_path, export_platform, target])
