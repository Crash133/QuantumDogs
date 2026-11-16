class_name NativeBuildConfig
extends RefCounted

const GODOT_CPP_API_VERSION := "4.7"
const GODOT_CPP_TARGET := "template_debug"

static func is_platform_supported(platform: String) -> bool:
	return platform in ["Windows", "Linux"]

static func build_directory(native_dir: String, platform: String) -> String:
	match platform:
		"Windows":
			return native_dir.path_join("build/Windows-mingw")
		"Linux":
			return native_dir.path_join("build/Linux")
		_:
			return ""

static func expected_library_path(project_root: String, platform: String) -> String:
	match platform:
		"Windows":
			return project_root.path_join("bin/hit_manager_combat.windows.template_debug.x86_64.dll")
		"Linux":
			return project_root.path_join("bin/libhit_manager_combat.linux.template_debug.x86_64.so")
		_:
			return ""

static func expected_archive_path(project_root: String, platform: String) -> String:
	match platform:
		"Windows":
			return project_root.path_join("bin/libgodot-cpp.windows.template_debug.x86_64.a")
		"Linux":
			return project_root.path_join("bin/libgodot-cpp.linux.template_debug.x86_64.a")
		_:
			return ""

static func configure_arguments(native_dir: String, build_dir: String, platform: String) -> PackedStringArray:
	var generator := "MinGW Makefiles" if platform == "Windows" else "Unix Makefiles"
	return PackedStringArray([
		"-S", native_dir,
		"-B", build_dir,
		"-G", generator,
		"-DCMAKE_BUILD_TYPE=Debug",
		"-DHIT_MANAGER_OPTIMIZE=ON",
		"-DGODOTCPP_API_VERSION=" + GODOT_CPP_API_VERSION,
		"-DGODOTCPP_TARGET=" + GODOT_CPP_TARGET,
	])
