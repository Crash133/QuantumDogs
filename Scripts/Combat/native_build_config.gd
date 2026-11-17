class_name NativeBuildConfig
extends RefCounted

const GODOT_CPP_API_VERSION := "4.7"
const GODOT_CPP_TARGET := "template_debug"
const GODOT_CPP_RELEASE_TARGET := "template_release"

static func is_platform_supported(platform: String) -> bool:
	return platform in ["Windows", "Linux"]

# Release keeps its own CMake cache so switching targets never reconfigures the debug tree.
static func build_directory(native_dir: String, platform: String, target := GODOT_CPP_TARGET) -> String:
	var suffix := "" if target == GODOT_CPP_TARGET else "-release"
	match platform:
		"Windows":
			return native_dir.path_join("build/Windows-mingw" + suffix)
		"Linux":
			return native_dir.path_join("build/Linux" + suffix)
		_:
			return ""

static func expected_library_path(project_root: String, platform: String, target := GODOT_CPP_TARGET) -> String:
	match platform:
		"Windows":
			return project_root.path_join("bin/hit_manager_combat.windows.%s.x86_64.dll" % target)
		"Linux":
			return project_root.path_join("bin/libhit_manager_combat.linux.%s.x86_64.so" % target)
		_:
			return ""

static func expected_archive_path(project_root: String, platform: String, target := GODOT_CPP_TARGET) -> String:
	match platform:
		"Windows":
			return project_root.path_join("bin/libgodot-cpp.windows.%s.x86_64.a" % target)
		"Linux":
			return project_root.path_join("bin/libgodot-cpp.linux.%s.x86_64.a" % target)
		_:
			return ""

static func cmake_build_type(target := GODOT_CPP_TARGET) -> String:
	return "Debug" if target == GODOT_CPP_TARGET else "Release"

static func configure_arguments(native_dir: String, build_dir: String, platform: String, target := GODOT_CPP_TARGET) -> PackedStringArray:
	var generator := "MinGW Makefiles" if platform == "Windows" else "Unix Makefiles"
	return PackedStringArray([
		"-S", native_dir,
		"-B", build_dir,
		"-G", generator,
		"-DCMAKE_BUILD_TYPE=" + cmake_build_type(target),
		"-DHIT_MANAGER_OPTIMIZE=ON",
		"-DGODOTCPP_API_VERSION=" + GODOT_CPP_API_VERSION,
		"-DGODOTCPP_TARGET=" + target,
	])
